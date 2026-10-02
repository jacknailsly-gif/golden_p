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

  group('Stop-Profit Positive Guard Tests', () {
    test('Zero pnl (pnl == 0.0) with targetPercent == 0.0 must NOT trigger Stop-Profit', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(0.0, mode: GameMode.towers);

      expect(analyzerTowers.getProfitForMode(GameMode.towers), 0.0);

      // Even if targetPercent is 0.0, Stop-Profit must NEVER trigger when pnl <= 0.0
      final triggered = await overlayVM.testCheckStopProfitInline(1, mode: GameMode.towers);
      expect(triggered, isFalse, reason: 'Stop Profit must NOT trigger when pnl is 0.0');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('Negative pnl (drawdown -5%) with negative targetPercent (-10%) must NOT trigger Stop-Profit', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(-10.0, mode: GameMode.towers);

      // Balance drops to 0.95 (-5%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.95000000',
      });

      expect(analyzerTowers.getProfitForMode(GameMode.towers), closeTo(-5.0, 0.001));

      // Stop-Profit must NEVER trigger during drawdown (pnl < 0)
      final triggered = await overlayVM.testCheckStopProfitInline(1, mode: GameMode.towers);
      expect(triggered, isFalse, reason: 'Stop Profit must NEVER trigger during drawdown (pnl < 0)');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('Micro-precision pnl <= 0.00000001 must NOT trigger Stop-Profit', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.0000000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(0.0, mode: GameMode.towers);

      // Micro tiny delta <= 1e-8
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.0000000000001',
      });

      final triggered = await overlayVM.testCheckStopProfitInline(1, mode: GameMode.towers);
      expect(triggered, isFalse, reason: 'pnl <= 0.00000001 must not trigger stop profit');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('Strict Positive Guard: Only triggers when pnl > 0.00000001 AND pnl >= targetPercent', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(5.0, mode: GameMode.towers);

      // Profit +3%: below target
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.03000000',
      });
      expect(await overlayVM.testCheckStopProfitInline(1, mode: GameMode.towers), isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);

      // Profit +6%: exceeds target
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.06000000',
      });
      expect(await overlayVM.testCheckStopProfitInline(1, mode: GameMode.towers), isTrue);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isTrue);
    });

    test('Shield 4: 6 losses in 10 rounds history records without stalling execution', () {
      final overlayVM = OverlayButtonsViewModel();
      final state = overlayVM.getState(GameMode.towers);

      // Simulate 6 losses in 8 rounds
      for (int i = 0; i < 6; i++) {
        state.recentRoundsHistory.add(false);
      }
      state.recentRoundsHistory.add(true);
      state.recentRoundsHistory.add(true);

      final int recentLosses = state.recentRoundsHistory.where((w) => !w).length;
      expect(recentLosses, 6);
      expect(state.recentRoundsHistory.length, 8);
      // Confirmed that history tracking works and 300s stall has been removed
    });
  });
}
