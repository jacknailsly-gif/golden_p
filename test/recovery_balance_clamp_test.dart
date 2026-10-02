import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('Repro & Guard: Recovery Bet Must NEVER Exceed Account Balance Tests', () {
    test('Repro: Standard rounding of balance cap can round UP above balance', () {
      const double currentBalance = 0.05436;
      // Standard roundToSignificantDigits rounds 0.05436 to 0.0544
      final double unconstrainedRounded = roundToSignificantDigits(currentBalance, digits: 3);
      expect(unconstrainedRounded, equals(0.0544));
      // Bug repro: 0.0544 > 0.05436 (exceeds balance!)
      expect(unconstrainedRounded, greaterThan(currentBalance));
    });

    test('Fix: roundToSignificantDigits with floorOnly: true NEVER exceeds balance', () {
      const double currentBalance = 0.05436;
      final double safeRounded = roundToSignificantDigits(currentBalance, digits: 3, floorOnly: true);
      expect(safeRounded, equals(0.0543));
      // Guard verified: 0.0543 <= 0.05436
      expect(safeRounded, lessThanOrEqualTo(currentBalance));
    });

    test('Fix: When debt requires 50 DOGE but balance is 2.5 DOGE, bet is clamped <= balance', () {
      const double currentBalance = 2.548;
      const double totalDebt = 50.0;
      const double pRate = 0.45;
      final double initialRequiredBet = totalDebt / pRate; // 111.11 DOGE

      expect(initialRequiredBet, greaterThan(currentBalance));

      // Apply Hard Balance Clamp Protocol:
      double safeBet = initialRequiredBet;
      if (safeBet > currentBalance) {
        safeBet = currentBalance;
      }
      safeBet = roundToSignificantDigits(safeBet, digits: 3, floorOnly: true);

      expect(safeBet, equals(2.54));
      expect(safeBet, lessThanOrEqualTo(currentBalance));
    });
  });
}
