import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

String formatBetAmountToSignificantDigits(double value, {int digits = 3}) {
  final double rounded = roundToSignificantDigits(value, digits: digits);
  String formatted = rounded.toStringAsFixed(8);
  if (formatted.contains('.')) {
    formatted = formatted.replaceAll(RegExp(r'0*$'), '');
    if (formatted.endsWith('.')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
  }
  return formatted;
}

void main() {
  group('Significant Digits (2-3 นัยสำคัญแบบยืดหยุ่น) Tests', () {
    test('Repro: Unrounded bets produce 5-8 significant digits', () {
      const double unroundedRecovery = 0.00341892;
      final String legacyFormat = unroundedRecovery.toStringAsFixed(8).replaceAll(RegExp(r'0*$'), '');
      expect(legacyFormat, equals('0.00341892')); // 6 significant digits (341892)
      expect(legacyFormat.length, equals(10));
    });

    test('3 significant digits: Rounds standard 3-digit values correctly', () {
      expect(formatBetAmountToSignificantDigits(0.00341892), equals('0.00342'));
      expect(formatBetAmountToSignificantDigits(0.00012345), equals('0.000123'));
      expect(formatBetAmountToSignificantDigits(0.054321), equals('0.0543'));
      expect(formatBetAmountToSignificantDigits(1.2345), equals('1.23'));
      expect(formatBetAmountToSignificantDigits(12.345), equals('12.3'));
    });

    test('2-3 flexible digits: When trailing digit is 0, strips down to 2 digits', () {
      expect(formatBetAmountToSignificantDigits(0.001204), equals('0.0012'));
      expect(formatBetAmountToSignificantDigits(0.002501), equals('0.0025'));
      expect(formatBetAmountToSignificantDigits(0.0005001), equals('0.0005'));
    });

    test('Edge cases: Minimum floors and whole numbers', () {
      expect(formatBetAmountToSignificantDigits(0.0001), equals('0.0001'));
      expect(formatBetAmountToSignificantDigits(0.00001), equals('0.00001'));
      expect(formatBetAmountToSignificantDigits(0.00007882), equals('0.0000788'));
      expect(formatBetAmountToSignificantDigits(100.0), equals('100'));
      expect(formatBetAmountToSignificantDigits(120.0), equals('120'));
    });

    test('Direct roundToSignificantDigits function returns valid double values', () {
      expect(roundToSignificantDigits(0.00341892), equals(0.00342));
      expect(roundToSignificantDigits(0.001204), equals(0.0012));
      expect(roundToSignificantDigits(0.00012345), equals(0.000123));
      expect(roundToSignificantDigits(1.2345), equals(1.23));
      expect(roundToSignificantDigits(0.0), equals(0.0));
      expect(roundToSignificantDigits(-5.0), equals(-5.0));
    });
  });
}
