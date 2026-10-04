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

  group('Auto Stop-Loss at 80% Ratio & Cut-Loss Protocol Tests', () {
    test('Auto Stop Loss ratio is exactly 80% of Stop Profit (e.g. TP 2.5% -> SL 2.0%)', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();

      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);
      expect(overlayVM.getStopProfitPercent(GameMode.towers), 2.5);
      expect(overlayVM.getAutoStopLossPercent(GameMode.towers), 2.0);

      overlayVM.setStopProfitPercent(10.0, mode: GameMode.mines);
      expect(overlayVM.getStopProfitPercent(GameMode.mines), 10.0);
      expect(overlayVM.getAutoStopLossPercent(GameMode.mines), 8.0);
    });

    test('When pnl <= -2.0% (with TP 2.5%), Stop Loss triggers 2-3 hour break, resets debt to 0, and resets profit tracking', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);

      // Initial balance 1.0 DOGE
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      // Simulate some accumulated debt and loss streak
      state.activeNewLoss = 0.05;
      state.consecutiveLossesStreak = 3;
      state.isCurrentlyRecoveryRound = true;
      state.recoveryStepInCycle = 2;
      expect(state.totalAccumulatedLoss, greaterThan(0.0));

      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);

      // Balance drops to 0.980 (-2.0%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.98000000',
      });
      expect(analyzerTowers.getProfitForMode(GameMode.towers), closeTo(-2.0, 0.001));

      // Trigger Stop-Loss inline
      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isTrue);

      // 1. Break is active for 2-3 hours (120 to 180 minutes)
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isTrue);
      final breakRemaining = overlayVM.getBreakRemainingDuration(GameMode.towers);
      expect(breakRemaining.inMinutes, greaterThanOrEqualTo(119));
      expect(breakRemaining.inMinutes, lessThanOrEqualTo(180));

      // 2. Debt is 100% reset (Cut-loss)
      expect(state.totalAccumulatedLoss, 0.0);
      expect(state.activeNewLoss, 0.0);
      expect(state.consecutiveLossesStreak, 0);
      expect(state.isCurrentlyRecoveryRound, isFalse);
      expect(state.recoveryStepInCycle, 0);
      expect(state.currentRecoveryCycle, 1);
      expect(state.isLossStreakBaseBetLocked, isFalse);
      expect(state.observationRoundsRemaining, 0);

      // 3. Profit tracking is reset to 0.0%
      expect(analyzerTowers.getProfitForMode(GameMode.towers), 0.0);
    });

    test('Negative pnl above the threshold (e.g. -1.0% when threshold is -2.0%) does NOT trigger Stop Loss', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      // Balance drops to 0.990 (-1.0%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.99000000',
      });
      expect(analyzerTowers.getProfitForMode(GameMode.towers), closeTo(-1.0, 0.001));

      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('Positive pnl (e.g. +1.5%) never triggers Stop Loss', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      // Balance rises to 1.015 (+1.5%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.01500000',
      });
      expect(analyzerTowers.getProfitForMode(GameMode.towers), closeTo(1.5, 0.001));

      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });
  });
}
