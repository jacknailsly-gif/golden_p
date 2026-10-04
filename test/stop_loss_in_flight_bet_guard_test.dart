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

  group('Stop-Loss In-Flight Bet Guard Tests', () {
    test('1. In-flight bet deduction (isRoundInProgress == true) MUST NOT trigger Stop-Loss in testCheckStopLossInline', () async {
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
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers); // SL limit = 2.0% (drop of 0.0025 -> 0.1225)

      // Player places a recovery bet (คูณเงิน) of 0.0030 DOGE.
      // Casino DOM immediately reflects debited balance 0.12200000 (-2.4%) before M1-M3 click or Cashout!
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12200000',
      });

      // Bet is active and in-flight:
      state.isRoundInProgress = true;

      // In-flight guard: Must return false!
      final triggeredInFlight = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggeredInFlight, isFalse, reason: 'Stop-Loss must NOT trigger while round is in progress');
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });

    test('2. In-flight bet deduction (isRoundInProgress == true) MUST NOT trigger Stop-Loss in background testMonitorSLTP', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 0.125;
      state.isRunning = true;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12500000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers); // SL limit = 2.0%

      // Bet placed: DOM balance temporarily debited to 0.12200000 (-2.4%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12200000',
      });

      // Round is in-flight:
      state.isRoundInProgress = true;

      // 500ms background watchdog runs:
      await overlayVM.testMonitorSLTP();

      // Watchdog must skip evaluating in-flight rounds:
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse, reason: '_monitorSLTP must skip in-flight rounds');
    });

    test('3. After round settles as actual LOSS (isRoundInProgress == false), Stop-Loss triggers correctly', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzerTowers = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzerTowers, mode: GameMode.towers);

      final state = overlayVM.getState(GameMode.towers);
      state.sessionStartBalance = 0.125;
      state.activeNewLoss = 0.0030;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12500000',
      });
      overlayVM.setStopProfitEnabled(true, mode: GameMode.towers);
      overlayVM.setStopProfitPercent(2.5, mode: GameMode.towers); // SL limit = 2.0%

      // Round finishes and bomb hits -> settled balance is 0.12200000 (-2.4% below baseline 0.125)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12200000',
      });

      // Round is now finished:
      state.isRoundInProgress = false;

      // Post-loss Stop-Loss check runs:
      final triggeredSettled = await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers);
      expect(triggeredSettled, isTrue, reason: 'Stop-Loss must trigger on settled real loss');

      // 1-2 hour break active
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isTrue);
      final remaining = overlayVM.getBreakRemainingDuration(GameMode.towers);
      expect(remaining.inMinutes, greaterThanOrEqualTo(59));
      expect(remaining.inMinutes, lessThanOrEqualTo(120));

      // Cut-loss: debt reset to 0
      expect(state.totalAccumulatedLoss, 0.0);
    });

    test('4. After round settles as WIN with Cashout, profit is realized and Stop-Loss never fires', () async {
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

      // During round: bet in-flight
      state.isRoundInProgress = true;
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12200000',
      });
      expect(await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers), isFalse);

      // Round wins and Cashes out! Balance increases to 0.12800000 (+2.4%)
      analyzerTowers.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.12800000',
      });
      state.isRoundInProgress = false;

      expect(await overlayVM.testCheckStopLossInline(1, mode: GameMode.towers), isFalse);
      expect(overlayVM.isBreakActiveFor(GameMode.towers), isFalse);
    });
  });
}
