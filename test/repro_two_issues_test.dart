import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('Repro Issue 2: 3 Significant Figures formatting', () {
    test('roundToSignificantDigits rounds correctly to 3 sig figs', () {
      // User's explicit example: 0.000654589 -> 0.000655
      expect(roundToSignificantDigits(0.000654589, 3), equals(0.000655));
      expect(roundToSignificantDigits(0.00012345, 3), equals(0.000123));
      expect(roundToSignificantDigits(0.0000212198, 3), equals(0.0000212));
      expect(roundToSignificantDigits(0.00034498, 3), equals(0.000345));
      expect(roundToSignificantDigits(0.001999, 3), equals(0.002));
      expect(roundToSignificantDigits(1.2345, 3), equals(1.23));
      expect(roundToSignificantDigits(12.345, 3), equals(12.3));
    });
  });

  group('Repro Issue 1: Stop Profit isolated between modes', () {
    test('OverlayButtonsViewModel has independent Stop Profit per mode', () {
      final vm = OverlayButtonsViewModel();
      vm.setStopProfitEnabled(true, mode: GameMode.towers);
      vm.setStopProfitPercent(5.0, mode: GameMode.towers);

      vm.setStopProfitEnabled(false, mode: GameMode.mines);
      vm.setStopProfitPercent(12.0, mode: GameMode.mines);

      expect(vm.isStopProfitEnabledFor(GameMode.towers), isTrue);
      expect(vm.getStopProfitPercentFor(GameMode.towers), equals(5.0));

      expect(vm.isStopProfitEnabledFor(GameMode.mines), isFalse);
      expect(vm.getStopProfitPercentFor(GameMode.mines), equals(12.0));
    });
  });
}
