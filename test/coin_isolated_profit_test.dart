import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Coin-Isolated Profit Tracking Tests', () {
    test('Towers profit is strictly isolated per coin (DOGE vs POL)', () {
      final vm = SequenceAnalyzerViewModel(gameMode: GameMode.towers);

      // 1. Initial balance on DOGE = 0.50
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.50000000',
      });

      expect(vm.getCoinTypeForMode(GameMode.towers), 'DOGE');
      expect(vm.getBalanceForMode(GameMode.towers), '0.50000000');
      expect(vm.getInitialBalanceForMode(GameMode.towers), '0.50000000');
      expect(vm.getProfitForMode(GameMode.towers), 0.0);

      // 2. DOGE balance increases to 0.55 (+10%)
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.55000000',
      });

      expect(vm.getProfitForMode(GameMode.towers), closeTo(10.0, 0.001));
      expect(vm.profitPercentage, closeTo(10.0, 0.001));

      // 3. User switches to POL (0.27000000)
      // CRITICAL: Must NOT compare 0.27 POL against 0.50 DOGE (which would be -46%)!
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'POL',
        'balance': '0.27000000',
      });

      expect(vm.getCoinTypeForMode(GameMode.towers), 'POL');
      expect(vm.getBalanceForMode(GameMode.towers), '0.27000000');
      expect(vm.getInitialBalanceForMode(GameMode.towers), '0.27000000');
      // Profit for POL starts fresh at 0.0%, NEVER -46%!
      expect(vm.getProfitForMode(GameMode.towers), 0.0);
      expect(vm.profitPercentage, 0.0);

      // 4. POL balance increases to 0.297 (+10%)
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'POL',
        'balance': '0.29700000',
      });

      expect(vm.getProfitForMode(GameMode.towers), closeTo(10.0, 0.001));
      expect(vm.profitPercentage, closeTo(10.0, 0.001));

      // 5. User switches BACK to DOGE (balance 0.55000000)
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.55000000',
      });

      expect(vm.getCoinTypeForMode(GameMode.towers), 'DOGE');
      // DOGE initial balance (0.50) is preserved!
      expect(vm.getInitialBalanceForMode(GameMode.towers), '0.50000000');
      // DOGE profit (+10%) is preserved!
      expect(vm.getProfitForMode(GameMode.towers), closeTo(10.0, 0.001));
      expect(vm.profitPercentage, closeTo(10.0, 0.001));

      // 6. Query specific coins explicitly
      expect(vm.getProfitForMode(GameMode.towers, coinType: 'DOGE'), closeTo(10.0, 0.001));
      expect(vm.getProfitForMode(GameMode.towers, coinType: 'POL'), closeTo(10.0, 0.001));
      expect(vm.getInitialBalanceForMode(GameMode.towers, coinType: 'DOGE'), '0.50000000');
      expect(vm.getInitialBalanceForMode(GameMode.towers, coinType: 'POL'), '0.27000000');
    });

    test('Towers POL and Mines POL are isolated by GameMode', () {
      final vmTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      final vmMines = SequenceAnalyzerViewModel(gameMode: GameMode.mines);

      vmTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'POL',
        'balance': '1.00000000',
      });
      vmTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'POL',
        'balance': '1.20000000',
      });
      expect(vmTowers.getProfitForMode(GameMode.towers), closeTo(20.0, 0.001));

      vmMines.applyParsedBalanceResultForTesting(GameMode.mines, {
        'coin': 'POL',
        'balance': '5.00000000',
      });
      expect(vmMines.getProfitForMode(GameMode.mines), 0.0);
      expect(vmMines.getInitialBalanceForMode(GameMode.mines), '5.00000000');

      // Towers POL profit unaffected
      expect(vmTowers.getProfitForMode(GameMode.towers), closeTo(20.0, 0.001));
    });

    test('resetProfitTracking with specific coin resets only that coin', () {
      final vm = SequenceAnalyzerViewModel(gameMode: GameMode.towers);

      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.50000000',
      });
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.55000000',
      });

      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'POL',
        'balance': '0.20000000',
      });
      vm.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'POL',
        'balance': '0.22000000',
      });

      expect(vm.getProfitForMode(GameMode.towers, coinType: 'DOGE'), closeTo(10.0, 0.001));
      expect(vm.getProfitForMode(GameMode.towers, coinType: 'POL'), closeTo(10.0, 0.001));

      // Reset POL only
      vm.resetProfitTracking(mode: GameMode.towers, coinType: 'POL');

      expect(vm.getProfitForMode(GameMode.towers, coinType: 'POL'), 0.0);
      expect(vm.getInitialBalanceForMode(GameMode.towers, coinType: 'POL'), isNull);

      // DOGE remains untouched
      expect(vm.getProfitForMode(GameMode.towers, coinType: 'DOGE'), closeTo(10.0, 0.001));
      expect(vm.getInitialBalanceForMode(GameMode.towers, coinType: 'DOGE'), '0.50000000');
    });

    test('GameModeSessionState tracks activeCoinType', () {
      final state = GameModeSessionState(GameMode.towers);
      expect(state.activeCoinType, isNull);

      state.activeCoinType = 'DOGE';
      state.sessionStartBalance = 0.50;
      state.sessionMaxBalance = 0.55;

      expect(state.activeCoinType, 'DOGE');
      expect(state.sessionStartBalance, 0.50);
      expect(state.sessionMaxBalance, 0.55);
    });

    test('Towers multi-coin switching across DOGE, POL, USDT, TRX, BTC maintains independent baselines and profits for each coin', () {
      final vm = SequenceAnalyzerViewModel(gameMode: GameMode.towers);

      // Coins inside Towers:
      final coinsData = [
        {'coin': 'DOGE', 'init': '0.50000000', 'new': '0.60000000', 'profit': 20.0},
        {'coin': 'POL',  'init': '0.27000000', 'new': '0.29700000', 'profit': 10.0},
        {'coin': 'USDT', 'init': '1.50000000', 'new': '1.65000000', 'profit': 10.0},
        {'coin': 'TRX',  'init': '10.0000000', 'new': '12.5000000', 'profit': 25.0},
        {'coin': 'BTC',  'init': '0.00010000', 'new': '0.00011000', 'profit': 10.0},
      ];

      // Step 1: Initialize each coin in Tower sequentially
      for (final c in coinsData) {
        vm.applyParsedBalanceResultForTesting(GameMode.towers, {
          'coin': c['coin'],
          'balance': c['init'],
        });
        expect(vm.getCoinTypeForMode(GameMode.towers), c['coin']);
        expect(vm.getBalanceForMode(GameMode.towers), c['init']);
        expect(vm.getInitialBalanceForMode(GameMode.towers), c['init']);
        // Fresh initial profit is 0.0%
        expect(vm.getProfitForMode(GameMode.towers), 0.0);
      }

      // Step 2: Simulate gains on each coin in Tower
      for (final c in coinsData) {
        vm.applyParsedBalanceResultForTesting(GameMode.towers, {
          'coin': c['coin'],
          'balance': c['new'],
        });
        expect(vm.getCoinTypeForMode(GameMode.towers), c['coin']);
        expect(vm.getProfitForMode(GameMode.towers), closeTo(c['profit'] as double, 0.001));
      }

      // Step 3: Switch back and verify all coins preserved their independent initial balance & profit!
      for (final c in coinsData) {
        final coinName = c['coin'] as String;
        expect(vm.getInitialBalanceForMode(GameMode.towers, coinType: coinName), c['init']);
        expect(vm.getProfitForMode(GameMode.towers, coinType: coinName), closeTo(c['profit'] as double, 0.001));
      }
    });
  });
}
