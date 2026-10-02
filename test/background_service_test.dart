import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/services/network_guard_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.golden_p/network_guard');

  group('Background Service Tests', () {
    setUp(() {
      NetworkGuardService.isAndroidOverride = true;
    });

    tearDown(() {
      NetworkGuardService.isAndroidOverride = null;
    });

    test('startBackgroundService invokes native channel method', () async {
      bool startCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'startBackgroundService') {
          startCalled = true;
          return true;
        }
        return null;
      });

      final bool success = await NetworkGuardService.startBackgroundService();
      expect(success, isTrue);
      expect(startCalled, isTrue);
    });

    test('stopBackgroundService invokes native channel method', () async {
      bool stopCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'stopBackgroundService') {
          stopCalled = true;
          return true;
        }
        return null;
      });

      final bool success = await NetworkGuardService.stopBackgroundService();
      expect(success, isTrue);
      expect(stopCalled, isTrue);
    });

    test('isBackgroundServiceRunning queries native channel status', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'isBackgroundServiceRunning') {
          return true;
        }
        return null;
      });

      final bool isRunning = await NetworkGuardService.isBackgroundServiceRunning();
      expect(isRunning, isTrue);
    });
  });
}
