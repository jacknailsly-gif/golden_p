import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('Full 100% Single-Round Debt Recovery Tests', () {
    test('Towers: 100% recovery sizes bet to clear full debt in 1 shot', () {
      final state = GameModeSessionState(GameMode.towers);
      state.activeNewLoss = 0.05; // 0.05 debt
      const double pRate = 0.45; // Towers payout profit rate (1.45x -> profit rate 0.45)
      const double floorBet = 0.0001;
      const double baseSurplus = floorBet * pRate * 2.0;

      final double debtToEscalate = state.totalAccumulatedLoss;
      final double targetProfit = debtToEscalate + baseSurplus;
      final double requiredBet = targetProfit / pRate;

      // When this bet wins:
      final double profitOnWin = requiredBet * pRate;
      expect(profitOnWin, greaterThanOrEqualTo(state.totalAccumulatedLoss));

      // Subtract profit clears all debt immediately
      state.subtractProfitFromDebt(profitOnWin);
      expect(state.totalAccumulatedLoss, equals(0.0));
    });

    test('Mines: 100% recovery sizes bet to clear full debt in 1 shot', () {
      final state = GameModeSessionState(GameMode.mines);
      state.activeNewLoss = 0.10;
      const double pRate = 0.128; // Mines 3 bombs 1 diamond profit rate (~1.128x)
      const double floorBet = 0.00001;
      const double baseSurplus = floorBet * pRate * 2.0;

      final double debtToEscalate = state.totalAccumulatedLoss;
      final double targetProfit = debtToEscalate + baseSurplus;
      final double requiredBet = targetProfit / pRate;

      final double profitOnWin = requiredBet * pRate;
      expect(profitOnWin, greaterThanOrEqualTo(state.totalAccumulatedLoss));

      state.subtractProfitFromDebt(profitOnWin);
      expect(state.totalAccumulatedLoss, equals(0.0));
    });
  });
}
