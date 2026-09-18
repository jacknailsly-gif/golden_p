import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('User Directive: AI Brain Prediction System (ระบบทายของสมอง AI) Tests', () {
    late OmniMatrixEngine engine;

    setUp(() {
      engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);
    });

    test('Step 1: AI Brain Prediction synchronization when aiBrainPrediction is provided', () {
      // Simulate SequenceAnalyzerViewModel (V19 Clean Brain) predicting 'B'
      final res = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        aiBrainPrediction: 'B',
      );

      expect(res.column, equals('B'), reason: 'Must synchronize with AI Brain prediction B');
      expect(res.activeStrategyMode, contains('AI Brain'));
      expect(res.confidence, greaterThanOrEqualTo(60.0));
      expect(res.modelAgreementCount, greaterThanOrEqualTo(1));
    });

    test('Step 2: AI Brain Multi-Model Selection when standalone (no external prediction)', () {
      // Record bombs at 'A' so that 'A' becomes dangerous and sub-models favor 'B' or 'C'
      engine.recordOutcome(chosenColumn: 'B', won: true, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: true, revealedBombPos: 'A', mode: GameMode.towers);

      final res = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
      );

      // Since column A was repeatedly the bomb, AI Brain must choose B or C
      expect(res.column, anyOf('B', 'C'), reason: 'AI Brain must avoid frequently bombed column A');
      expect(res.activeStrategyMode, contains('AI Brain'));
    });

    test('Step 3: Dynamic adaptation as game history advances', () {
      // Feed shifting bomb patterns
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'C', mode: GameMode.towers);

      final res = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        aiBrainPrediction: 'A',
      );

      expect(res.column, equals('A'));
      expect(res.consensusGrade, isNotEmpty);
    });

    test('Step 4: 3-Loss Defense - streak >= 3 triggers holdFire and sets defensive cooldown', () {
      // User Directive: ให้ปรับจาก 5 ตา มาเปัน 3 ตาครับ
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(3));
      expect(engine.getDefensiveCooldown(GameMode.towers), equals(2));

      final pred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0002,
        aiBrainPrediction: 'C',
      );
      expect(pred.column, anyOf('B', 'C'));
      expect(pred.recoveryClearance, RecoveryClearance.holdFire);
      expect(pred.consensusGrade, anyOf('DEFENSE', 'CHOP'));
    });
  });
}
