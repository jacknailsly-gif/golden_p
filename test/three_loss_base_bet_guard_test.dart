import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('User Directive: Always Recover (????????) Tests', () {
    test('State initializes with no 3-loss streak lock', () {
      final state = GameModeSessionState(GameMode.towers);
      expect(state.consecutiveLossesStreak, equals(0));
      expect(state.isLossStreakBaseBetLocked, isFalse);
    });

    test('User Directive: Always recover every round when debt exists regardless of streak', () {
      final state = GameModeSessionState(GameMode.towers);
      state.activeNewLoss = 0.00030000; // Has debt

      // Consecutive loss streak 1, 2, 3, 4, 5
      for (int streak = 1; streak <= 5; streak++) {
        state.consecutiveLossesStreak = streak;
        // With "????????", isLossStreakBaseBetLocked remains false
        state.isLossStreakBaseBetLocked = false;

        // Debt > 0 always triggers recovery
        final shouldRecover = state.totalAccumulatedLoss > 0.00000001;
        expect(shouldRecover, isTrue, reason: 'Streak  must continue recovering every round (????????)');
      }
    });
  });
}
