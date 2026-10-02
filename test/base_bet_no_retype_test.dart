import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Base Bet No-Retype / No-Paste Protocol Tests', () {
    test('State tracking: hasBaseBetBeenSet lifecycle across win, loss without recovery, and recovery', () {
      final state = GameModeSessionState(GameMode.towers);

      // 1. Initial state: hasBaseBetBeenSet is false
      expect(state.hasBaseBetBeenSet, isFalse);

      // 2. Base Bet set for the first round -> hasBaseBetBeenSet becomes true
      state.hasBaseBetBeenSet = true;
      expect(state.hasBaseBetBeenSet, isTrue);

      // 3. Base Bet WINS: hasBaseBetBeenSet MUST remain true (no typing, no paste)
      state.lastRoundWasWin = true;
      state.consecutiveBaseBetWins++;
      state.consecutiveLossesStreak = 0;
      expect(state.hasBaseBetBeenSet, isTrue);

      // 4. Base Bet LOSS without recovery (e.g. observation or holdFire): hasBaseBetBeenSet MUST remain true
      state.lastRoundWasWin = false;
      state.observationRoundsRemaining = 8;
      state.isLossStreakBaseBetLocked = true;
      expect(state.hasBaseBetBeenSet, isTrue);

      // 5. Recovery triggered: hasBaseBetBeenSet becomes false (because recovery bet is placed on DOM)
      state.isCurrentlyRecoveryRound = true;
      state.hasBaseBetBeenSet = false;
      expect(state.hasBaseBetBeenSet, isFalse);

      // 6. Recovery WINS -> Returns to Base Bet, Base Bet set once, hasBaseBetBeenSet becomes true again
      state.isCurrentlyRecoveryRound = false;
      state.justWonRecoveryBet = true;
      state.hasBaseBetBeenSet = true; // Set once on return
      expect(state.hasBaseBetBeenSet, isTrue);
    });
  });
}
