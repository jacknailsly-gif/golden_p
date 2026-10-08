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

  group('Auto Stop-Loss Disabled Specification Tests (User Directive: เอา Stop loss ออกไป)', () {
    test('getAutoStopLossPercent and autoStopLossPercent return 0.0 (Disabled 100%)', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();

      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);
      expect(overlayVM.getStopProfitPercent(GameMode.towers), 2.5);
      expect(overlayVM.getAutoStopLossPercent(GameMode.towers), 0.0,
          reason: 'Stop-loss percent must be 0.0 (Disabled)');
      expect(overlayVM.autoStopLossPercent, 0.0);

      overlayVM.setStopProfitPercent(10.0, mode: GameMode.mines);
      expect(overlayVM.getStopProfitPercent(GameMode.mines), 10.0);
      expect(overlayVM.getAutoStopLossPercent(GameMode.mines), 0.0,
          reason: 'Stop-loss percent must be 0.0 (Disabled)');
    });

    test('When balance drops <= -2.5%, Stop-Loss is disabled: returns false, never takes break, never resets debt', () async {
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

      // Balance drops to 0.975 (-2.5%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.97500000',
      });

      // Stop-Loss inline check must return false (Disabled 100%)
      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isFalse, reason: 'Stop-loss must be completely disabled');

      // 1. Break is NOT active
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);

      // 2. Debt is strictly preserved (NOT reset by Stop-Loss)
      expect(state.totalAccumulatedLoss, equals(0.05));
      expect(state.activeNewLoss, equals(0.05));
      expect(state.consecutiveLossesStreak, equals(3));
    });

    test('Large drawdown (-50%) never triggers Stop-Loss when Stop-Loss is disabled', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 1.0;
      state.activeNewLoss = 0.50;

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.50000000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      final triggered = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggered, isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
      expect(state.totalAccumulatedLoss, equals(0.50), reason: 'Debt must never be cleared by stop loss');
    });

    test('Stop Loss Drawdown Guard is disabled: getAutoStopLossPercent is 0.0, full recovery bet allowed', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();

      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      final slLimit = overlayVM.getAutoStopLossPercent(GameMode.towers);
      expect(slLimit, equals(0.0), reason: 'SL limit is 0.0 so recovery sizing is never artificially clamped by SL');
    });
  });
}
