import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('Sniper Recovery (ระบบทวงหนี้แบบมือปืน) Tests', () {
    late OmniMatrixEngine engine;
    late GameModeSessionState sessionState;

    setUp(() {
      engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);
      sessionState = GameModeSessionState(GameMode.towers);
    });

    test('Case 1: มีหนี้สะสม แต่สถิติยังไม่เข้าเกณฑ์ Sniper Signal -> AI สั่ง Hold Fire / SNIPER_ABSORB (เดิน Base Bet ต่ำสุด ถนอมพอร์ต)', () {
      // Setup: History has no clear bomb pattern (uniform distribution, no eliminated bomb)
      engine.recordOutcome(chosenColumn: 'A', won: true, mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: true, mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, mode: GameMode.towers);

      // Current accumulated debt exists
      const currentDebt = 5.0;
      const currentBalance = 100.0;
      sessionState.activeNewLoss = currentDebt;

      final prediction = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: currentDebt,
        currentBalance: currentBalance,
      );

      // Without bomb pattern, eliminatedBombColumn is null -> isSniperSignal must be false
      expect(prediction.eliminatedBombColumn, isNull,
          reason: 'No clear bomb evidence -> eliminatedBombColumn must be null');
      expect(prediction.isSniperSignal, isFalse,
          reason: 'Sniper Signal must NOT fire when bomb elimination is absent');
      expect(prediction.recoveryClearance, equals(RecoveryClearance.holdFire),
          reason: 'Must hold fire and protect portfolio with base bet');
      expect(prediction.consensusGrade, equals('SNIPER_ABSORB'),
          reason: 'Consensus grade must be SNIPER_ABSORB during scouting');

      // Recovery gate must reject recovery when holdFire
      expect(sessionState.canEnterRecovery(omniResult: prediction), isFalse,
          reason: 'canEnterRecovery must return false when clearance is holdFire');
    });

    test('Case 2: สถิติเข้าเกณฑ์ Sniper Signal ครบ 3 ข้อ -> AI สั่ง RecoveryClearance.full100 ลั่นไกทวงหนี้เต็มจำนวนไม้เดียวจบ', () {
      // Setup: Verified bomb cluster at Column B (Sticky / Cluster pattern)
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'B', mode: GameMode.towers);

      // Now hit 1 loss (Streak 1, within recovery range streak < 3)
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'B', mode: GameMode.towers);

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(1));

      const currentDebt = 2.5;
      const currentBalance = 100.0;
      sessionState.activeNewLoss = currentDebt;

      final prediction = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: currentDebt,
        currentBalance: currentBalance,
      );

      // Verify Sniper Signal prerequisites:
      // 1. Bomb Elimination identified
      expect(prediction.eliminatedBombColumn, equals('B'),
          reason: 'Repeated bombs at B must identify B as eliminated bomb column');
      // 2. Positive Edge
      expect(prediction.mathematicalEdge, greaterThan(0.0),
          reason: 'Calibrated confidence must provide positive mathematical edge');
      // 3. High confidence / consensus
      expect(prediction.confidence, greaterThanOrEqualTo(72.0),
          reason: 'Sniper shot requires calibrated confidence >= 72%');
      // 4. Sniper Signal fired
      expect(prediction.isSniperSignal, isTrue,
          reason: 'All sniper criteria met -> isSniperSignal must be true');
      expect(prediction.recoveryClearance, equals(RecoveryClearance.full100),
          reason: 'Sniper signal must trigger 100% full recovery clearance');
      expect(prediction.consensusGrade, anyOf(equals('SNIPER_ONE_SHOT'), equals('SNIPER_GOLDEN')),
          reason: 'Grade must be SNIPER_ONE_SHOT or SNIPER_GOLDEN');

      // Recovery gate must pass recovery
      expect(sessionState.canEnterRecovery(omniResult: prediction), isTrue,
          reason: 'canEnterRecovery must allow recovery when clearance is full100');
    });

    test('Case 3: เมื่อชนะไม้ทวงหนี้ -> เคลียร์หนี้ และถอยกลับไปเดิน Base Bet ปกติทันที', () {
      // Setup sniper signal & win
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'B', mode: GameMode.towers);

      final recoveryPred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 3.0,
        currentBalance: 97.0,
      );
      expect(recoveryPred.recoveryClearance, equals(RecoveryClearance.full100));

      // Simulate recovery win on recommended column
      engine.recordOutcome(chosenColumn: recoveryPred.column, won: true, mode: GameMode.towers);
      sessionState.activeNewLoss = 0.0;
      sessionState.readyToRecoverLoss = 0.0;
      expect(sessionState.totalAccumulatedLoss, equals(0.0));

      // Round after winning recovery:
      final nextPred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        currentDebt: 0.0,
        currentBalance: 101.5,
      );

      // Must retreat to base bet / holdFire immediately
      expect(nextPred.recoveryClearance, equals(RecoveryClearance.holdFire),
          reason: 'Debt cleared -> must return to holdFire');
      expect(sessionState.canEnterRecovery(omniResult: nextPred), isFalse,
          reason: 'canEnterRecovery must return false when there is zero debt');
    });
  });
}
