import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/services/user_agent_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserAgentService Stealth & Device Spoofing Suite', () {
    test('Sanitizes real OPPO Reno 8T WebView User-Agent to pure Chrome Mobile', () {
      const rawOppoUa =
          'Mozilla/5.0 (Linux; U; Android 14; th-th; CPH2505 Build/UKQ1.230924.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36';

      final sanitized = UserAgentService.sanitizeUserAgent(rawOppoUa);
      final model = UserAgentService.extractDeviceModel(sanitized);

      // Verify removal of WebView signatures
      expect(sanitized.contains('Version/4.0'), isFalse);
      expect(sanitized.contains('; wv'), isFalse);
      expect(sanitized.contains('U;'), isFalse);

      // Verify real device model retention
      expect(sanitized.contains('CPH2505'), isTrue);
      expect(model, equals('CPH2505'));

      // Verify Chrome Mobile signature
      expect(sanitized.contains('Chrome/130.0.0.0 Mobile Safari/537.36'), isTrue);
    });

    test('Sanitizes real Samsung Galaxy S24 WebView User-Agent to pure Chrome Mobile', () {
      const rawSamsungUa =
          'Mozilla/5.0 (Linux; U; Android 14; en-us; SM-S921B Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36';

      final sanitized = UserAgentService.sanitizeUserAgent(rawSamsungUa);
      final model = UserAgentService.extractDeviceModel(sanitized);

      // Verify removal of WebView signatures
      expect(sanitized.contains('Version/4.0'), isFalse);
      expect(sanitized.contains('; wv'), isFalse);
      expect(sanitized.contains('U;'), isFalse);

      // Verify real Samsung model retention
      expect(sanitized.contains('SM-S921B'), isTrue);
      expect(model, equals('SM-S921B'));

      // Verify Chrome Mobile signature
      expect(sanitized.contains('Chrome/130.0.0.0 Mobile Safari/537.36'), isTrue);
    });

    test('Replaces generic Chrome reduction "K" with realistic fallback model', () {
      const rawReducedUa =
          'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

      final sanitized = UserAgentService.sanitizeUserAgent(rawReducedUa);
      expect(sanitized.contains('CPH2505'), isTrue);
      expect(sanitized.contains(' K)'), isFalse);
    });

    test('Replaces emulator User-Agent with realistic fallback model', () {
      const rawEmulatorUa =
          'Mozilla/5.0 (Linux; U; Android 14; sdk_gphone64_arm64 Build/TE1A.220922.010; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36';

      final sanitized = UserAgentService.sanitizeUserAgent(rawEmulatorUa);
      expect(sanitized.contains('CPH2505'), isTrue);
      expect(sanitized.contains('sdk_gphone'), isFalse);
    });

    test('Client Hints JavaScript script contains active model and purges bridge', () {
      final script = UserAgentService.clientHintsScript;
      expect(script.contains('delete window.flutter_inappwebview'), isTrue);
      expect(script.contains('navigator.userAgentData'), isTrue);
      expect(script.contains(UserAgentService.currentModel), isTrue);
      expect(script.contains("navigator, 'webdriver'"), isTrue);
      expect(script.contains('get: () => undefined'), isTrue);
    });

    test('Client Hints JavaScript script masks navigator.webdriver to return undefined', () {
      final script = UserAgentService.clientHintsScript;
      expect(script.contains('navigator.webdriver'), isTrue);
      expect(script.contains('undefined'), isTrue);
      expect(script.contains("Object.defineProperty(navigator, 'webdriver'"), isTrue);
      expect(script.contains("Object.defineProperty(window.Navigator.prototype, 'webdriver'"), isTrue);
    });

    test('initialUserScripts provides AT_DOCUMENT_START injection', () {
      final scripts = UserAgentService.initialUserScripts;
      expect(scripts.isNotEmpty, isTrue);
      expect(scripts.first.source.contains(UserAgentService.currentModel), isTrue);
      expect(scripts.first.source.contains('navigator.webdriver'), isTrue);
    });
  });
}
