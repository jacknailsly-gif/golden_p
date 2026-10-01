import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('Dynamic Base Bet with Floor Guard Tests (Option 2)', () {
    test('Towers DOGE: Scales with balance / 10,000 when above floor', () {
      const mode = GameMode.towers;
      const floor = 0.00007882;

      // Balance = 100 DOGE -> 100 / 10,000 = 0.01
      expect(mode.calculateBaseBet(100.0, floor, coin: 'DOGE'), equals(0.01));

      // Balance = 5.0 DOGE -> 5 / 10,000 = 0.0005
      expect(mode.calculateBaseBet(5.0, floor, coin: 'DOGE'), equals(0.0005));

      // Balance = 1.0 DOGE -> 1 / 10,000 = 0.0001
      expect(mode.calculateBaseBet(1.0, floor, coin: 'DOGE'), equals(0.0001));
    });

    test('Towers DOGE Floor Guard: Clamps to floor when balance / 10,000 is below floor', () {
      const mode = GameMode.towers;
      const floor = 0.00007882;

      // Balance = 0.5 DOGE -> 0.5 / 10,000 = 0.00005 < 0.00007882 -> Clamped to floor!
      expect(mode.calculateBaseBet(0.5, floor, coin: 'DOGE'), equals(floor));

      // Balance = 0.01 DOGE -> Clamped to floor!
      expect(mode.calculateBaseBet(0.01, floor, coin: 'DOGE'), equals(floor));

      // Balance = 0 -> Clamped to floor!
      expect(mode.calculateBaseBet(0.0, floor, coin: 'DOGE'), equals(floor));
    });

    test('Mines POL: Scales with balance / 10,000 and respects floor guard (0.00001)', () {
      const mode = GameMode.mines;
      const floor = 0.00001;

      // Balance = 200 POL -> 200 / 10,000 = 0.02
      expect(mode.calculateBaseBet(200.0, floor, coin: 'POL'), equals(0.02));

      // Balance = 1.0 POL -> 1 / 10,000 = 0.0001
      expect(mode.calculateBaseBet(1.0, floor, coin: 'POL'), equals(0.0001));

      // Balance = 0.05 POL -> 0.05 / 10,000 = 0.000005 < 0.00001 -> Clamped to 0.00001!
      expect(mode.calculateBaseBet(0.05, floor, coin: 'POL'), equals(floor));
    });

    test('USDT across Towers & Mines: respects USDT floor (0.000005)', () {
      const floor = 0.000005;

      // 50 USDT -> 50 / 10,000 = 0.005
      expect(GameMode.towers.calculateBaseBet(50.0, floor, coin: 'USDT'), equals(0.005));
      expect(GameMode.mines.calculateBaseBet(50.0, floor, coin: 'USDT'), equals(0.005));

      // 0.01 USDT -> 0.01 / 10,000 = 0.000001 < 0.000005 -> Clamped to 0.000005
      expect(GameMode.towers.calculateBaseBet(0.01, floor, coin: 'USDT'), equals(floor));
      expect(GameMode.mines.calculateBaseBet(0.01, floor, coin: 'USDT'), equals(floor));
    });
  });
}
