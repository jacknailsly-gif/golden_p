import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  test('Verify OmniMatrixEngine accuracy on realistic casino regime bursts', () {
    debugPrint = (String? msg, {int? wrapWidth}) {};
    final engine = OmniMatrixEngine.instance;
    engine.resetAllMemory(mode: GameMode.towers);

    final rng = Random(42);
    const int totalRounds = 500;
    const columns = ['A', 'B', 'C'];

    int wins = 0;
    String prevBomb = 'A';
    String prevBomb2 = 'B';

    int currentRegime = 0; // 0: PingPong, 1: Cyclic, 2: Sticky, 3: Random
    int regimeRoundsLeft = 0;

    for (int r = 1; r <= totalRounds; r++) {
      if (regimeRoundsLeft <= 0) {
        final p = rng.nextInt(100);
        if (p < 38) {
          currentRegime = 0; // Ping-Pong
          regimeRoundsLeft = 10 + rng.nextInt(15);
        } else if (p < 68) {
          currentRegime = 1; // Cyclic
          regimeRoundsLeft = 10 + rng.nextInt(15);
        } else if (p < 85) {
          currentRegime = 2; // Sticky
          regimeRoundsLeft = 6 + rng.nextInt(8);
        } else {
          currentRegime = 3; // Random
          regimeRoundsLeft = 3 + rng.nextInt(5);
        }
      }
      regimeRoundsLeft--;

      String actualBomb;
      switch (currentRegime) {
        case 0:
          actualBomb = prevBomb2;
          break;
        case 1:
          actualBomb = columns[(columns.indexOf(prevBomb) + 1) % 3];
          break;
        case 2:
          actualBomb = prevBomb;
          break;
        default:
          actualBomb = columns[rng.nextInt(3)];
          break;
      }
      prevBomb2 = prevBomb;
      prevBomb = actualBomb;

      final pred = engine.getNextPrediction(mode: GameMode.towers);
      final bool won = (pred.column != actualBomb);
      engine.recordOutcome(chosenColumn: pred.column, won: won, revealedBombPos: actualBomb);
      if (won) wins++;
    }

    final double winRate = (wins / totalRounds) * 100.0;
    print('Engine Win Rate on Casino Regimes: ${winRate.toStringAsFixed(2)}% (Wins: $wins / $totalRounds)');
    expect(winRate, inInclusiveRange(95.0, 100.0));
  });
}
