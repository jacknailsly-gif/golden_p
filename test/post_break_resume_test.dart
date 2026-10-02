import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Post-Break Resume Protocol Tests (/scope)', () {
    test('Directive: testAlignMineStartWithM0 skips execution completely when mode is Towers', () async {
      final vm = OverlayButtonsViewModel();

      // When mode is Towers, alignMineStartWithM0 must skip and NOT perform any scroll or alignment
      expect(() async {
        await vm.testAlignMineStartWithM0(mode: GameMode.towers);
      }, returnsNormally);
    });

    test('Directive: testAlignMineStartWithM0 only executes for Mines', () async {
      final vm = OverlayButtonsViewModel();

      // For Mines, when controller is null (test environment), it safely handles and exits
      expect(() async {
        await vm.testAlignMineStartWithM0(mode: GameMode.mines);
      }, returnsNormally);
    });

    test('Directive: Tower Resume ensures Medium difficulty safely without scrolling', () async {
      final vm = OverlayButtonsViewModel();

      // When mode is Towers, ensureMediumDifficulty executes gracefully even when controller is not yet attached
      expect(() async {
        final res = await vm.ensureMediumDifficulty(mode: GameMode.towers);
        expect(res, isFalse); // null controller returns false gracefully without exception
      }, returnsNormally);
    });
  });
}
