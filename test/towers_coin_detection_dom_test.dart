import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic>? evaluateBalanceJsOnHtml(String jsCode, String html) {
  final cleanJs = jsCode.trim().endsWith(';') 
      ? jsCode.trim().substring(0, jsCode.trim().length - 1) 
      : jsCode.trim();
  final runner = '''
    const { JSDOM } = require('jsdom');
    const dom = new JSDOM(${jsonEncode(html)});
    global.window = dom.window;
    global.document = dom.window.document;
    const res = $cleanJs;
    console.log(res || 'null');
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

  group('Towers Coin & Balance DOM Detection Tests', () {
    late SequenceAnalyzerViewModel vm;
    late String towersJs;

    setUp(() {
      vm = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      towersJs = vm.getBalanceJsForTesting(GameMode.towers);
    });

    test('1. FEY detection from direct balance element with FEY text', () {
      const html = '''
        <div class="user-balance-box">
          <span class="balance">0.00171871 FEY</span>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('FEY'), reason: 'Coin must be recognized as FEY, not DOGE');
      expect(res['balance'], equals('0.00171871'));
    });

    test('2. PEPE detection from dropdown selector and 2-decimal balance', () {
      const html = '''
        <div class="currency-selector">
          <select name="currency">
            <option value="doge">Dogecoin (DOGE)</option>
            <option value="pepe" selected>Pepe (PEPE)</option>
            <option value="usdt">Tether (USDT)</option>
          </select>
        </div>
        <div class="balance-container">
          <span class="balance">1500.50</span>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('PEPE'), reason: 'Coin must be recognized from select dropdown as PEPE');
      expect(res['balance'], equals('1500.50'));
    });

    test('3. DGB detection from balance element with DigiByte text', () {
      const html = '''
        <div class="header">
          <div id="balance">0.00074300 DGB</div>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('DGB'), reason: 'Coin must be recognized as DGB, not DOGE');
      expect(res['balance'], equals('0.00074300'));
    });

    test('4. DOGE detection from direct balance element', () {
      const html = '''
        <div class="header">
          <span class="balance">0.00007820 DOGE</span>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('DOGE'));
      expect(res['balance'], equals('0.00007820'));
    });

    test('5. POL detection from currency dropdown and balance', () {
      const html = '''
        <select id="currency">
          <option value="POL" selected>Polygon (POL)</option>
        </select>
        <div class="balance">0.00000903</div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('POL'));
      expect(res['balance'], equals('0.00000903'));
    });

    test('6. USDT detection from container text', () {
      const html = '''
        <div class="balance">0.00000500 USDT</div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('USDT'));
      expect(res['balance'], equals('0.00000500'));
    });

    test('7. Text-based pattern scanner detects Feyorra (FEY)', () {
      const html = '''
        <div class="account-summary">
          <span>Account Info</span>
          <p>Feyorra (FEY) 0.00171871</p>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('FEY'));
      expect(res['balance'], equals('0.00171871'));
    });

    test('8. Large PEPE integer balance detection', () {
      const html = '''
        <div class="balance-wrap">
          <span class="balance">500000000 PEPE</span>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('PEPE'));
      expect(res['balance'], equals('500000000'));
    });

    test('9. Towers fallback to DOGE when no coin information is present anywhere', () {
      const html = '''
        <div class="user-box">
          <span class="balance">0.50000000</span>
        </div>
      ''';
      final res = evaluateBalanceJsOnHtml(towersJs, html);
      expect(res, isNotNull);
      expect(res!['coin'], equals('DOGE'));
      expect(res['balance'], equals('0.50000000'));
    });

    test('10. Mines mode detects POL by default or specified coin', () {
      final minesJs = vm.getBalanceJsForTesting(GameMode.mines);
      
      // POL default on Mines
      const htmlPol = '''
        <div id="balance">1.25000000</div>
      ''';
      final resPol = evaluateBalanceJsOnHtml(minesJs, htmlPol);
      expect(resPol, isNotNull);
      expect(resPol!['coin'], equals('POL'));
      expect(resPol['balance'], equals('1.25000000'));

      // USDT on Mines via dropdown
      const htmlUsdt = '''
        <select name="currency">
          <option value="usdt" selected>USDT</option>
        </select>
        <div id="balance">5.50000000</div>
      ''';
      final resUsdt = evaluateBalanceJsOnHtml(minesJs, htmlUsdt);
      expect(resUsdt, isNotNull);
      expect(resUsdt!['coin'], equals('USDT'));
      expect(resUsdt['balance'], equals('5.50000000'));
    });

    test('11. ViewModel integration: Parsed result updates detectedCoinType and isolated state', () {
      // Apply FEY balance
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'FEY',
        'balance': '0.00171871',
      });
      expect(vm.getCoinTypeForMode(GameMode.towers), equals('FEY'));
      expect(vm.getBalanceForMode(GameMode.towers), equals('0.00171871'));

      // Apply PEPE balance
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'PEPE',
        'balance': '1500.50',
      });
      expect(vm.getCoinTypeForMode(GameMode.towers), equals('PEPE'));
      expect(vm.getBalanceForMode(GameMode.towers), equals('1500.50'));

      // Apply DGB balance
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DGB',
        'balance': '0.00074300',
      });
      expect(vm.getCoinTypeForMode(GameMode.towers), equals('DGB'));
      expect(vm.getBalanceForMode(GameMode.towers), equals('0.00074300'));
    });
  });
}
