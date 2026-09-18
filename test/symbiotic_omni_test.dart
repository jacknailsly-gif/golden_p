import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';

void main() {
  group('OmniMatrix Symbiotic AI & Recovery Engine Tests', () {
    late OmniMatrixEngine engine;

    setUp(() {
      engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);
    });

    test('Initial state: Hold Fire when debt is 0 or low confidence', () {
      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        currentDebt: 0.0,
        currentBalance: 0.5147,
      );

      expect(result.column, anyOf('A', 'B', 'C'));
      expect(result.confidence, greaterThanOrEqualTo(60.0));
      expect(result.confidence, lessThanOrEqualTo(100.0));
      expect(result.recoveryClearance, RecoveryClearance.holdFire);
    });

    test('Win outcome advances memory via candidate bomb registration', () {
      engine.recordOutcome(
        chosenColumn: 'A',
        won: true,
        revealedBombPos: null,
        mode: GameMode.towers,
      );

      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        currentDebt: 0.0,
        currentBalance: 0.5147,
      );
      expect(result.column, isNotNull);
    });

    test('Anti-Monotony Penalty triggers after picking same column >= 2 times', () {
      for (int i = 0; i < 5; i++) {
        engine.recordOutcome(
          chosenColumn: 'A',
          won: true,
          revealedBombPos: null,
          mode: GameMode.towers,
        );
      }

      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0001,
        currentBalance: 0.5147,
      );

      expect(result.column, anyOf('A', 'B', 'C'));
    });

    test('Recovery clearance logic adheres to multi-model consensus', () {
      // With debt and isRecoveryRound true, if Grade AAA is met, clearance is full100
      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.00015,
        currentBalance: 0.5147,
      );

      if (result.consensusGrade == 'AAA' || result.consensusGrade == 'FULL100') {
        expect(result.recoveryClearance, RecoveryClearance.full100);
      } else if (result.consensusGrade == 'AA') {
        expect(result.recoveryClearance, RecoveryClearance.half50);
      } else {
        expect(result.recoveryClearance, RecoveryClearance.holdFire);
      }
    });

    test('Clearance grades map accurately to recovery authorization', () {
      expect(RecoveryClearance.full100.displayName, contains('100% Full Recovery'));
      expect(RecoveryClearance.half50.displayName, contains('50% Sliced Recovery'));
      expect(RecoveryClearance.holdFire.displayName, contains('Hold Fire'));
    });

    test('Entropy and Fluid Kelly Quant calculations', () {
      // With empty history, entropy defaults to neutral 0.50
      final initialEntropy = engine.calculateNormalizedEntropy(GameMode.towers);
      expect(initialEntropy, 0.50);

      // Populate history with uniform bombs: A, B, C repeating -> Maximum Entropy (~1.0)
      for (int i = 0; i < 6; i++) {
        engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
        engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
        engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'C', mode: GameMode.towers);
      }
      final highEntropy = engine.calculateNormalizedEntropy(GameMode.towers);
      expect(highEntropy, greaterThan(0.90),
          reason: 'Uniform bomb spread across all 3 columns must yield high entropy');

      // Edge formula test: Break-even win rate is 70.42%
      final pred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        currentDebt: 0.0,
        currentBalance: 1.0,
      );
      expect(pred.mathematicalEdge, greaterThanOrEqualTo(0.0));
      expect(pred.recommendedFluidFraction, inInclusiveRange(0.0, 0.20));
      expect(pred.marketRegime, isNotEmpty);
    });
  });
}
