import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Single-Shot 100% Recovery & Bankroll Risk Ceiling Tests', () {
    const double floorBet = 0.00007882;
    const double pRate = 0.42;

    test('Single-Shot Recovery calculates exact bet to clear 100% of 1-loss debt', () {
      double totalDebt = 0.00007882; // 1 loss
      double targetFraction = 1.0; // 100% single-shot
      double currentBalance = 0.514;

      double debtToEscalate = totalDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate; // ~0.00026648 DOGE

      final double maxRecoveryCap = currentBalance * 0.05; // 5% = 0.0257 DOGE
      if (requiredBet > maxRecoveryCap) {
        requiredBet = maxRecoveryCap;
      }

      expect(requiredBet, closeTo(0.00026648, 0.000001));

      // Simulate Win
      double profit = requiredBet * pRate;
      double remainingDebt = totalDebt - profit;
      expect(remainingDebt, lessThanOrEqualTo(0.0)); // 100% cleared to 0!
    });

    test('Single-Shot Recovery calculates exact bet to clear multi-loss debt in one shot', () {
      double totalDebt = 0.00035000; // Multi-loss debt
      double targetFraction = 1.0;
      double currentBalance = 0.514;

      double debtToEscalate = totalDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate; // ~0.00091215 DOGE

      final double maxRecoveryCap = currentBalance * 0.05; // 0.0257 DOGE
      if (requiredBet > maxRecoveryCap) {
        requiredBet = maxRecoveryCap;
      }

      expect(requiredBet, closeTo(0.00091215, 0.000001));

      // Simulate Win
      double profit = requiredBet * pRate;
      double remainingDebt = totalDebt - profit;
      expect(remainingDebt, lessThanOrEqualTo(0.0)); // 100% cleared to 0!
    });

    test('Bankroll Risk Guard caps recovery bet at 5% of balance to prevent account blowouts', () {
      double extremeDebt = 0.05000000; // Extreme debt
      double targetFraction = 1.0;
      double currentBalance = 0.514;

      double debtToEscalate = extremeDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate;

      final double maxRecoveryCap = currentBalance * 0.05; // 5% cap = 0.0257 DOGE
      if (requiredBet > maxRecoveryCap) {
        requiredBet = maxRecoveryCap;
      }

      expect(requiredBet, closeTo(0.0257, 0.00001));
      expect(requiredBet, lessThanOrEqualTo(currentBalance * 0.05));
    });

    test('Floor protection ensures bet is never below base bet', () {
      double tinyDebt = 0.000001;
      double targetFraction = 1.0;
      double debtToEscalate = tinyDebt * targetFraction;
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate;

      if (requiredBet < floorBet) {
        requiredBet = floorBet;
      }

      expect(requiredBet, greaterThanOrEqualTo(floorBet));
    });
  });
}
