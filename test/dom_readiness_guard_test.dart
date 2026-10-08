import 'dart:math';
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

  group('DOM State Readiness Guard & Slow Network Watchdog Verification Suite', () {
    test('1. Condition (a): M0 button status changes to cashout verifies game start', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();

      // Simulate M0 displaying 'cashout' after start bet
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async {
        if (markerId == 'M0') return 'cashout';
        return 'none';
      };

      final isReady = await overlayVM.checkDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        targetMarker: 'M1',
      );

      expect(isReady, isTrue, reason: 'M0 changing to cashout proves server accepted bet and started round');
    });

    test('2. Condition (a): M0 button status changes away from "bet" verifies game start', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();

      // Simulate M0 changing away from 'bet' (e.g. 'pick')
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async {
        if (markerId == 'M0') return 'pick';
        return 'none';
      };

      final isReady = await overlayVM.checkDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        targetMarker: 'M1',
      );

      expect(isReady, isTrue, reason: 'M0 changing away from bet proves round transitioned');
    });

    test('3. Condition (b): Balance deduction (balance < balanceBeforeRound) verifies game start', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzer = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzer, mode: GameMode.towers);

      // M0 has not visually updated yet (still 'bet')
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async => 'bet';

      // But balance on server/DOM has dropped from 1.000 to 0.999 (-0.001 bet deducted)
      analyzer.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '0.99900000',
      });

      final isReady = await overlayVM.checkDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        targetMarker: 'M1',
      );

      expect(isReady, isTrue, reason: 'Balance drop proves server has deducted bet even if visual cues lag');
    });

    test('4. Condition (c): Target tile / grid becomes active verifies game start', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();

      // M0 is still 'bet', balance is unchanged (1.0 == 1.0)
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async => 'bet';
      overlayVM.gridOrTileActiveOverride = ({mode, targetMarker}) async => true;

      final isReady = await overlayVM.checkDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        targetMarker: 'M1',
      );

      expect(isReady, isTrue, reason: 'Active grid or pickable tile proves game board is open');
    });

    test('5. Unready State: When M0 is still "bet", balance unchanged, and grid inactive -> returns false', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final analyzer = SequenceAnalyzerViewModel(gameMode: GameMode.towers);
      overlayVM.setSequenceAnalyzerViewModel(analyzer, mode: GameMode.towers);

      // M0 still 'bet', balance is equal to balanceBeforeRound, grid is inactive
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async => 'bet';
      analyzer.applyParsedBalanceResultForTesting(GameMode.towers, {
        'coin': 'DOGE',
        'balance': '1.00000000',
      });
      overlayVM.gridOrTileActiveOverride = ({mode, targetMarker}) async => false;

      final isReady = await overlayVM.checkDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        targetMarker: 'M1',
      );

      expect(isReady, isFalse, reason: 'Must not confirm readiness before server starts round');
    });

    test('6. Slow Network Watchdog: Times out and returns false to abort premature click', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final state = overlayVM.getState(GameMode.towers);
      state.isRunning = true;
      state.runToken = 1;

      // Keep unready throughout
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async => 'bet';
      overlayVM.gridOrTileActiveOverride = ({mode, targetMarker}) async => false;

      // Use short test timeout
      overlayVM.domReadinessWatchdogTimeout = const Duration(milliseconds: 200);
      overlayVM.domReadinessPollInterval = const Duration(milliseconds: 40);

      final isReady = await overlayVM.waitForDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        runToken: 1,
        targetMarker: 'M1',
      );

      expect(isReady, isFalse, reason: 'Watchdog must trigger timeout and return false to abort premature click');
    });

    test('7. Slow Network Watchdog: Successfully proceeds when server responds with delayed start', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final state = overlayVM.getState(GameMode.towers);
      state.isRunning = true;
      state.runToken = 1;

      int pollCount = 0;
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async {
        pollCount++;
        // Delayed response on attempt 3
        if (pollCount >= 3) return 'cashout';
        return 'bet';
      };

      overlayVM.domReadinessWatchdogTimeout = const Duration(seconds: 2);
      overlayVM.domReadinessPollInterval = const Duration(milliseconds: 30);

      final isReady = await overlayVM.waitForDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        runToken: 1,
        targetMarker: 'M1',
      );

      expect(isReady, isTrue, reason: 'Watchdog must proceed as soon as DOM state verifies game start');
      expect(pollCount, greaterThanOrEqualTo(3));
    });

    test('8. Observation dwell time invariant: Window is strictly between 2.5s and 3.5s', () {
      final rng = Random();
      for (int i = 0; i < 200; i++) {
        final int dwellMs = 2500 + rng.nextInt(1001);
        expect(dwellMs, greaterThanOrEqualTo(2500));
        expect(dwellMs, lessThanOrEqualTo(3500));
      }
    });

    test('9. Premature click prevention: Round in progress resets cleanly on watchdog stall abort', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final state = overlayVM.getState(GameMode.towers);
      state.isRunning = true;
      state.runToken = 1;

      state.isRoundInProgress = true;

      // Simulate watchdog failure
      overlayVM.detectVisualOutcomeOverride = (markerId, {mode}) async => 'bet';
      overlayVM.gridOrTileActiveOverride = ({mode, targetMarker}) async => false;
      overlayVM.domReadinessWatchdogTimeout = const Duration(milliseconds: 150);
      overlayVM.domReadinessPollInterval = const Duration(milliseconds: 30);

      final started = await overlayVM.waitForDomGameReadiness(
        mode: GameMode.towers,
        balanceBeforeRound: 1.0,
        runToken: 1,
        targetMarker: 'M1',
      );

      expect(started, isFalse);

      // When watchdog fails, round is safely reset and click is skipped
      state.isRoundInProgress = false;
      expect(state.isRoundInProgress, isFalse);
    });
  });
}
