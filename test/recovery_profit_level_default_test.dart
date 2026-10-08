import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Recovery Profit Level Default Settings Tests', () {
    test('Default profit percent and level before initialize: Towers is Level 6 (39%), Mines is Level 7 (42%)', () {
      final vm = OverlayButtonsViewModel();

      expect(vm.getRecoveryProfitPercent(GameMode.towers), equals(0.39),
          reason: 'Towers default percent must be 0.39 (Level 6)');
      expect(vm.getRecoveryProfitLevel(GameMode.towers), equals(6),
          reason: 'Towers default level must be Level 6');

      expect(vm.getRecoveryProfitPercent(GameMode.mines), equals(0.42),
          reason: 'Mines default percent must be 0.42 (Level 7)');
      expect(vm.getRecoveryProfitLevel(GameMode.mines), equals(7),
          reason: 'Mines default level must be Level 7');
    });

    test('Default profit percent and level after initialize with empty SharedPreferences', () async {
      final vm = OverlayButtonsViewModel();
      await vm.initialize();

      expect(vm.getRecoveryProfitPercent(GameMode.towers), equals(0.39),
          reason: 'Towers initialized default percent must be 0.39');
      expect(vm.getRecoveryProfitLevel(GameMode.towers), equals(6),
          reason: 'Towers initialized default level must be 6');

      expect(vm.getRecoveryProfitPercent(GameMode.mines), equals(0.42),
          reason: 'Mines initialized default percent must be 0.42');
      expect(vm.getRecoveryProfitLevel(GameMode.mines), equals(7),
          reason: 'Mines initialized default level must be 7');
    });

    test('recoveryProfitLevels labels and values match the specifications', () {
      final levels = OverlayButtonsViewModel.recoveryProfitLevels;

      final level6 = levels.firstWhere((item) => item['level'] == 6);
      expect(level6['value'], equals(0.39));
      expect(level6['label'], equals('Level 6: 39% (Default Towers)'));

      final level7 = levels.firstWhere((item) => item['level'] == 7);
      expect(level7['value'], equals(0.42));
      expect(level7['label'], equals('Level 7: 42% (Default Mines)'));

      final level8 = levels.firstWhere((item) => item['level'] == 8);
      expect(level8['value'], equals(0.48));
      expect(level8['label'], equals('Level 8: 48%'));
    });

    test('Cycle recovery profit level starts at defaults and cycles correctly', () async {
      final vm = OverlayButtonsViewModel();
      await vm.initialize();

      // Towers starts at Level 6 -> cycle goes to 7 -> 8 -> 1
      expect(vm.getRecoveryProfitLevel(GameMode.towers), equals(6));
      vm.cycleRecoveryProfitLevel(mode: GameMode.towers);
      expect(vm.getRecoveryProfitLevel(GameMode.towers), equals(7));
      expect(vm.getRecoveryProfitPercent(GameMode.towers), equals(0.42));

      // Mines starts at Level 7 -> cycle goes to 8 -> 1
      expect(vm.getRecoveryProfitLevel(GameMode.mines), equals(7));
      vm.cycleRecoveryProfitLevel(mode: GameMode.mines);
      expect(vm.getRecoveryProfitLevel(GameMode.mines), equals(8));
      expect(vm.getRecoveryProfitPercent(GameMode.mines), equals(0.48));
    });
  });
}
