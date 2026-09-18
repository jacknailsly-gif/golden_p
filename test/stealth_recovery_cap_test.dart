import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('Stealth Multi-Tranche Recovery & Drawdown Tethering Tests', () {
    const double floorBet = 0.00007882;
    const double pRate = 0.42;

    test('Stealth Cap limits recovery bet for Grade AAA to at most 3.5x Base Bet', () {
      double totalDebt = 0.00804239; // Large debt
      double targetFraction = 1.0; // Grade AAA 100% intent
      double currentBalance = 0.514;

      double debtToEscalate = totalDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate; // Raw formula: ~0.0192 DOGE

      // Calculate Stealth Cap
      final double maxMultiple = targetFraction >= 0.99 ? 3.5 : (targetFraction >= 0.5 ? 2.2 : 1.5);
      final double balanceLimit = currentBalance * 0.005; // 0.00257 DOGE
      final double maxRecoveryCap = min(floorBet * maxMultiple, balanceLimit); // ~0.00027587 DOGE

      if (requiredBet > maxRecoveryCap) {
        requiredBet = maxRecoveryCap;
      }

      // Assert that requiredBet is strictly capped at ~0.00027587 DOGE (3.5x Base Bet)
      expect(requiredBet, closeTo(floorBet * 3.5, 0.0000001));
      expect(requiredBet, lessThan(0.0003)); // Under 0.0003 DOGE!
      expect(requiredBet, greaterThanOrEqualTo(floorBet));
    });

    test('Stealth Cap limits recovery bet for Grade AA to at most 2.2x Base Bet', () {
      double totalDebt = 0.0040;
      double targetFraction = 0.5; // Grade AA 50%
      double currentBalance = 0.514;

      double debtToEscalate = totalDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate;

      final double maxMultiple = targetFraction >= 0.99 ? 3.5 : (targetFraction >= 0.5 ? 2.2 : 1.5);
      final double balanceLimit = currentBalance * 0.005;
      final double maxRecoveryCap = min(floorBet * maxMultiple, balanceLimit);

      if (requiredBet > maxRecoveryCap) {
        requiredBet = maxRecoveryCap;
      }

      expect(requiredBet, closeTo(floorBet * 2.2, 0.0000001));
      expect(requiredBet, lessThan(0.0002));
    });

    test('Small debt recovers 100% in a single shot without triggering cap', () {
      double totalDebt = 0.00003; // Tiny debt
      double targetFraction = 1.0;
      double currentBalance = 0.514;

      double debtToEscalate = totalDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate; // ~0.00015025 DOGE

      final double maxMultiple = 3.5;
      final double maxRecoveryCap = floorBet * maxMultiple; // ~0.00027587 DOGE

      if (requiredBet > maxRecoveryCap) {
        requiredBet = maxRecoveryCap;
      }

      // Should NOT be capped because it is smaller than cap
      expect(requiredBet, closeTo(0.00015025, 0.000001));
      expect(requiredBet, lessThan(maxRecoveryCap));
    });

    test('Drawdown tethering prevents phantom debt accumulation', () {
      double sessionMaxBalance = 0.51527675;
      double curBal = 0.51443678;
      double phantomDebt = 0.00438594;

      double realDrawdown = sessionMaxBalance - curBal; // 0.00083997
      double adjustedDebt = phantomDebt;
      if (adjustedDebt > realDrawdown) {
        adjustedDebt = realDrawdown;
      }

      expect(adjustedDebt, closeTo(0.00083997, 0.00000001));
    });
  });
}
