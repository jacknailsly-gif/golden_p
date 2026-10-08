import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Coin Min Bet / Base Bet Floors Specification Tests', () {
    test('calculateBaseBet returns correct floor for all 6 coins in Towers', () {
      // 1. USDT: 0.000005
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'USDT'), equals(0.000005));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'TETHER'), equals(0.000005));

      // 2. DOGE: 0.00007882
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'DOGE'), equals(0.00007882));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'DOGECOIN'), equals(0.00007882));

      // 3. POL: 0.00000903
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'POL'), equals(0.00000903));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'POLYGON'), equals(0.00000903));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'MATIC'), equals(0.00000903));

      // 4. FEY: 0.00171871
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'FEY'), equals(0.00171871));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'FEYORRA'), equals(0.00171871));

      // 5. PEPE: 0.3859
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'PEPE'), equals(0.3859));

      // 6. DGB: 0.000743
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'DGB'), equals(0.000743));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'DIGIBYTE'), equals(0.000743));

      // Fallback for unspecified coin -> defaults to DOGE floor (0.00007882)
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'UNKNOWN'), equals(0.00007882));
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: null), equals(0.00007882));
    });

    test('getFloorBetForMode returns correct floor for all 6 coins in Towers', () {
      final vm = OverlayButtonsViewModel();

      // 1. USDT: 0.000005
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'USDT'), equals(0.000005));

      // 2. DOGE: 0.00007882
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'DOGE'), equals(0.00007882));

      // 3. POL: 0.00000903
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'POL'), equals(0.00000903));

      // 4. FEY: 0.00171871
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'FEY'), equals(0.00171871));

      // 5. PEPE: 0.3859
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'PEPE'), equals(0.3859));

      // 6. DGB: 0.000743
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'DGB'), equals(0.000743));

      // Fallback for unspecified coin -> defaults to 0.00007882
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'OTHER'), equals(0.00007882));
    });

    test('Mines floor bet behavior: USDT is 0.000005, default is 0.00001', () {
      final vm = OverlayButtonsViewModel();

      expect(GameMode.mines.calculateBaseBet(0.0, null, coin: 'USDT'), equals(0.000005));
      expect(GameMode.mines.calculateBaseBet(0.0, null, coin: 'POL'), equals(0.00001));
      expect(vm.getFloorBetForMode(GameMode.mines, coinType: 'USDT'), equals(0.000005));
      expect(vm.getFloorBetForMode(GameMode.mines, coinType: 'POL'), equals(0.00001));
    });
  });
}
