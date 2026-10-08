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

  group('Stop-Loss Inactivity & Recovery Protection Tests (User Directive: เอา Stop loss ออกไป)', () {
    test('1. In-flight bet deduction (isRoundInProgress == true) returns false in testCheckStopLossInline', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 0.125;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12500000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12200000',
      });

      state.isRoundInProgress = true;

      final triggeredInFlight = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggeredInFlight, isFalse, reason: 'Stop-Loss must be false (Disabled)');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('2. Settled real LOSS (isRoundInProgress == false) returns false, debt is preserved for 100% recovery', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 0.125;
      state.activeNewLoss = 0.0030;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12150000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      state.isRoundInProgress = false;

      final triggeredSettled = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggeredSettled, isFalse, reason: 'Stop-Loss is disabled 100%, must return false');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
      expect(state.totalAccumulatedLoss, equals(0.0030), reason: 'Debt must remain for recovery and not be reset');
    });

    test('3. Background watchdog testMonitorSLTP does not trigger break when Stop-Loss is disabled', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 0.125;
      state.isRunning = true;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.11000000', // -12% drawdown
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers);

      await overlayVM.testMonitorSLTP();
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse, reason: 'Watchdog must never trigger break when Stop-Loss is disabled');
    });
  });
}
