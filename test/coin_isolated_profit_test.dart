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

    test('Stop profit triggers 2-3 hour break and resets profit to 0.000% on both Towers and Mines', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      final analyzerMines = SequenceAnalyzerViewModel(gameMode: GameMode.mines);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerMines, mode: GameMode.mines);

      // --- TOWERS TEST ---
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(10.0, mode: GameMode.towers);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);

      // Towers balance rises to +12%
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.12000000',
      });
      expect(analyzerTowers.getProfitForMode(GameMode.towers), closeTo(12.0, 0.001));

      // Inline TP triggered
      final towersTriggered = await overlayVM.testCheckStopProfitInline(1, mode: GameMode.towers);
      expect(towersTriggered, isTrue);

      // Break must be 2 to 3 hours (120 to 180 minutes)
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isTrue);
      final towersBreak = overlayVM.getBreakRemainingDuration(GameMode.towers);
      expect(towersBreak.inMinutes, greaterThanOrEqualTo(119));
      expect(towersBreak.inMinutes, lessThanOrEqualTo(180));

      // Countdown formatted as HH:mm:ss
      final formattedTowers = overlayVM.getBreakRemainingFormatted(GameMode.towers);
      expect(formattedTowers, matches(r'^\d{2}:\d{2}:\d{2}$'));

      // Profit reset to 0.000%
      expect(analyzerTowers.getProfitForMode(GameMode.towers), 0.0);

      // --- MINES TEST (Mode Isolated) ---
      analyzerMines.applyParsedBalanceResultForTesting(GameMode.mines, {
        'coin': 'POL',
        'balance': '2.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.mines);
      overlayVM.setStopProfitPercent(15.0, mode: GameMode.mines);
      expect(overlayVM.isBreakActiveFor(GameMode.mines), isFalse);

      // Mines balance rises to +20%
      analyzerMines.applyParsedBalanceResultForTesting(GameMode.mines, {
        'coin': 'POL',
        'balance': '2.40000000',
      });
      expect(analyzerMines.getProfitForMode(GameMode.mines), closeTo(20.0, 0.001));

      final minesTriggered = await overlayVM.testCheckStopProfitInline(1, mode: GameMode.mines);
      expect(minesTriggered, isTrue);

      expect(overlayVM.isBreakActiveFor(GameMode.mines), isTrue);
      final minesBreak = overlayVM.getBreakRemainingDuration(GameMode.mines);
      expect(minesBreak.inMinutes, greaterThanOrEqualTo(119));
      expect(minesBreak.inMinutes, lessThanOrEqualTo(180));
      expect(analyzerMines.getProfitForMode(GameMode.mines), 0.0);

      // Cancel Towers break
      overlayVM.cancelBreak(mode: GameMode.towers);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
      expect(overlayVM.getBreakRemainingFormatted(GameMode.towers), '00:00:00');
      // Mines break is still active
      expect(overlayVM.isBreakActiveFor(GameMode.mines), isTrue);

      overlayVM.dispose();
    });
  });
}
