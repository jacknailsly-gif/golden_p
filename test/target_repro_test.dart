import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  test('REPRO: Current Win Rate fails to reach 95-100% target and All-in causes Wipeout', () {
    final engine = OmniMatrixEngine.instance;
    engine.resetAllMemory(mode: GameMode.towers);

    double currentBalance = 100.0;
    double accumulatedDebt = 95.0; // Simulated debt after unfavorable streak
    double pRate = 0.42;

    // 1. Debt recovery all-in repro:
    // With previous logic: if (requiredBet > currentBalance) requiredBet = currentBalance;
    double requiredBet = (accumulatedDebt + 0.001) / pRate; // ~226.2 > 100
    if (requiredBet > currentBalance) {
      requiredBet = currentBalance; // ALL IN 100%!
    }
    // If this round loses:
    currentBalance -= requiredBet;
    print('REPRO Bankroll after losing All-in recovery: $currentBalance (BUST!)');
    expect(currentBalance, equals(0.0), reason: 'Proves why portfolio busted (All-in 100%)');

    // 2. Win rate target 95-100% repro on existing engine:
    final rng = Random(42);
    int wins = 0;
    const columns = ['A', 'B', 'C'];
    String prevBomb = 'A';
    String prevBomb2 = 'B';
    const int total = 500;

    for (int i = 0; i < total; i++) {
      String actualBomb;
      final int patternType = rng.nextInt(100);
      if (patternType < 38) {
        actualBomb = prevBomb2;
      } else if (patternType < 68) {
        actualBomb = columns[(columns.indexOf(prevBomb) + 1) % 3];
      } else if (patternType < 85) {
        actualBomb = prevBomb;
      } else {
        actualBomb = columns[rng.nextInt(3)];
      }
      prevBomb2 = prevBomb;
      prevBomb = actualBomb;

      final pred = engine.getNextPrediction(mode: GameMode.towers);
      final bool won = pred.column != actualBomb;
      engine.recordOutcome(chosenColumn: pred.column, won: won, revealedBombPos: actualBomb);
      if (won) wins++;
    }

    final winRate = (wins / total) * 100.0;
    print('REPRO Current Win Rate: ${winRate.toStringAsFixed(2)}% (Target: 95.0% - 100.0%)');

    // This expectation asserts the user's required 95-100% target and will fail on current code:
    expect(winRate, inInclusiveRange(95.0, 100.0),
        reason: 'Current engine cannot reach 95-100% win rate');
  });
}
