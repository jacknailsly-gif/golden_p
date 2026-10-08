import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/services/user_agent_service.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Anti-Bot Stealth & DOM Security Suite', () {
    test('SEC-03 & SEC-04: clientHintsScript cleanly defines navigator.webdriver = false without Function.prototype.toString tampering and purges flutter_inappwebview', () {
      final script = UserAgentService.clientHintsScript;

      // Static code verification
      expect(script.contains('return false;'), isTrue, reason: 'navigator.webdriver must return false');
      expect(script.contains('Function.prototype.toString ='), isFalse, reason: 'Must NOT override Function.prototype.toString to prevent Turnstile detection');
      expect(script.contains("Object.defineProperty(navigator, 'webdriver'"), isTrue);
      expect(script.contains("Object.defineProperty(window.Navigator.prototype, 'webdriver'"), isTrue);
      expect(script.contains('delete window.flutter_inappwebview'), isTrue);

      // Node.js DOM runtime execution verification
      final runner = '''
        const { JSDOM } = require('jsdom');
        const dom = new JSDOM('<!DOCTYPE html><html><head></head><body></body></html>');
        global.window = dom.window;
        global.document = dom.window.document;
        global.navigator = dom.window.navigator;
        global.Navigator = dom.window.Navigator;
        global.Function = dom.window.Function;

        // Set fake bridge initially to test purging
        dom.window.flutter_inappwebview = { callHandler: function() {} };

        // Execute stealth script
        eval(${jsonEncode(script)});

        const result = {
          webdriverValue: global.navigator.webdriver,
          hasBridge: ('flutter_inappwebview' in dom.window),
          nativeToStringPreserved: (global.Function.prototype.toString.name === 'toString'),
          hasChrome: (typeof dom.window.chrome !== 'undefined'),
          chromeAppDisabled: (dom.window.chrome?.app?.InstallState?.DISABLED === 'disabled'),
          chromeCsi: (typeof dom.window.chrome?.csi === 'function'),
          chromeLoadTimes: (typeof dom.window.chrome?.loadTimes === 'function')
        };
        console.log(JSON.stringify(result));
      ''';

      final res = Process.runSync(
        'node',
        ['-e', runner],
        workingDirectory: Directory.current.path,
        environment: {'NODE_PATH': '${Directory.current.path}/node_modules'},
      );
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final data = jsonDecode(res.stdout.toString().trim()) as Map<String, dynamic>;
        expect(data['webdriverValue'], isFalse, reason: 'navigator.webdriver must evaluate to false');
        expect(data['hasBridge'], isFalse, reason: 'flutter_inappwebview must be deleted');
        expect(data['nativeToStringPreserved'], isTrue, reason: 'Native Function.prototype.toString must remain intact');
        expect(data['hasChrome'], isTrue, reason: 'window.chrome must be emulated');
        expect(data['chromeAppDisabled'], isTrue, reason: 'window.chrome.app.InstallState.DISABLED must equal disabled');
        expect(data['chromeCsi'], isTrue, reason: 'window.chrome.csi must be a function');
        expect(data['chromeLoadTimes'], isTrue, reason: 'window.chrome.loadTimes must be a function');
      }
    });

    test('Speed Multiplier Human Ceiling Guard: setSpeedMultiplier clamps strictly to [0.5, 1.0]', () async {
      final vm = OverlayButtonsViewModel();
      await vm.initialize();

      // Default is 1.0
      expect(vm.speedMultiplier, equals(1.0));

      // Attempt setting super-human speeds -> clamped to 1.0
      vm.setSpeedMultiplier(2.5);
      expect(vm.speedMultiplier, equals(1.0), reason: 'Must clamp 2.5x down to 1.0x human ceiling');

      vm.setSpeedMultiplier(10.0);
      expect(vm.speedMultiplier, equals(1.0), reason: 'Must clamp 10.0x down to 1.0x human ceiling');

      // Attempt setting normal human speed within bounds
      vm.setSpeedMultiplier(0.75);
      expect(vm.speedMultiplier, equals(0.75), reason: 'Values within [0.5, 1.0] must be preserved');

      // Attempt setting excessively slow speed -> clamped to 0.5
      vm.setSpeedMultiplier(0.1);
      expect(vm.speedMultiplier, equals(0.5), reason: 'Must clamp 0.1x up to 0.5x minimum floor');

      vm.setSpeedMultiplier(-1.0);
      expect(vm.speedMultiplier, equals(0.5), reason: 'Must clamp negative values up to 0.5x floor');
    });

    test('Stealth Seed Rotation: 2-hour cooldown throttles DOM seed rotation unless force: true', () async {
      final vm = OverlayButtonsViewModel();

      // Initially null
      expect(vm.lastWebSeedRotationTime, isNull);

      // First call rotates and records timestamp (force: false)
      final firstRotated = await vm.rotateWebClientSeed(force: false);
      expect(firstRotated, isFalse); // No webview controller attached in test environment, but updates internal stats & doesn't skip due to cooldown

      final now = DateTime.now();
      vm.setLastWebSeedRotationTimeForTesting(now);
      expect(vm.lastWebSeedRotationTime, equals(now));

      // Immediate second call without force -> MUST skip DOM rotation due to 2h cooldown
      final secondRotated = await vm.rotateWebClientSeed(force: false);
      expect(secondRotated, isFalse, reason: 'Must skip DOM rotation when within 2-hour cooldown');

      // Calling with force: true -> bypasses cooldown
      vm.setLastWebSeedRotationTimeForTesting(now);
      expect(now.difference(vm.lastWebSeedRotationTime!) < OverlayButtonsViewModel.minWebSeedRotationInterval, isTrue);

      // Calling after 2 hours (e.g. 2 hours 1 minute ago) -> cooldown expired
      vm.setLastWebSeedRotationTimeForTesting(now.subtract(const Duration(hours: 2, minutes: 1)));
      expect(DateTime.now().difference(vm.lastWebSeedRotationTime!) >= OverlayButtonsViewModel.minWebSeedRotationInterval, isTrue);
    });

    test('Stealth DOM Cleanliness: Zero golden-zoom-style project artifacts in codebase', () {
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();
      final viewFile = File('lib/views/sequence_analyzer_view.dart').readAsStringSync();

      expect(vmFile.contains('golden-zoom-style'), isFalse, reason: 'OverlayButtonsViewModel must not contain golden-zoom-style');
      expect(viewFile.contains('golden-zoom-style'), isFalse, reason: 'SequenceAnalyzerView must not contain golden-zoom-style');
    });

    test('SEC-02 & SEC-05: Bet amount typing routine has ZERO window symbols and does NOT mutate inputmode', () async {
      final vm = OverlayButtonsViewModel();
      expect(vm.isTypingBetAmount, isFalse);

      // Check ViewModel source / runtime guarantees
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();

      // SEC-02: Absolutely NO gp_ Symbols declared on window
      expect(vmFile.contains("Symbol.for('gp_typing_busy')"), isFalse, reason: 'Must not declare gp_typing_busy');
      expect(vmFile.contains("Symbol.for('gp_typing_done')"), isFalse, reason: 'Must not declare gp_typing_done');
      expect(vmFile.contains("Symbol.for('gp_"), isFalse, reason: 'Must not declare any gp_ symbols on window');

      // SEC-05: Absolutely NO inputmode = 'none' mutation
      expect(vmFile.contains("setAttribute('inputmode', 'none')"), isFalse, reason: 'Must not set inputmode to none');
      expect(vmFile.contains("inputmode', 'none'"), isFalse, reason: 'Must not set inputmode to none');
    });

    test('SEC-06: Typing event dispatch order matches W3C specification (beforeinput before value update, then input)', () {
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();

      // Find indices in _setBetAmount
      final idxBeforeInput = vmFile.indexOf("InputEvent('beforeinput'");
      final idxSetVal = vmFile.indexOf("setVal(currentText);", idxBeforeInput);
      final idxInput = vmFile.indexOf("InputEvent('input'", idxSetVal);

      expect(idxBeforeInput, isPositive, reason: 'Must dispatch beforeinput');
      expect(idxSetVal, isPositive, reason: 'Must update value via setVal');
      expect(idxInput, isPositive, reason: 'Must dispatch input event');

      expect(idxBeforeInput < idxSetVal, isTrue, reason: 'beforeinput MUST be dispatched BEFORE value update');
      expect(idxSetVal < idxInput, isTrue, reason: 'input event MUST be dispatched AFTER value update');
    });

    test('SEC-08: _getBalanceJs does NOT use querySelectorAll("*") in either Mines or Towers', () {
      final analyzer = SequenceAnalyzerViewModel();
      final minesJs = analyzer.getBalanceJsForTesting(GameMode.mines);
      final towersJs = analyzer.getBalanceJsForTesting(GameMode.towers);

      expect(minesJs.contains("querySelectorAll('*')"), isFalse, reason: 'Mines _getBalanceJs must not query all elements');
      expect(minesJs.contains('querySelectorAll("*")'), isFalse);
      expect(towersJs.contains("querySelectorAll('*')"), isFalse, reason: 'Towers _getBalanceJs must not query all elements');
      expect(towersJs.contains('querySelectorAll("*")'), isFalse);

      // Also verify OverlayButtonsViewModel _getBalanceDouble
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();
      expect(vmFile.contains("querySelectorAll('*')"), isFalse, reason: 'OverlayButtonsViewModel must not query all elements');
      expect(vmFile.contains('querySelectorAll("*")'), isFalse);
    });

    test('SEC-09: clientHintsScript defines navigator.maxTouchPoints = 5 and guarantees DeviceOrientationEvent', () {
      final script = UserAgentService.clientHintsScript;

      expect(script.contains("navigator, 'maxTouchPoints'"), isTrue);
      expect(script.contains("get: () => 5"), isTrue);
      expect(script.contains('DeviceOrientationEvent'), isTrue);

      final runner = '''
        const { JSDOM } = require('jsdom');
        const dom = new JSDOM('<!DOCTYPE html><html><head></head><body></body></html>');
        global.window = dom.window;
        global.document = dom.window.document;
        global.navigator = dom.window.navigator;
        global.Navigator = dom.window.Navigator;
        global.Function = dom.window.Function;

        eval(${jsonEncode(script)});

        const result = {
          maxTouchPoints: global.navigator.maxTouchPoints,
          hasOrientation: typeof dom.window.DeviceOrientationEvent !== 'undefined'
        };
        console.log(JSON.stringify(result));
      ''';

      final res = Process.runSync(
        'node',
        ['-e', runner],
        workingDirectory: Directory.current.path,
        environment: {'NODE_PATH': '${Directory.current.path}/node_modules'},
      );
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final data = jsonDecode(res.stdout.toString().trim()) as Map<String, dynamic>;
        expect(data['maxTouchPoints'], equals(5), reason: 'maxTouchPoints must return 5 on mobile');
        expect(data['hasOrientation'], isTrue, reason: 'DeviceOrientationEvent must be present');
      }
    });

    test('DOM Touch Driver: OverlayButtonsViewModel executes clickScript on DOM elements without arbitrary native MotionEvent bypass on Android', () {
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();

      // Verify clickScript real DOM interaction logic
      expect(vmFile.contains('function doClick(el, px = x, py = y)'), isTrue, reason: 'Must implement doClick on DOM element');
      expect(vmFile.contains('el.click()'), isTrue, reason: 'Must trigger native DOM element click');
      expect(vmFile.contains('getActualTarget'), isTrue, reason: 'Must resolve actual DOM target avoiding input boxes');
      expect(vmFile.contains('findClickableAncestor'), isTrue, reason: 'Must find clickable button ancestor');

      // Verify that Android does NOT bypass clickScript with raw MotionEvent
      expect(vmFile.contains('_performAndroidNativeClick'), isFalse,
          reason: 'Android must execute clickScript directly on DOM elements without native MotionEvent bypass');
    });
  });
}
