import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Direct Full Recovery Clearance Tests', () {
    late OmniMatrixEngine engine;

    setUp(() {
      engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);
    });

    test('a) High/neutral chaos (chaosIndex >= 0.50) grants clearance = full100 directly in recovery round', () {
      // With neutral/empty history, chaosIndex defaults to 0.50 (>= 0.50)
      expect(engine.calculateNormalizedEntropy(GameMode.towers), greaterThanOrEqualTo(0.50));

      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0005,
        currentBalance: 1.0,
      );

      expect(result.chaosIndex, greaterThanOrEqualTo(0.50));
      expect(result.recoveryClearance, RecoveryClearance.full100,
          reason: 'Recovery round grants full100 directly without chaos gating');
      expect(result.consensusGrade, anyOf('STICKY_SAFE', 'GOLDEN', 'AAA', 'FULL100'));
    });

    test('a2) Maximum entropy / uniform bomb spread still grants clearance = full100 in recovery round', () {
      // Populate history with uniform bomb distribution -> chaosIndex ~ 1.0
      for (int i = 0; i < 6; i++) {
        engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'A', mode: GameMode.towers);
        engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
        engine.recordOutcome(chosenColumn: 'B', won: true, revealedBombPos: 'C', mode: GameMode.towers);
      }

      expect(engine.calculateNormalizedEntropy(GameMode.towers), greaterThan(0.80));

      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0005,
        currentBalance: 1.0,
      );

      expect(result.chaosIndex, greaterThanOrEqualTo(0.50));
      expect(result.recoveryClearance, RecoveryClearance.full100,
          reason: 'High entropy does not block recovery clearance');
      expect(result.consensusGrade, anyOf('STICKY_SAFE', 'GOLDEN', 'AAA', 'FULL100'));
    });

    test('b) Low confidence does not block clearance = full100 in recovery round', () {
      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0005,
        currentBalance: 1.0,
      );

      expect(result.recoveryClearance, RecoveryClearance.full100,
          reason: 'Recovery round grants full100 regardless of confidence threshold');
      expect(result.consensusGrade, anyOf('STICKY_SAFE', 'GOLDEN', 'AAA', 'FULL100'));
    });

    test('c2) 3-loss streak or defensive cooldown still sets clearance = holdFire', () {
      for (int i = 0; i < 3; i++) {
        engine.recordOutcome(
          chosenColumn: 'A',
          won: false,
          revealedBombPos: 'A',
          mode: GameMode.towers,
        );
      }

      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0005,
        currentBalance: 1.0,
      );

      expect(result.recoveryClearance, RecoveryClearance.holdFire,
          reason: '3-loss streak must hold fire and fall back to base bet');
      expect(result.consensusGrade, 'DEFENSE');
    });

    test('c) Sticky Bomb / Grade AAA with low chaos (chaosIndex < 0.50) sets clearance = full100', () {
      // Consecutive bombs at 'A' -> stickyBombCol = 'A', entropy = 0.0 (< 0.50)
      for (int i = 0; i < 9; i++) {
        engine.recordOutcome(
          chosenColumn: 'B',
          won: true,
          revealedBombPos: 'A',
          mode: GameMode.towers,
        );
      }
      engine.recordOutcome(
        chosenColumn: 'C',
        won: false,
        revealedBombPos: 'A',
        mode: GameMode.towers,
      );

      final entropy = engine.calculateNormalizedEntropy(GameMode.towers);
      expect(entropy, lessThan(0.50), reason: 'All bombs at column A must yield near 0 entropy');

      final result = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.0005,
        currentBalance: 1.0,
      );

      expect(result.chaosIndex, lessThan(0.50));
      expect(result.recoveryClearance, RecoveryClearance.full100,
          reason: 'Sticky bomb with low chaos (< 0.50) qualifies for 100% full recovery');
      expect(result.consensusGrade, anyOf('STICKY_SAFE', 'GOLDEN', 'AAA', 'FULL100'));
    });

    test('d) canEnterRecovery returns false when clearance is holdFire, and true when full100', () async {
      final overlayVM = OverlayButtonsViewModel();
      await overlayVM.initialize();
      final state = overlayVM.getState(GameMode.towers);

      // Set active debt
      state.activeNewLoss = 0.01;
      state.consecutiveLossesStreak = 1;
      expect(state.totalAccumulatedLoss, greaterThan(0.0));

      // 1. Result with holdFire
      final holdFireResult = OmniPredictionResult(
        column: 'B',
        confidence: 72.0,
        rationale: 'Test Hold Fire',
        probabilityDistribution: {'A': 0.2, 'B': 0.72, 'C': 0.08},
        recoveryClearance: RecoveryClearance.holdFire,
        consensusGrade: 'HOLD_FIRE',
        chaosIndex: 0.65,
        marketRegime: 'CHOP',
      );

      final canRecoverWithHoldFire = overlayVM.canEnterRecovery(
        GameMode.towers,
        omniResult: holdFireResult,
      );
      expect(canRecoverWithHoldFire, isFalse,
          reason: 'canEnterRecovery must return false when clearance is holdFire');

      // 2. Result with full100
      final full100Result = OmniPredictionResult(
        column: 'B',
        confidence: 82.0,
        rationale: 'Test Full 100',
        probabilityDistribution: {'A': 0.1, 'B': 0.82, 'C': 0.08},
        recoveryClearance: RecoveryClearance.full100,
        consensusGrade: 'STICKY_SAFE',
        chaosIndex: 0.20,
        marketRegime: 'ALPHA_EDGE',
      );

      final canRecoverWithFull100 = overlayVM.canEnterRecovery(
        GameMode.towers,
        omniResult: full100Result,
      );
      expect(canRecoverWithFull100, isTrue,
          reason: 'canEnterRecovery must return true when clearance is full100');
    });
  });
}
