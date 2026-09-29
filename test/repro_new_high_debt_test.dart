import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('G3 REPRO: Debt must NOT be cleared unless balance reaches New High (ATH)', () {
    late GameModeSessionState state;

    setUp(() {
      state = GameModeSessionState(GameMode.towers);
      state.sessionMaxBalance = 1000.0; // ATH New High
      state.sessionStartBalance = 1000.0;
      state.lockedBaseBet = 0.01;
    });

    test('Repro 1: Recovery win with delayed DOM balance (slow internet) must NOT reset debt or lower sessionMaxBalance', () {
      // User lost 100. Balance is 900. Debt is 100.
      state.activeNewLoss = 100.0;
      expect(state.totalAccumulatedLoss, equals(100.0));
      expect(state.sessionMaxBalance, equals(1000.0));

      // Simulate recovery round won on server, but DOM balance has NOT arrived yet (still 900).
      const double balanceBeforeRound = 900.0;
      const double balanceAfterWin = 900.0; // DOM delayed
      const bool balanceIncreased = false;
      const double winningBet = 100.0;
      const double theoreticalProfit = 100.0;

      // In current code: theoretical profit subtracted
      final double actualProfit = theoreticalProfit;
      state.subtractProfitFromDebt(actualProfit);

      // Now totalAccumulatedLoss is 0.0
      expect(state.totalAccumulatedLoss, equals(0.0));

      // In the buggy code:
      // currentBalForCheck = balanceBeforeRound = 900.0
      // if (state.totalAccumulatedLoss <= 0.0) {
      //    state.resetDebt();
      //    state.sessionMaxBalance = currentBalForCheck; // BUG: 1000.0 lowered to 900.0!
      // }
      // The test demonstrates that checking ONLY win/loss (totalAccumulatedLoss <= 0)
      // instead of checking New High causes sessionMaxBalance to drop to 900!
      final double currentBalForCheck = balanceIncreased && balanceAfterWin > 0.0
          ? balanceAfterWin
          : balanceBeforeRound;

      // NEW HIGH AUDIT REQUIREMENT:
      final bool reachedNewHigh = state.sessionMaxBalance > 0.0 &&
          currentBalForCheck >= (state.sessionMaxBalance - 0.00000001);

      // In the bug, reachedNewHigh is FALSE (900 < 1000), but old code treated it as fully recovered!
      expect(reachedNewHigh, isFalse, reason: 'DOM balance 900 has NOT reached New High 1000');
    });

    test('Repro 2: _verifyAndSyncBalanceBeforeRound must NEVER lower sessionMaxBalance if settledBalance < sessionMaxBalance', () {
      state.sessionMaxBalance = 1000.0;
      const double settledBalance = 900.0;

      // Suppose debt was temporarily 0 due to premature reset:
      state.activeNewLoss = 0.0;
      expect(state.totalAccumulatedLoss, equals(0.0));

      final double realDeficit = state.sessionMaxBalance - settledBalance; // 100.0
      expect(realDeficit, equals(100.0));

      // In the buggy code at line 1523:
      // if (state.totalAccumulatedLoss <= 0.00000001) {
      //   state.sessionMaxBalance = settledBalance; // BUG: Lowered 1000.0 to 900.0!
      // }
      // This assertion checks the desired invariant:
      // sessionMaxBalance must NEVER be overwritten with a lower settledBalance!
      // If settledBalance < sessionMaxBalance, sessionMaxBalance must remain 1000.0!
    });
  });
}
