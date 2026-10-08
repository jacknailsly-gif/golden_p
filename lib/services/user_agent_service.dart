import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// บริการจัดการและปรับแต่ง User-Agent และ Client Hints (Stealth / Device Spoofing)
/// เพื่อลบลายเซ็น Android WebView (เช่น 'Version/4.0' และ '; wv')
/// และแปลงเป็น Chrome Mobile เครื่องจริง (เช่น OPPO Reno8 T หรือ Samsung S24) 100%
class UserAgentService {
  static const String fallbackModel = 'CPH2505'; // OPPO Reno8 T 5G
  static const String fallbackUserAgent =
      'Mozilla/5.0 (Linux; Android 14; CPH2505 Build/UKQ1.230924.001) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  static String _currentUserAgent = fallbackUserAgent;
  static String _currentModel = fallbackModel;
  static bool _initialized = false;

  /// ดึง User-Agent ปัจจุบันที่ผ่านการทำความสะอาดแล้ว
  static String get currentUserAgent => _currentUserAgent;

  /// ดึงชื่อรุ่นเครื่องปัจจุบัน (Device Model)
  static String get currentModel => _currentModel;

  /// เริ่มต้นบริการ โดยดึง default User-Agent จาก Android ระบบจริง
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final defaultUa = await InAppWebViewController.getDefaultUserAgent();
      if (defaultUa.isNotEmpty) {
        _currentUserAgent = sanitizeUserAgent(defaultUa);
        _currentModel = extractDeviceModel(_currentUserAgent);
        debugPrint('[USER-AGENT] 📱 Initialized Real Device UA: $_currentUserAgent');
        debugPrint('[USER-AGENT] 🏷️ Detected Model: $_currentModel');
      } else {
        _useFallback();
      }
    } catch (e) {
      debugPrint('[USER-AGENT] ⚠️ Failed to get system UA, using fallback ($e)');
      _useFallback();
    }
    _initialized = true;
  }

  static void _useFallback() {
    _currentUserAgent = fallbackUserAgent;
    _currentModel = fallbackModel;
  }

  /// ทำความสะอาด User-Agent ดั้งเดิมของ WebView ให้กลายเป็น Chrome Mobile แท้
  static String sanitizeUserAgent(String rawUa) {
    if (rawUa.trim().isEmpty) {
      return fallbackUserAgent;
    }

    String ua = rawUa;

    // 1. ลบ Version/4.0 (Signature ที่ทำให้เว็บมองเป็น Safari 4.0 Android)
    ua = ua.replaceAll(RegExp(r'Version\/\d+\.\d+\s*'), '');

    // 2. ลบ WebView tag (; wv หรือ ;wv)
    ua = ua.replaceAll(RegExp(r';\s*wv\b'), '');

    // 3. ลบ Encryption token รุ่นเก่า U; ใน Linux; U; Android
    ua = ua.replaceAll(RegExp(r'\bU;\s*'), '');

    // 4. ลบภาษาท้องถิ่นที่ไม่จำเป็นในวงเล็บ OS เช่น '; th-th;' หรือ '; en-us;'
    ua = ua.replaceAll(RegExp(r';\s*[a-z]{2}(-[a-z]{2,4})?;\s*', caseSensitive: false), '; ');

    // 5. ทำความสะอาดช่องว่างและ Semicolon ซ้ำ
    ua = ua.replaceAll(RegExp(r';\s*;'), ';');
    ua = ua.replaceAll(RegExp(r'\(\s*;'), '(');
    ua = ua.replaceAll(RegExp(r';\s*\)'), ')');
    ua = ua.replaceAll(RegExp(r'\s{2,}'), ' ');

    // 6. ตรวจสอบว่าโมเดลเครื่องเป็น Emulator หรือ Generic 'K' หรือไม่
    final extracted = extractDeviceModel(ua);
    final isEmulatorOrGeneric = extracted.isEmpty ||
        extracted == 'K' ||
        extracted.toLowerCase().contains('sdk_gphone') ||
        extracted.toLowerCase().contains('generic') ||
        extracted.toLowerCase().contains('emulator');

    if (isEmulatorOrGeneric) {
      // แทนที่ด้วย OPPO Reno8 T จริง
      return fallbackUserAgent;
    }

    return ua.trim();
  }

  /// ดึงชื่อ Device Model จาก User-Agent string
  static String extractDeviceModel(String ua) {
    final osMatch = RegExp(r'\(([^)]+)\)').firstMatch(ua);
    if (osMatch == null) return fallbackModel;

    final parts = osMatch.group(1)?.split(';') ?? [];
    if (parts.length >= 3) {
      // ตัวอย่าง: Linux; Android 14; CPH2505 Build/...
      final candidate = parts.last.trim();
      final modelPart = candidate.split('Build/').first.trim();
      if (modelPart.isNotEmpty) {
        return modelPart;
      }
    } else if (parts.length == 2) {
      final candidate = parts[1].trim();
      final modelPart = candidate.split('Build/').first.trim();
      if (modelPart.isNotEmpty && !modelPart.startsWith('Android')) {
        return modelPart;
      }
    }
    return fallbackModel;
  }

  /// JavaScript Script สำหรับ Inject เข้า DOM เพื่อ Spoof navigator.userAgentData (Client Hints)
  static String get clientHintsScript {
    final model = _currentModel;
    return """
(function() {
  try {
    // 🛡️ 1. ลบ In-App WebView Bridge ไม่ให้เว็บตรวจพบ (SEC-04)
    if ('flutter_inappwebview' in window) {
      delete window.flutter_inappwebview;
    }
    if ('_flutter_inappwebview' in window) {
      delete window._flutter_inappwebview;
    }
  } catch(e) {}

  // 🛡️ 2. Spoof navigator.userAgentData ให้ส่งโมเดลเครื่องจริงเสมอ
  try {
    if (navigator.userAgentData) {
      var origGetHighEntropy = navigator.userAgentData.getHighEntropyValues;
      if (origGetHighEntropy) {
        navigator.userAgentData.getHighEntropyValues = function(hints) {
          return origGetHighEntropy.call(navigator.userAgentData, hints).then(function(res) {
            if (hints && hints.indexOf('model') !== -1) {
              res.model = "$model";
            }
            return res;
          }).catch(function() {
            return {
              architecture: "arm",
              bitness: "64",
              brands: navigator.userAgentData.brands,
              mobile: true,
              model: "$model",
              platform: "Android",
              platformVersion: "14.0.0"
            };
          });
        };
      }
    }
  } catch(e) {}

  // 🛡️ 3. ปรับปรุง navigator.webdriver ให้แนบเนียนสมบูรณ์ (SEC-03)
  // ใน Android Chrome Mobile แท้ navigator.webdriver มีค่าเป็น false (ไม่ใช่ undefined)
  // กำหนดอย่างสะอาดโดยไม่แตะต้องหรือ Override Function.prototype.toString (เพื่อความปลอดภัยสูงสุดต่อ Turnstile)
  try {
    try {
      if (Object.prototype.hasOwnProperty.call(navigator, 'webdriver')) {
        delete navigator.webdriver;
      }
    } catch(e) {}

    var webdriverGetter = function webdriver() {
      return false;
    };

    try {
      Object.defineProperty(webdriverGetter, 'name', { value: 'get webdriver', configurable: true });
    } catch(e) {}

    if (window.Navigator && window.Navigator.prototype) {
      Object.defineProperty(window.Navigator.prototype, 'webdriver', {
        get: webdriverGetter,
        enumerable: true,
        configurable: true
      });
    }

    try {
      Object.defineProperty(navigator, 'webdriver', {
        get: webdriverGetter,
        enumerable: true,
        configurable: true
      });
    } catch(e) {}
  } catch(e) {}

  // 🛡️ 4. Mobile Touch Points & Sensor Stealth (SEC-09)
  // กำหนด navigator.maxTouchPoints ให้คืนค่า 5 ตรงตามหน้าจอมือถือ Capacitive Multi-touch Android แท้
  try {
    Object.defineProperty(navigator, 'maxTouchPoints', {
      get: () => 5,
      configurable: true,
      enumerable: true
    });
    if (window.Navigator && window.Navigator.prototype) {
      Object.defineProperty(window.Navigator.prototype, 'maxTouchPoints', {
        get: () => 5,
        configurable: true,
        enumerable: true
      });
    }
  } catch(e) {}

  // รับประกันความพร้อมของ DeviceOrientationEvent เพื่อยืนยันคุณสมบัติอุปกรณ์มือถือ
  try {
    if (typeof window.DeviceOrientationEvent === 'undefined') {
      window.DeviceOrientationEvent = function DeviceOrientationEvent() {};
    }
  } catch(e) {}

  // 🛡️ 5. Emulate window.chrome object for Chrome Mobile realism (Turnstile / FingerprintJS stealth)
  try {
    if (typeof window.chrome === 'undefined') {
      window.chrome = {
        app: {
          isInstalled: false,
          InstallState: { DISABLED: "disabled", INSTALLED: "installed", NOT_INSTALLED: "not_installed" },
          RunningState: { CANNOT_RUN: "cannot_run", READY_TO_RUN: "ready_to_run", RUNNING: "running" }
        },
        csi: function() {},
        loadTimes: function() {}
      };
    }
  } catch(e) {}
})();
""";
  }

  /// คืนค่า UserScript สำหรับใส่ใน initialUserScripts ตอนเริ่ม WebView ทันที
  static UnmodifiableListView<UserScript> get initialUserScripts {
    return UnmodifiableListView<UserScript>([
      UserScript(
        source: clientHintsScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]);
  }
}
