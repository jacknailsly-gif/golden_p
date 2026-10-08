import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('OmniMatrix Prediction Enhancement Tests', () {
    late OmniMatrixEngine engine;

    setUp(() {
      engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);
    });

    test('Streak 1: Strict Anti-Repeat-Loss Guard forbids predicting lastLoss', () {
      // Record a loss on column B
      engine.recordOutcome(
        chosenColumn: 'B',
        won: false,
        revealedBombPos: 'B',
        mode: GameMode.towers,
      );

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(1));
      expect(engine.getLastLossPick(GameMode.towers), equals('B'));

      // Case A: Without external aiBrainPrediction, must NEVER pick 'B'
      final predictionA = engine.getNextPrediction(mode: GameMode.towers);
      expect(predictionA.column, isNot(equals('B')),
          reason: 'Streak 1 must strictly evade the column that just lost (B)');
      expect(predictionA.column, anyOf('A', 'C'));

      // Case B: Even if stale external AI suggests 'B', OmniMatrix must VETO and pick safe column
      final predictionB = engine.getNextPrediction(
        mode: GameMode.towers,
        aiBrainPrediction: 'B',
      );
      expect(predictionB.column, isNot(equals('B')),
          reason: 'OmniMatrix must VETO stale AI prediction pointing to lastLoss B');
      expect(predictionB.column, anyOf('A', 'C'));
    });

    test('Streak 2: Diversity Escape always selects the 3rd untouched column and never picks p2', () {
      // Pair 1: Lost on A, then lost on B -> untouched is C
      engine.resetAllMemory(mode: GameMode.towers);
      engine.recordOutcome(
        chosenColumn: 'A',
        won: false,
        revealedBombPos: 'A',
        mode: GameMode.towers,
      );
      engine.recordOutcome(
        chosenColumn: 'B',
        won: false,
        revealedBombPos: 'B',
        mode: GameMode.towers,
      );

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(2));
      final pred1 = engine.getNextPrediction(mode: GameMode.towers);
      expect(pred1.column, equals('C'),
          reason: 'When losses are p1=A and p2=B, must strictly pick the untouched column C, never B or A');

      // Pair 2: Lost on B, then lost on C -> untouched is A
      engine.resetAllMemory(mode: GameMode.towers);
      engine.recordOutcome(
        chosenColumn: 'B',
        won: false,
        revealedBombPos: 'B',
        mode: GameMode.towers,
      );
      engine.recordOutcome(
        chosenColumn: 'C',
        won: false,
        revealedBombPos: 'C',
        mode: GameMode.towers,
      );

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(2));
      final pred2 = engine.getNextPrediction(mode: GameMode.towers);
      expect(pred2.column, equals('A'),
          reason: 'When losses are p1=B and p2=C, must strictly pick the untouched column A, never C or B');

      // Pair 3: Lost on C, then lost on A -> untouched is B
      engine.resetAllMemory(mode: GameMode.towers);
      engine.recordOutcome(
        chosenColumn: 'C',
        won: false,
        revealedBombPos: 'C',
        mode: GameMode.towers,
      );
      engine.recordOutcome(
        chosenColumn: 'A',
        won: false,
        revealedBombPos: 'A',
        mode: GameMode.towers,
      );

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(2));
      final pred3 = engine.getNextPrediction(mode: GameMode.towers);
      expect(pred3.column, equals('B'),
          reason: 'When losses are p1=C and p2=A, must strictly pick the untouched column B, never A or C');
    });

    test('Anchor Rotation Guard: Rotates anchor away after 3 consecutive wins on the same column', () {
      // Win 3 consecutive rounds on column A
      engine.recordOutcome(
        chosenColumn: 'A',
        won: true,
        mode: GameMode.towers,
      );
      engine.recordOutcome(
        chosenColumn: 'A',
        won: true,
        mode: GameMode.towers,
      );
      engine.recordOutcome(
        chosenColumn: 'A',
        won: true,
        mode: GameMode.towers,
      );

      // Now request next prediction
      final prediction = engine.getNextPrediction(mode: GameMode.towers);

      // Must rotate away from 'A' to evade PRNG cluster traps
      expect(prediction.column, isNot(equals('A')),
          reason: 'After 3 consecutive wins on A, engine must rotate to B or C');
      expect(prediction.column, anyOf('B', 'C'));

      // Active anchor must now be the rotated column
      expect(engine.getActiveAnchor(GameMode.towers), equals(prediction.column),
          reason: 'Active anchor must update to the rotated column');
    });

    test('Stale AI Brain Prediction Veto: Statistical consensus overrides conflicting stale prediction', () {
      // Record multiple losses in column C so C has heavy bomb probability
      engine.recordOutcome(chosenColumn: 'A', won: true, mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: true, mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'C', mode: GameMode.towers);

      // External stale AI passes 'C'
      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        aiBrainPrediction: 'C',
      );

      expect(result.column, isNot(equals('C')),
          reason: 'OmniMatrix must override stale aiBrainPrediction C that recently bombed');
    });

    test('Markov Round Index Gap Protection: Bomb events separated by 20 rounds are not paired as Markov transitions', () {
      // Round 1: Loss at A
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);

      // Rounds 2-21: 20 consecutive wins on B without revealed bombs
      for (int i = 0; i < 20; i++) {
        engine.recordOutcome(chosenColumn: 'B', won: true, mode: GameMode.towers);
      }

      // Round 22: Loss at C
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'C', mode: GameMode.towers);

      // At Round 23 (streak 1 with last loss C):
      // The bomb at A from 21 rounds ago must NOT be paired with C as a consecutive transition
      final pred = engine.getNextPrediction(mode: GameMode.towers);

      // Strictly evades C (lastLoss)
      expect(pred.column, isNot(equals('C')), reason: 'Must evade last loss C');
      expect(pred.column, anyOf('A', 'B'));
    });

    test('Bomb Elimination Voting: Confirms most dangerous bomb column is eliminated and recorded in eliminatedBombColumn', () {
      engine.resetAllMemory(mode: GameMode.towers);

      // Create a scenario where column B has high bomb risk (repeated bomb cluster / sticky)
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);

      final pred = engine.getNextPrediction(mode: GameMode.towers);

      // Verify that eliminatedBombColumn identifies 'B' as the eliminated bomb
      expect(pred.eliminatedBombColumn, equals('B'),
          reason: 'Sticky/clustered bomb at B must be identified as eliminatedBombColumn');

      // Verify that prediction never chooses B
      expect(pred.column, isNot(equals('B')),
          reason: 'Prediction must never select the eliminated bomb column B');
      expect(pred.column, anyOf('A', 'C'));
    });

    test('Anti-Cyclic Shift Defense in Streak 2: Evades cyclic bomb at untouched column A and locks target onto p1 (B)', () {
      engine.resetAllMemory(mode: GameMode.towers);

      // Casino pattern: Cyclic bomb shifting B -> C -> A -> B -> C (next cyclic bomb will be A!)
      // Rounds 1-3: Establish initial cyclic history B -> C -> A while maintaining normal play
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'C', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: true, revealedBombPos: 'A', mode: GameMode.towers);

      // Now start next cycle and enter Streak 2:
      // Round 4 (Streak 1): Pick B, hits bomb at B
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      expect(engine.getConsecutiveLosses(GameMode.towers), equals(1));

      // Round 5 (Streak 2): Pick C, hits bomb at C
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'C', mode: GameMode.towers);
      expect(engine.getConsecutiveLosses(GameMode.towers), equals(2));

      // At Round 6 (Streak 2 with p1=B, p2=C):
      // The untouched 3rd column is A!
      // In the casino's cyclic pattern (B -> C -> A), the next bomb is rotating right onto A!
      // Old code would blindly pick A (untouched) 100% of the time and walk into the bomb.
      // New Anti-Cyclic Guard must:
      // 1. Detect that eliminatedBombColumn is A
      // 2. Veto selecting untouched column A
      // 3. Lock target onto p1 (B) which was bombed 2 rounds ago and is now safe!
      final pred = engine.getNextPrediction(mode: GameMode.towers);

      expect(pred.eliminatedBombColumn, equals('A'),
          reason: 'Markov Order 1 + Order 2 N-gram + Cyclic detector must identify A as the cyclic bomb');
      expect(pred.column, equals('B'),
          reason: 'Must lock onto safe column p1 (B) and strictly evade cyclic bomb at untouched (A)');
    });
  });
}
