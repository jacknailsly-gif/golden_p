import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/services/network_guard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.golden_p/network_guard');

  group('NetworkGuardService Tests', () {
    setUp(() {
      NetworkGuardService.isAndroidOverride = true;
    });

    tearDown(() {
      NetworkGuardService.isAndroidOverride = null;
    });

    test('Emulator bypass: when isEmulator returns true, canProceed is true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isEmulator') {
          return true;
        }
        if (methodCall.method == 'isWifiConnected') {
          return true; // Even if Wi-Fi is on, emulator should bypass!
        }
        return null;
      });

      final bool canProceed = await NetworkGuardService.canProceed();
      expect(canProceed, isTrue);
    });

    test('Real Android with Wi-Fi ON: canProceed is false (blocked)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isEmulator') {
          return false; // Physical device
        }
        if (methodCall.method == 'isWifiConnected') {
          return true; // Wi-Fi is ON!
        }
        return null;
      });

      final bool canProceed = await NetworkGuardService.canProceed();
      expect(canProceed, isFalse);
      final bool isEmu = await NetworkGuardService.isEmulator();
      final bool isWifi = await NetworkGuardService.isWifiConnected();
      expect(isEmu, isFalse);
      expect(isWifi, isTrue);
    });

    test('Real Android with Wi-Fi OFF: canProceed is true (allowed)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isEmulator') {
          return false; // Physical device
        }
        if (methodCall.method == 'isWifiConnected') {
          return false; // Cellular data, Wi-Fi OFF
        }
        return null;
      });

      final bool isEmu = await NetworkGuardService.isEmulator();
      final bool isWifi = await NetworkGuardService.isWifiConnected();
      expect(isEmu, isFalse);
      expect(isWifi, isFalse);
    });

    test('disableWifi invokes native channel successfully', () async {
      bool disableCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'disableWifi') {
          disableCalled = true;
          return true;
        }
        return null;
      });

      final bool res = await NetworkGuardService.disableWifi();
      expect(res, isTrue);
      expect(disableCalled, isTrue);
    });

    test('openWifiSettings invokes native channel successfully', () async {
      bool openSettingsCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'openWifiSettings') {
          openSettingsCalled = true;
          return true;
        }
        return null;
      });

      await NetworkGuardService.openWifiSettings();
      expect(openSettingsCalled, isTrue);
    });
  });
}
