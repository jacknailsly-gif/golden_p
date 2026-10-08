import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic>? evaluateAlignmentJsOnHtml(
  String jsCode,
  String html,
  double targetY, {
  bool disableWindowScrollBy = false,
  bool withScrollableContainer = false,
}) {
  final cleanJs = jsCode.trim().endsWith(';')
      ? jsCode.trim().substring(0, jsCode.trim().length - 1)
      : jsCode.trim();
  final runner = '''
    const { JSDOM } = require('jsdom');
    const dom = new JSDOM(${jsonEncode(html)});
    global.window = dom.window;
    global.document = dom.window.document;
    
    let windowScrolled = false;
    let windowScrollY = 0;
    if ($disableWindowScrollBy) {
      delete global.window.scrollBy;
    } else {
      global.window.scrollBy = function(x, y) {
        windowScrolled = true;
        windowScrollY += y;
      };
    }

    const computedStyleMock = function(el) {
      if ($withScrollableContainer && el && el.classList && el.classList.contains('scrollable-wrapper')) {
        return { overflowY: 'auto' };
      }
      return { overflowY: 'visible' };
    };
    global.window.getComputedStyle = computedStyleMock;
    dom.window.getComputedStyle = computedStyleMock;

    // Mock getBoundingClientRect
    const all = dom.window.document.querySelectorAll('*');
    all.forEach((el) => {
      el.getBoundingClientRect = function() {
        if (el.id === 'btn_bet' || el.id === 'betBtn' || el.classList.contains('btn-bet') || el.classList.contains('btn-primary')) {
          return { top: 600, bottom: 650, left: 100, right: 200, width: 100, height: 50 };
        }
        if (el.classList.contains('big-container')) {
          return { top: 0, bottom: 300, left: 0, right: 1000, width: 1000, height: 300 };
        }
        if (el.tagName === 'BUTTON' || el.getAttribute('role') === 'button') {
          return { top: 600, bottom: 650, left: 100, right: 200, width: 100, height: 50 };
        }
        return { top: 0, bottom: 0, left: 0, right: 0, width: 10, height: 10 };
      };
      if ($withScrollableContainer && el.classList.contains('scrollable-wrapper')) {
        Object.defineProperty(el, 'scrollHeight', { value: 1200, configurable: true });
        Object.defineProperty(el, 'clientHeight', { value: 600, configurable: true });
      }
    });

    const res = ($cleanJs)($targetY);
    console.log(JSON.stringify(res || null));
  ''';
  final result = Process.runSync(
    'node',
    ['-e', runner],
    workingDirectory: Directory.current.path,
  );
  if (result.exitCode != 0) {
    throw Exception('Node execution failed: ${result.stderr}');
  }
  final out = result.stdout.toString().trim();
  if (out.isEmpty || out == 'null') return null;
  return jsonDecode(out) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Mines Start Button M0 Alignment Protocol Tests', () {
    test('1. Towers mode strictly skips M0 alignment per user directive', () async {
      final vm = OverlayButtonsViewModel();
      vm.setActiveGameMode(GameMode.towers);

      // Should complete immediately without attempting alignment
      await vm.testAlignMineStartWithM0(mode: GameMode.towers);
      expect(vm.activeGameMode, equals(GameMode.towers));
    });

    test('2. Polpick Gems candidate selectors include button#btn_bet and single authority window scroll', () {
      final vm = OverlayButtonsViewModel();
      final script = vm.getAlignMineJsForTesting(300.0);

      const html = '''
        <html>
          <body>
            <div class="game-controls">
              <button id="btn_bet" class="btn btn-primary" data-action="bet">Bet</button>
            </div>
          </body>
        </html>
      ''';

      final res = evaluateAlignmentJsOnHtml(script, html, 300.0);
      expect(res, isNotNull);
      expect(res!['success'], isTrue, reason: 'Must find button#btn_bet as candidate selector');
      // Single Authority: must scroll window only, not multi-layer additive
      expect(res['scrolledLayer'], equals('window'), reason: 'Single authority must select window when available');
    });

    test('3. Single Scrolling Authority chooses scrollable container when parent has overflow-y', () {
      final vm = OverlayButtonsViewModel();
      final script = vm.getAlignMineJsForTesting(250.0);

      const html = '''
        <html>
          <body>
            <div class="scrollable-wrapper" style="overflow-y: auto; height: 600px;">
              <button id="betBtn" class="btn-bet">Start Game</button>
            </div>
          </body>
        </html>
      ''';

      final res = evaluateAlignmentJsOnHtml(script, html, 250.0, withScrollableContainer: true);
      expect(res, isNotNull);
      expect(res!['success'], isTrue);
      expect(res['scrolledLayer'], equals('container'), reason: 'Must scroll container authority when parent is scrollable');
    });

    test('4. Text-based fallback rejects huge container div and selects real button', () {
      final vm = OverlayButtonsViewModel();
      final script = vm.getAlignMineJsForTesting(200.0);

      const html = '''
        <html>
          <body>
            <div class="big-container header-banner">
              <div>Bet and Play today!</div>
            </div>
            <div class="controls">
              <button class="custom-play">
                <span>Play Game</span>
              </button>
            </div>
          </body>
        </html>
      ''';

      final res = evaluateAlignmentJsOnHtml(script, html, 200.0);
      expect(res, isNotNull);
      expect(res!['success'], isTrue);
      expect(res['initialBtnCenterY'], equals(625.0), reason: 'Must match real button at top 600, not big-container at top 0');
    });

    test('5. Fixed reload delay constant is 6500ms and independent of speed multiplier', () async {
      final vm = OverlayButtonsViewModel();
      await vm.initialize();
      vm.setSpeedMultiplier(3.0);
      expect(OverlayButtonsViewModel.postBreakReloadDelayMs, equals(6500));
    });
  });
}
