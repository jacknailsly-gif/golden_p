import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NetworkGuardService {
  static const MethodChannel _channel = MethodChannel('com.example.golden_p/network_guard');

  @visibleForTesting
  static bool? isAndroidOverride;

  static bool get _isAndroid => isAndroidOverride ?? Platform.isAndroid;
  static bool _handlerInitialized = false;

  static void _initMethodChannelHandler() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWifiStateChanged') {
        final bool isBlocked = call.arguments as bool? ?? false;
        if (await isEmulator()) {
          isWifiBlockedNotifier.value = false;
          return;
        }
        isWifiBlockedNotifier.value = isBlocked;
        if (isBlocked) {
          debugPrint('[NETWORK GUARD] Native event: Wi-Fi detected! Triggering instant auto-disable...');
          await disableWifi();
        }
      }
    });
  }

  /// ตรวจสอบว่ากำลังรันบน Emulator หรือไม่ (User Directive: บน Emulator ใช้ปกติได้)
  static Future<bool> isEmulator() async {
    if (!_isAndroid) return true; // Desktop/Testing treated as emulator
    try {
      final bool? result = await _channel.invokeMethod<bool>('isEmulator');
      return result ?? false;
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error checking emulator: $e');
      return false;
    }
  }

  /// ตรวจสอบว่ามีการเชื่อมต่อ Wi-Fi อยู่หรือไม่
  static Future<bool> isWifiConnected() async {
    if (!_isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('isWifiConnected');
      return result ?? false;
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error checking Wi-Fi: $e');
      return false;
    }
  }

  /// เปิดหน้าต่างการตั้งค่า Wi-Fi บน Android
  static Future<void> openWifiSettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openWifiSettings');
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error opening Wi-Fi settings: $e');
    }
  }

  /// สั่งปิด Wi-Fi บนเครื่อง Android โดยตรง
  static Future<bool> disableWifi() async {
    if (!_isAndroid) return true;
    if (await isEmulator()) return true; // 🛡️ บน Emulator ไม่ปิด Wi-Fi ให้ทำงานได้ปกติ 100%
    try {
      final bool? res = await _channel.invokeMethod<bool>('disableWifi');
      return res ?? false;
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error disabling Wi-Fi: $e');
      return false;
    }
  }

  static Timer? _monitorTimer;
  static final ValueNotifier<bool> isWifiBlockedNotifier = ValueNotifier<bool>(false);

  /// เริ่มระบบตรวจสอบ Wi-Fi ต่อเนื่องตลอดเวลาที่แอปเปิดทำงาน (User Directive ข้อ 1)
  /// "ในขณะที่เปิดแอป golden_p จะไม่สามารถเปิด Wifi ได้เช่นกัน"
  /// ตรวจสอบทุก 300ms และสั่งปิด Wi-Fi ทันทีอัตโนมัติหากพบว่าถูกเปิด (เว้นแต่ Emulator)
  static void startContinuousMonitoring({Function(bool isBlocked)? onStatusChange}) {
    _initMethodChannelHandler();
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (await isEmulator()) {
        if (isWifiBlockedNotifier.value != false) {
          isWifiBlockedNotifier.value = false;
          onStatusChange?.call(false);
        }
        return;
      }
      final bool allowed = await canProceed();
      final bool blocked = !allowed;
      if (isWifiBlockedNotifier.value != blocked) {
        isWifiBlockedNotifier.value = blocked;
        onStatusChange?.call(blocked);
      }
      if (blocked) {
        debugPrint('[NETWORK GUARD] 🚨 Wi-Fi active while app running! Forcing auto-disable...');
        await disableWifi();
      }
    });
  }

  static void stopContinuousMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  /// ตรวจสอบเงื่อนไขตามคำสั่งผู้ใช้:
  /// - ข้อ 3: ติดตั้งบน Emulator ให้ใช้งานได้ปกติ (bypass = true)
  /// - ข้อ 2: ติดตั้งบน Android เครื่องจริง ตรวจสอบว่าเปิด Wi-Fi หรือไม่ ถ้าเปิดต้องปิดก่อนถึงจะเปิดแอปได้ปกติ (canProceed = false)
  static Future<bool> canProceed() async {
    if (!_isAndroid) return true;
    final bool emulator = await isEmulator();
    if (emulator) {
      return true;
    }

    final bool wifi = await isWifiConnected();
    if (wifi) {
      return false;
    }

    return true;
  }

  /// 🛡️ เริ่มต้น Foreground Service เพื่อให้บอททำงานต่อเนื่องในพื้นหลัง 100% (แม้สลับไปแอปอื่น)
  static Future<bool> startBackgroundService() async {
    if (!_isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('startBackgroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error starting background service: $e');
      return false;
    }
  }

  /// 🛡️ สั่งหยุด Foreground Service เมื่อหยุดบอท เพื่อคืนค่าทรัพยากร
  static Future<bool> stopBackgroundService() async {
    if (!_isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>('stopBackgroundService');
      return result ?? false;
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error stopping background service: $e');
      return false;
    }
  }

  /// 🛡️ ตรวจสอบสถานะการทำงานของ Background Service
  static Future<bool> isBackgroundServiceRunning() async {
    if (!_isAndroid) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('isBackgroundServiceRunning');
      return result ?? false;
    } catch (e) {
      debugPrint('[NETWORK GUARD] Error checking background service: $e');
      return false;
    }
  }
}
