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

    test('When pnl <= -2.0% (with TP 2.5%), Stop Loss triggers 1-2 hour break, resets debt to 0, and records milestone', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);

      // Initial balance 1.0 DOGE
      state.sessionStartBalance = 1.0;
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

      // Trigger Stop-Loss inline
      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isTrue);

      // 1. Break is active for 1-2 hours (60 to 120 minutes)
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isTrue);
      final breakRemaining = overlayVM.getBreakRemainingDuration(GameMode.towers);
      expect(breakRemaining.inMinutes, greaterThanOrEqualTo(59));
      expect(breakRemaining.inMinutes, lessThanOrEqualTo(120));

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

      // 4. Milestone history recorded with negative pnlPercent
      expect(overlayVM.profitMilestones.isNotEmpty, isTrue);
      final lastMilestone = overlayVM.profitMilestones.first;
      expect(lastMilestone.pnlPercent, closeTo(-2.0, 0.001));
      expect(lastMilestone.targetPercent, closeTo(-2.0, 0.001));
      expect(lastMilestone.breakMinutes, greaterThanOrEqualTo(60));
      expect(lastMilestone.breakMinutes, lessThanOrEqualTo(120));
    });

    test('Stop-Loss PnL is strictly calculated from sessionStartBalance (0.125), NOT from peak ATH (0.150)', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);

      // Start at 0.125 DOGE
      state.sessionStartBalance = 0.125;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12500000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers); // SL = 2.0%

      // Profit rises to 0.150 ATH (+20%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.15000000',
      });
      state.sessionMaxBalance = 0.150;

      // Balance dips to 0.130 (down -13.3% from ATH, but still +4% above sessionStartBalance 0.125)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.13000000',
      });

      // Stop-Loss must NOT trigger because 0.130 > 0.125
      final triggeredAt130 = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggeredAt130, isFalse, reason: 'Balance is above sessionStartBalance, Stop-Loss must not trigger');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);

      // Balance drops below 0.125 to 0.1225 (-2.0% from 0.125)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12250000',
      });

      // Now Stop-Loss triggers!
      final triggeredAt1225 = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggeredAt1225, isTrue, reason: 'Balance dropped <= -2.0% from sessionStartBalance, Stop-Loss must trigger');

      // Break duration is 1-2 hours (60 to 120 minutes)
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isTrue);
      final breakRemaining = overlayVM.getBreakRemainingDuration(GameMode.towers);
      expect(breakRemaining.inMinutes, greaterThanOrEqualTo(59));
      expect(breakRemaining.inMinutes, lessThanOrEqualTo(120));

      // Stop-Loss creates a milestone record in profitMilestones with negative pnlPercent
      expect(overlayVM.profitMilestones.isNotEmpty, isTrue);
      final lastMilestone = overlayVM.profitMilestones.first;
      expect(lastMilestone.pnlPercent, closeTo(-2.0, 0.001));
      expect(lastMilestone.mode, GameMode.towers);
      expect(lastMilestone.breakMinutes, greaterThanOrEqualTo(60));
      expect(lastMilestone.breakMinutes, lessThanOrEqualTo(120));
    });

    test('Negative pnl above the threshold (e.g. -1.0% when threshold is -2.0%) does NOT trigger Stop Loss', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 1.0;

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

      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('Positive pnl (e.g. +1.5%) never triggers Stop Loss', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 1.0;

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

      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });
  });
}
