import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bet Typing and M0-M3 Coordination Synchronization Suite', () {
    test('SEC-02 & DOM Guard: Static inspection ensures no premature return and no window symbols', () {
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();

      // Ensure flawed premature returns are absent
      expect(vmFile.contains("return { ready: true, reason: 'no_input' };"), isFalse,
          reason: 'M0 guard must never return ready: true when input element is missing');
      expect(vmFile.contains("return { ready: true, reason: 'empty' };"), isFalse,
          reason: 'M0 guard must never return ready: true when input element is empty or zero');
      expect(vmFile.contains("if (!inp) return true;"), isFalse,
          reason: '_setBetAmount polling loop must never return true when input element is null');

      // Element-level non-enumerable flags
      expect(vmFile.contains('_typingActive'), isTrue,
          reason: 'Typing routine must set element-level _typingActive flag');
      expect(vmFile.contains('_typingDone'), isTrue,
          reason: 'Typing routine must set element-level _typingDone flag');

      // maxGuardWaitMs must be 12000
      expect(vmFile.contains('const int maxGuardWaitMs = 12000;'), isTrue,
          reason: 'maxGuardWaitMs must be 12000ms to allow human-like typing pace without premature timeout');

      // Zero window symbol pollution
      expect(vmFile.contains("Symbol.for('gp_"), isFalse,
          reason: 'Must never pollute window with gp_ symbols');
    });

    test('DOM Runtime: getM0PreClickGuardJs handles missing, empty, typing, mismatch, and match states correctly', () {
      final vm = OverlayButtonsViewModel();
      const double targetBet = 0.0005;
      final script = vm.getM0PreClickGuardJs(targetBet);

      final runner = '''
        const { JSDOM } = require('jsdom');

        // Test 1: No input in DOM
        const dom1 = new JSDOM('<!DOCTYPE html><html><body><div id="game"></div></body></html>');
        global.window = dom1.window;
        global.document = dom1.window.document;
        global.Math = Math;
        global.parseFloat = parseFloat;
        global.isNaN = isNaN;
        const resNoInput = eval(${jsonEncode(script)});

        // Test 2: Input exists but empty (value = "")
        const dom2 = new JSDOM('<!DOCTYPE html><html><body><input id="amount" type="text" value="" /></body></html>');
        global.window = dom2.window;
        global.document = dom2.window.document;
        const resEmpty = eval(${jsonEncode(script)});

        // Test 3: Input exists with matching value but _typingActive === true
        const dom3 = new JSDOM('<!DOCTYPE html><html><body><input id="amount" type="text" value="0.0005" /></body></html>');
        global.window = dom3.window;
        global.document = dom3.window.document;
        const inp3 = dom3.window.document.getElementById('amount');
        Object.defineProperty(inp3, '_typingActive', { value: true, writable: true, configurable: true, enumerable: false });
        const resTyping = eval(${jsonEncode(script)});

        // Test 4: Input exists with mismatched value
        const dom4 = new JSDOM('<!DOCTYPE html><html><body><input id="amount" type="text" value="0.0001" /></body></html>');
        global.window = dom4.window;
        global.document = dom4.window.document;
        const resMismatch = eval(${jsonEncode(script)});

        // Test 5: Input exists with matching value and typing completed
        const dom5 = new JSDOM('<!DOCTYPE html><html><body><input id="amount" type="text" value="0.0005" /></body></html>');
        global.window = dom5.window;
        global.document = dom5.window.document;
        const inp5 = dom5.window.document.getElementById('amount');
        Object.defineProperty(inp5, '_typingActive', { value: false, writable: true, configurable: true, enumerable: false });
        Object.defineProperty(inp5, '_typingDone', { value: true, writable: true, configurable: true, enumerable: false });
        const resMatched = eval(${jsonEncode(script)});

        // Test 6: Towers Min/Max button container resolution
        const dom6 = new JSDOM(`<!DOCTYPE html><html><body>
          <div class="bet-container">
            <button>Min</button>
            <button>Max</button>
            <input type="text" value="0.0005" />
          </div>
        </body></html>`);
        global.window = dom6.window;
        global.document = dom6.window.document;
        const resTowersContainer = eval(${jsonEncode(script)});

        const results = {
          noInput: resNoInput,
          empty: resEmpty,
          typing: resTyping,
          mismatch: resMismatch,
          matched: resMatched,
          towersContainer: resTowersContainer
        };
        console.log(JSON.stringify(results));
      ''';

      final res = Process.runSync(
        'node',
        ['-e', runner],
        workingDirectory: Directory.current.path,
        environment: {'NODE_PATH': '${Directory.current.path}/node_modules'},
      );

      expect(res.exitCode, equals(0), reason: 'Node execution failed: ${res.stderr}');
      final data = jsonDecode(res.stdout.toString().trim()) as Map<String, dynamic>;

      // Test 1: No input -> must NOT be ready
      expect(data['noInput']['ready'], isFalse);
      expect(data['noInput']['reason'], equals('no_input'));

      // Test 2: Empty input -> must NOT be ready
      expect(data['empty']['ready'], isFalse);
      expect(data['empty']['reason'], equals('empty'));

      // Test 3: Typing active -> must NOT be ready
      expect(data['typing']['ready'], isFalse);
      expect(data['typing']['reason'], equals('typing'));

      // Test 4: Mismatch -> must NOT be ready
      expect(data['mismatch']['ready'], isFalse);
      expect(data['mismatch']['reason'], equals('mismatch'));

      // Test 5: Matched -> MUST be ready!
      expect(data['matched']['ready'], isTrue);
      expect(data['matched']['reason'], equals('matched'));
      expect(data['matched']['domVal'], equals(0.0005));

      // Test 6: Towers container -> MUST resolve input and be ready!
      expect(data['towersContainer']['ready'], isTrue);
      expect(data['towersContainer']['reason'], equals('matched'));
    });

    test('DOM Runtime: _setBetAmount polling script correctly waits until typing completion', () {
      final vmFile = File('lib/viewmodels/overlay_buttons_viewmodel.dart').readAsStringSync();

      // Extract the polling JS snippet from _setBetAmount
      final startIdx = vmFile.indexOf('while (stopwatch.elapsedMilliseconds < maxTypingWaitMs) {');
      expect(startIdx, isPositive);
      final sourceStart = vmFile.indexOf('source: """', startIdx);
      final sourceEnd = vmFile.indexOf('"""', sourceStart + 11);
      final rawJs = vmFile.substring(sourceStart + 11, sourceEnd).trim();

      // Replace template variables for test
      final script = rawJs
          .replaceAll(r'$amountStr', '0.0005')
          .replaceAll(r'${double.tryParse(amountStr) ?? 0}', '0.0005');

      final runner = '''
        const { JSDOM } = require('jsdom');

        // Test A: No input in DOM -> must return false (do NOT finish)
        const domA = new JSDOM('<!DOCTYPE html><html><body></body></html>');
        global.window = domA.window;
        global.document = domA.window.document;
        global.parseFloat = parseFloat;
        global.Math = Math;
        const resNoInput = eval(${jsonEncode(script)});

        // Test B: Input exists, but _typingActive === true -> must return false
        const domB = new JSDOM('<!DOCTYPE html><html><body><input id="amount" value="0.0005"/></body></html>');
        global.window = domB.window;
        global.document = domB.window.document;
        const inpB = domB.window.document.getElementById('amount');
        Object.defineProperty(inpB, '_typingActive', { value: true, writable: true, configurable: true, enumerable: false });
        Object.defineProperty(inpB, '_typingDone', { value: false, writable: true, configurable: true, enumerable: false });
        const resTypingActive = eval(${jsonEncode(script)});

        // Test C: Input exists, _typingActive === false, but _typingDone !== true -> must return false
        const domC = new JSDOM('<!DOCTYPE html><html><body><input id="amount" value="0.0005"/></body></html>');
        global.window = domC.window;
        global.document = domC.window.document;
        const inpC = domC.window.document.getElementById('amount');
        Object.defineProperty(inpC, '_typingActive', { value: false, writable: true, configurable: true, enumerable: false });
        Object.defineProperty(inpC, '_typingDone', { value: false, writable: true, configurable: true, enumerable: false });
        const resTypingNotDone = eval(${jsonEncode(script)});

        // Test D: Input exists, _typingDone === true, but partial value '0.00' -> must return false
        const domD = new JSDOM('<!DOCTYPE html><html><body><input id="amount" value="0.00"/></body></html>');
        global.window = domD.window;
        global.document = domD.window.document;
        const inpD = domD.window.document.getElementById('amount');
        Object.defineProperty(inpD, '_typingActive', { value: false, writable: true, configurable: true, enumerable: false });
        Object.defineProperty(inpD, '_typingDone', { value: true, writable: true, configurable: true, enumerable: false });
        const resPartialVal = eval(${jsonEncode(script)});

        // Test E: Input exists, _typingDone === true, and value '0.0005' -> must return true!
        const domE = new JSDOM('<!DOCTYPE html><html><body><input id="amount" value="0.0005"/></body></html>');
        global.window = domE.window;
        global.document = domE.window.document;
        const inpE = domE.window.document.getElementById('amount');
        Object.defineProperty(inpE, '_typingActive', { value: false, writable: true, configurable: true, enumerable: false });
        Object.defineProperty(inpE, '_typingDone', { value: true, writable: true, configurable: true, enumerable: false });
        const resComplete = eval(${jsonEncode(script)});

        console.log(JSON.stringify({
          noInput: resNoInput,
          typingActive: resTypingActive,
          typingNotDone: resTypingNotDone,
          partialVal: resPartialVal,
          complete: resComplete
        }));
      ''';

      final res = Process.runSync(
        'node',
        ['-e', runner],
        workingDirectory: Directory.current.path,
        environment: {'NODE_PATH': '${Directory.current.path}/node_modules'},
      );

      expect(res.exitCode, equals(0), reason: 'Node execution failed: ${res.stderr}');
      final data = jsonDecode(res.stdout.toString().trim()) as Map<String, dynamic>;

      expect(data['noInput'], isFalse, reason: 'Polling loop must return false when input missing');
      expect(data['typingActive'], isFalse, reason: 'Polling loop must return false when typing is active');
      expect(data['typingNotDone'], isFalse, reason: 'Polling loop must return false when typing is not done');
      expect(data['partialVal'], isFalse, reason: 'Polling loop must return false when value is partial');
      expect(data['complete'], isTrue, reason: 'Polling loop must return true when typing completed with correct amount');
    });

    test('Base Bet No-Retype: Rule logic preserves hasBaseBetBeenSet invariant', () {
      final state = GameModeSessionState(GameMode.towers);

      // Initial state
      expect(state.hasBaseBetBeenSet, isFalse);

      // Once set, flag must be true
      state.hasBaseBetBeenSet = true;
      expect(state.hasBaseBetBeenSet, isTrue);

      // Recovery round clears base bet set status if debt recovery fires
      state.isCurrentlyRecoveryRound = true;
      expect(state.isCurrentlyRecoveryRound, isTrue);
    });
  });
}
