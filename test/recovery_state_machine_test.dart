import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';

void main() {
  group('Recovery State Machine & Circuit Breaker Architecture Tests', () {
    late GameModeSessionState state;

    setUp(() {
      state = GameModeSessionState(GameMode.towers);
      state.sessionMaxBalance = 100.0;
      state.sessionStartBalance = 100.0;
      state.lockedBaseBet = 0.0001;
    });

    test('Scenario 1: 3 consecutive losses triggers observation mode with recovery locked', () {
      state.activeNewLoss = 0.50;
      expect(state.recoveryState, equals(RecoveryState.normal));

      // Simulate 3 consecutive losses
      state.consecutiveLossesStreak = 3;
      state.isLossStreakBaseBetLocked = true;
      const int obsRounds = 18;
      state.observationRoundsRemaining = obsRounds;
      state.recoveryState = RecoveryState.observation;

      // In observation mode, recovery must be locked out
      expect(state.observationRoundsRemaining, equals(18));
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Recovery must be locked while observation rounds are active');
    });

    test('Scenario 2: Observation completes with WIN -> transitions to recoveryGate (no auto-recovery without gate approval)', () {
      state.activeNewLoss = 0.50;
      state.recoveryState = RecoveryState.observation;
      state.isLossStreakBaseBetLocked = true;
      state.observationRoundsRemaining = 1;

      // Final round wins
      state.subtractProfitFromDebt(0.000042);
      state.observationRoundsRemaining--;
      if (state.observationRoundsRemaining <= 0) {
        state.observationRoundsRemaining = 0;
        state.isLossStreakBaseBetLocked = false;
        if (state.totalAccumulatedLoss > 0.00000001) {
          state.recoveryState = RecoveryState.recoveryGate;
        }
      }
      state.consecutiveLossesStreak = 0;

      expect(state.observationRoundsRemaining, equals(0));
      expect(state.isLossStreakBaseBetLocked, isFalse);
      expect(state.recoveryState, equals(RecoveryState.recoveryGate));
      expect(state.isPostObservationRecoveryReady, isTrue);

      // In recoveryGate, state is ready for gate evaluation
      expect(state.canEnterRecovery(), isTrue);
    });

    test('Scenario 3: Recovery loss increments recoveryLossStreak without being reset upon entering observation', () {
      state.activeNewLoss = 0.50;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.recoveryLossStreak, equals(0));

      // Execute recovery round
      state.recoveryState = RecoveryState.recovery;
      state.isCurrentlyRecoveryRound = true;

      // Recovery round LOSES
      state.activeNewLoss += 0.20;
      state.recoveryLossStreak++;
      state.recoveryAttempts++;
      state.consecutiveLossesStreak = 3; // Triggers observation
      state.isCurrentlyRecoveryRound = false;

      // Transition to observation
      state.observationRoundsRemaining = 18;
      state.recoveryState = RecoveryState.observation;
      state.isLossStreakBaseBetLocked = true;

      // Crucial verification: recoveryLossStreak MUST NOT be reset to 0 upon entering observation!
      expect(state.recoveryLossStreak, equals(1),
          reason: 'recoveryLossStreak must persist across observation periods to prevent infinite loop');
      expect(state.canEnterRecovery(), isFalse);
    });

    test('Scenario 4: 3 recovery losses triggers Circuit Breaker, halting automatic recovery and retreating to Base Bet', () {
      state.activeNewLoss = 0.70;
      state.recoveryLossStreak = 2; // 2 previous recovery losses (Cycles 1 & 2 failed)
      state.recoveryState = RecoveryState.recovery;
      state.isCurrentlyRecoveryRound = true;

      // Third recovery round LOSES
      state.activeNewLoss += 0.30;
      state.recoveryLossStreak++; // becomes 3
      state.recoveryAttempts++;

      if (state.recoveryLossStreak >= 3) {
        state.recoveryCircuitBreakerActive = true;
        state.isLossStreakBaseBetLocked = true;
        state.observationRoundsRemaining = 0;
        state.consecutiveLossesStreak = 0;
        state.recoveryState = RecoveryState.circuitBreaker;
      }
      state.isCurrentlyRecoveryRound = false;

      expect(state.recoveryLossStreak, equals(3));
      expect(state.recoveryCircuitBreakerActive, isTrue);
      expect(state.isLossStreakBaseBetLocked, isTrue);
      expect(state.recoveryState, equals(RecoveryState.circuitBreaker));

      // Gate must reject recovery unconditionally (bot retreats to Base Bet)
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Circuit breaker must unconditionally block recovery after 3 failed attempts, retreating to Base Bet');
    });

    test('Scenario 5: Selective Recovery Gate (Sniper Recovery): HoldFire or High Chaos (> 0.70) blocks recovery entry', () {
      state.activeNewLoss = 0.50;
      state.recoveryLossStreak = 0;
      state.recoveryState = RecoveryState.recoveryGate;

      const holdFireResult = OmniPredictionResult(
        column: 'B',
        confidence: 0.40,
        rationale: 'High Chaos / Market Chop detected',
        probabilityDistribution: {'A': 0.33, 'B': 0.34, 'C': 0.33},
        activeStrategyMode: 'Defensive',
        isHighConfidence: false,
        recoveryClearance: RecoveryClearance.holdFire,
        consensusGrade: 'DEFENSE',
        modelAgreementCount: 1,
        mathematicalEdge: -0.05,
        chaosIndex: 0.85,
        recommendedFluidFraction: 0.0,
        marketRegime: 'CHOP',
        isGoldenHighway: false,
        isCasinoTargeting: true,
      );

      // Evaluated against HoldFire: Selective Recovery Gate holds fire and stays at Base Bet
      final bool approved = state.canEnterRecovery(omniResult: holdFireResult);
      expect(approved, isFalse,
          reason: 'Selective Recovery Gate must block recovery entry when market is in High Chaos / HoldFire');
    });

    test('Scenario 6: Gate passes -> Recovery WIN -> Debt cleared, recoveryLossStreak reset to 0, returns to normal', () {
      state.activeNewLoss = 0.50;
      state.recoveryLossStreak = 1; // Prior recovery loss
      state.recoveryState = RecoveryState.recoveryGate;

      const clearResult = OmniPredictionResult(
        column: 'C',
        confidence: 0.85,
        rationale: 'Alpha Edge confirmed',
        probabilityDistribution: {'A': 0.10, 'B': 0.10, 'C': 0.80},
        activeStrategyMode: 'AlphaEdge',
        isHighConfidence: true,
        recoveryClearance: RecoveryClearance.full100,
        consensusGrade: 'ALPHA_EDGE',
        modelAgreementCount: 3,
        mathematicalEdge: 0.45,
        chaosIndex: 0.20,
        recommendedFluidFraction: 0.10,
        marketRegime: 'TRENDING',
        isGoldenHighway: false,
        isCasinoTargeting: false,
      );

      final bool approved = state.canEnterRecovery(omniResult: clearResult);
      expect(approved, isTrue);

      // Enter recovery
      state.recoveryState = RecoveryState.recovery;
      state.isCurrentlyRecoveryRound = true;

      // Recovery round WINS
      state.resetDebt(); // Clears debt, resets recoveryLossStreak, sets state to normal
      expect(state.totalAccumulatedLoss, equals(0.0));
      expect(state.recoveryLossStreak, equals(0));
      expect(state.recoveryAttempts, equals(0));
      expect(state.recoveryState, equals(RecoveryState.normal));
      expect(state.isCurrentlyRecoveryRound, isFalse);
    });

    test('Scenario 7: Observation completion cannot bypass active Circuit Breaker', () {
      state.activeNewLoss = 1.0;
      state.recoveryCircuitBreakerActive = true;
      state.recoveryState = RecoveryState.circuitBreaker;
      state.recoveryLossStreak = 2;

      // Complete 20 rounds of observation
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;

      // Even if observation finishes, circuit breaker must prevent recovery
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Observation completion must never bypass Circuit Breaker');
    });

    test('Scenario 8: Zero Debt Protection (totalAccumulatedLoss <= epsilon prevents recovery)', () {
      state.activeNewLoss = 0.0;
      state.readyToRecoverLoss = 0.0;
      state.frozenDebtBuckets.clear();
      expect(state.totalAccumulatedLoss, equals(0.0));

      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isFalse,
          reason: 'canEnterRecovery must return false when debt is zero');

      state.recoveryState = RecoveryState.normal;
      state.consecutiveLossesStreak = 1;
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Even with 1 streak loss, zero debt cannot enter recovery');
    });

    test('Scenario 9: 100% Full Recovery across all cycles (Hybrid Sliced Recovery removed)', () {
      state.lockedBaseBet = 0.0001;

      // Round 1 (recoveryLossStreak == 0) -> 100% Full Recovery
      state.recoveryLossStreak = 0;
      state.activeNewLoss = 10.0;
      expect(state.totalAccumulatedLoss, equals(10.0),
          reason: 'Cycle 1 must recover 100% full debt');

      // Round 2 (recoveryLossStreak == 1) -> 100% Full Recovery
      state.recoveryLossStreak = 1;
      state.activeNewLoss = 12.0;
      expect(state.totalAccumulatedLoss, equals(12.0),
          reason: 'Cycle 2 must recover 100% full debt');

      // Round 3+ (recoveryLossStreak >= 2) -> 100% Full Recovery (Hybrid Sliced Recovery removed)
      state.recoveryLossStreak = 2;
      state.activeNewLoss = 15.0;
      expect(state.totalAccumulatedLoss, equals(15.0),
          reason: 'Cycle 3+ recovers 100% full debt with 30-50 observation window');
    });

    test('Scenario 10: Strict Ban on Back-to-Back Recovery (No Back-to-Back Recovery Bets)', () {
      state.activeNewLoss = 5.0; // 5.0 DOGE debt
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue);

      // Execute 30% recovery slice round
      state.recoveryState = RecoveryState.recovery;
      state.isCurrentlyRecoveryRound = true;

      // Slice WINS! Profit pays down 30% of debt
      const double actualProfit = 1.5; // 30% of 5.0
      state.subtractProfitFromDebt(actualProfit);
      expect(state.totalAccumulatedLoss, closeTo(3.5, 0.00001));

      // Partial debt remains: must buffer cooling in Base Bet
      state.consecutiveRecoveryLosses = 0;
      state.consecutiveBaseBetWins = 0;
      state.justWonRecoveryBet = true; // 🛑 Block immediate recovery
      state.isCurrentlyRecoveryRound = false;
      state.recoveryState = RecoveryState.normal;

      // Crucial verification: Immediate next round MUST NOT be allowed to recover!
      expect(state.canEnterRecovery(), isFalse,
          reason: 'justWonRecoveryBet must strictly prevent back-to-back recovery on subsequent round');
    });

    test('Scenario 11: 100% Full Recovery Unlocked Immediately with Debt (No 3-Win Sliced Buffer)', () {
      state.activeNewLoss = 3.5; // Remaining debt
      state.recoveryState = RecoveryState.normal;
      state.justWonRecoveryBet = false;
      state.consecutiveBaseBetWins = 0;

      // In 100% Full Recovery mode, recovery is allowed immediately when debt exists
      expect(state.canEnterRecovery(), isTrue,
          reason: 'User directive: Hybrid Sliced Recovery removed, recovers immediately on debt');
    });

    test('Scenario 12: Circuit Breaker Auto-Reset upon N=3 consecutive Base Bet wins', () {
      state.activeNewLoss = 5.0;
      state.recoveryCircuitBreakerActive = true;
      state.recoveryState = RecoveryState.circuitBreaker;
      state.recoveryLossStreak = 2;
      state.consecutiveBaseBetWins = 0;

      // While Circuit Breaker is active, recovery is blocked
      expect(state.canEnterRecovery(), isFalse);

      // Base Bet Win 1 & 2
      state.consecutiveBaseBetWins = 2;
      expect(state.canEnterRecovery(), isFalse);

      // Base Bet Win 3 (Hits N=3 threshold)
      state.consecutiveBaseBetWins = 3;
      if (state.consecutiveBaseBetWins >= state.consecutiveBaseBetWinsRequiredForRecovery) {
        if (state.recoveryCircuitBreakerActive || state.recoveryState == RecoveryState.circuitBreaker) {
          state.recoveryCircuitBreakerActive = false;
          state.recoveryLossStreak = 0;
          state.isLossStreakBaseBetLocked = false;
          state.recoveryState = RecoveryState.recoveryGate;
        }
      }

      expect(state.recoveryCircuitBreakerActive, isFalse,
          reason: 'Circuit Breaker must auto-reset after 3 consecutive Base Bet wins');
      expect(state.recoveryLossStreak, equals(0));
      expect(state.recoveryState, equals(RecoveryState.recoveryGate));
      expect(state.canEnterRecovery(), isTrue,
          reason: 'System is now safely authorized to attempt a 30% recovery slice');
    });

    test('Scenario 13: 30-50 Observation rounds triggered in Cycle 3+ and unlocks 100% recovery', () {
      state.activeNewLoss = 5.0;
      state.recoveryLossStreak = 2; // Cycle 3+
      state.recoveryState = RecoveryState.observation;

      // In Cycle 3+, observation window is 30-50 rounds
      const int cycle3Obs = 40; // in [30..50]
      state.observationRoundsRemaining = cycle3Obs;
      state.isLossStreakBaseBetLocked = true;
      state.isCurrentlyRecoveryRound = false;

      // During observation, recovery is strictly locked
      expect(state.observationRoundsRemaining, equals(40));
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Recovery must be locked during 30-50 observation window');

      // Countdown finishes
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.recoveryState = RecoveryState.recoveryGate;

      // Unlocked for 100% full recovery! (Hybrid Sliced Recovery removed)
      expect(state.canEnterRecovery(), isTrue,
          reason: 'Completing 30-50 observation rounds unlocks 100% recovery for Round 3+');
    });

    test('Scenario 14: 15-25 Observation rounds triggered after failed recovery round 1', () {
      state.activeNewLoss = 5.0;
      state.recoveryLossStreak = 0;
      state.recoveryState = RecoveryState.recovery;
      state.isCurrentlyRecoveryRound = true;

      // Recovery bet LOSES
      state.activeNewLoss += 0.5;
      state.recoveryLossStreak++; // becomes 1
      state.recoveryAttempts++;

      // Trigger 15-25 observation rounds
      const int obsAfterLoss = 18; // in [15..25]
      state.observationRoundsRemaining = obsAfterLoss;
      state.isLossStreakBaseBetLocked = true;
      state.recoveryState = RecoveryState.observation;
      state.isCurrentlyRecoveryRound = false;

      expect(state.recoveryLossStreak, equals(1));
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Must observe 15-25 rounds on Base Bet before attempting Round 2');

      // Observation completes
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.recoveryState = RecoveryState.recoveryGate;

      expect(state.canEnterRecovery(), isTrue,
          reason: 'Completing 15-25 observation rounds unlocks Round 2 (100%)');
    });

    test('Scenario 15: User Directive: Cycle 1 strict 3-loss limit ("ปกติ: แพ้ [Base Bet] -> ทวง [ไม้ 1] -> แพ้ -> ทวง [ไม้ 2] -> แพ้ -> กลับ Base bet") -> observation 15-25 rounds -> advance to Cycle 2', () {
      // 1. เริ่มต้นรอบที่ 1: เดิน Base Bet ปกติ
      state.currentRecoveryCycle = 1;
      state.recoveryStepInCycle = 0;
      state.recoveryState = RecoveryState.normal;
      state.consecutiveLossesStreak = 0;
      state.activeNewLoss = 0.0;
      expect(state.canEnterRecovery(), isFalse, reason: 'Normal Base Bet without debt cannot enter recovery');

      // 2. เดิน Base Bet แพ้ตาแรก (แพ้ครั้งที่ 1) -> "แพ้ทวง": ตาถัดไปออกไม้ทวงที่ 1 ทันที! (ไม่ต้องรอ 15-25 ตา)
      state.activeNewLoss = 1.0;
      state.consecutiveLossesStreak = 1;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue, reason: 'แพ้ตาแรก -> ทวงทันที ไม้ที่ 1 ได้รับการอนุมัติ');

      // 3. ออกไม้ทวงที่ 1 -> แพ้! (แพ้ครั้งที่ 2) -> "แพ้ทวง": เลื่อนเป็นไม้ 2 ทันที!
      state.consecutiveLossesStreak = 2;
      state.recoveryStepInCycle = 2;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue, reason: 'ไม้ทวงที่ 2 ("แพ้ทวง") ได้รับการอนุมัติทวงทันทีในตาถัดไป');

      // 4. ออกไม้ทวงที่ 2 -> แพ้! (แพ้ครั้งที่ 3 ครบแล้ว: Base Bet + ไม้ 1 + ไม้ 2)!
      // คำสั่งผู้ใช้: "ปันหาใหย่คิอมัน แพ้ 3 ตาแล้ว มันยังทวงตาที่ 4 อีก ไม่ไปที่ Base bet... ปกติ แพ้ทวง แพ้ทวง แพ้ กลับ Base bet"
      // ต้องถอยกลับไป Base Bet ทันที! ห้ามทวงตาที่ 4 เด็ดขาด!
      state.consecutiveLossesStreak = 3;
      state.recoveryStepInCycle = 0;
      state.observationRoundsRemaining = 18;
      state.isLossStreakBaseBetLocked = true;
      state.currentRecoveryCycle = 2;
      state.recoveryState = RecoveryState.observation;

      // 🛑 ตาที่ 4 ต้องเป็น Base Bet เท่านั้น: canEnterRecovery ต้องเป็น FALSE อย่างเด็ดขาด!
      expect(state.canEnterRecovery(), isFalse,
          reason: 'แพ้ครบ 3 ตาแล้ว ตาที่ 4 ต้องเป็น Base Bet ห้ามทวงเด็ดขาด!');
      expect(state.consecutiveLossesStreak, equals(3));
      expect(state.observationRoundsRemaining, equals(18));

      // 5. ดูเชิงครบ 18 ตา (ลดทีละ 1) -> "ทวงทันที": เข้าสู่รอบที่ 2 ไม้ทวงที่ 1 ทันที!
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.consecutiveLossesStreak = 0;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue, reason: 'ดูเชิงครบ 15-25 ตาแล้ว -> ทวงทันทีในรอบที่ 2');
      expect(state.currentRecoveryCycle, equals(2), reason: 'เลื่อนเข้าสู่รอบที่ 2 สำเร็จ');
    });

    test('Scenario 16: User Directive: Cycle 2 3-shot recovery -> observation 15-25 rounds -> advance to Cycle 3', () {
      // 1. เข้าสู่รอบที่ 2 ไม้ทวงที่ 1 (หลังดูเชิงครบ 15-25 ตา)
      state.currentRecoveryCycle = 2;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      state.consecutiveLossesStreak = 0;
      state.activeNewLoss = 2.5;
      expect(state.canEnterRecovery(), isTrue);

      // 2. ไม้ 1 แพ้ -> ไม้ 2 ทันที!
      state.consecutiveLossesStreak = 1;
      state.recoveryStepInCycle = 2;
      expect(state.canEnterRecovery(), isTrue);

      // 3. ไม้ 2 แพ้ -> ไม้ 3 ทันที!
      state.consecutiveLossesStreak = 2;
      state.recoveryStepInCycle = 3;
      expect(state.canEnterRecovery(), isTrue);

      // 4. ไม้ 3 แพ้ -> "แพ้ กลับไป Base bet":
      // คำสั่งผู้ใช้: "ถ้ารอบ 2 แพ้ครบ 3 ตา รอ 15- 25 ตา ทวงทันที"
      // แพ้ครบ 3 ไม้แล้ว -> ต้องถอยกลับไปเดิน Base Bet ทันที! ห้ามทวงตาที่ 4!
      state.recoveryStepInCycle = 0;
      state.consecutiveLossesStreak = 3;
      state.observationRoundsRemaining = 20;
      state.isLossStreakBaseBetLocked = true;
      state.currentRecoveryCycle = 3;
      state.recoveryState = RecoveryState.observation;
      expect(state.canEnterRecovery(), isFalse,
          reason: 'รอบ 2 ทวงแพ้ครบ 3 ไม้ -> พักดูเชิง 15-25 ตา ตาที่ 4 ต้องเป็น Base Bet เท่านั้น!');

      // 5. ดูเชิงครบ 20 ตา -> "ทวงทันที" เริ่มไม้ที่ 1 ของรอบ 3!
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.consecutiveLossesStreak = 0;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue);
      expect(state.currentRecoveryCycle, equals(3), reason: 'เลื่อนเข้าสู่รอบที่ 3 สำเร็จ');
    });

    test('Scenario 17: User Directive: Cycle 3 3-shot recovery -> observation 15-25 rounds -> loops back to Cycle 1 ("วนกลับไป รอบแรก")', () {
      // 1. เข้าสู่รอบที่ 3 ไม้ทวงที่ 1
      state.currentRecoveryCycle = 3;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      state.consecutiveLossesStreak = 0;
      state.activeNewLoss = 4.0;
      expect(state.canEnterRecovery(), isTrue);

      // 2. ไม้ 1 แพ้ -> ไม้ 2 ทันที!
      state.consecutiveLossesStreak = 1;
      state.recoveryStepInCycle = 2;
      expect(state.canEnterRecovery(), isTrue);

      // 3. ไม้ 2 แพ้ -> ไม้ 3 ทันที!
      state.consecutiveLossesStreak = 2;
      state.recoveryStepInCycle = 3;
      expect(state.canEnterRecovery(), isTrue);

      // 4. ไม้ 3 แพ้ -> "แพ้ กลับไป Base bet วนกลับไป รอบแรก":
      // คำสั่งผู้ใช้: "ถ้ารอบ 3 แพ้ครบ 3 ตา รอ 15- 25 ตา ทวงทันที แพ้ทวง แพ้ทวง แพ้ กลับไป Base bet วนกลับไป รอบแรก"
      state.recoveryStepInCycle = 0;
      state.consecutiveLossesStreak = 3;
      state.observationRoundsRemaining = 15;
      state.isLossStreakBaseBetLocked = true;
      state.currentRecoveryCycle = 1; // "วนกลับไป รอบแรก"
      state.recoveryState = RecoveryState.observation;
      expect(state.canEnterRecovery(), isFalse,
          reason: 'รอบ 3 ทวงแพ้ครบ 3 ไม้ -> พักดูเชิง 15-25 ตา ก่อนวนกลับไปรอบแรก ตาที่ 4 ต้องเป็น Base Bet');

      // 5. ดูเชิงครบ 15 ตา -> "ทวงทันที วนกลับไปรอบแรก":
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.consecutiveLossesStreak = 0;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue);
      expect(state.currentRecoveryCycle, equals(1),
          reason: 'คำสั่งผู้ใช้: วนกลับไปเริ่มไม้ทวงที่ 1 ของรอบแรก');
    });

    test('Scenario 18: Recovery WIN at step 2 -> clears debt and resets cycle to 1', () {
      state.currentRecoveryCycle = 2;
      state.recoveryStepInCycle = 2; // ไม้ที่ 2
      state.activeNewLoss = 3.0;
      state.recoveryState = RecoveryState.recovery;
      state.isCurrentlyRecoveryRound = true;

      // ไม้ที่ 2 ชนะ! เคลียร์หนี้สำเร็จ
      state.subtractProfitFromDebt(3.0);
      expect(state.totalAccumulatedLoss, equals(0.0));

      // Reset debt and return to normal Cycle 1
      state.resetDebt();
      expect(state.currentRecoveryCycle, equals(1));
      expect(state.recoveryStepInCycle, equals(0));
      expect(state.consecutiveLossesStreak, equals(0));
      expect(state.recoveryState, equals(RecoveryState.normal));
      expect(state.canEnterRecovery(), isFalse, reason: 'Zero debt, back to Base Bet in cycle 1');
    });

    test('Scenario 19: Strict 3-Loss Ceiling in canEnterRecovery & Observation Countdown Integrity', () {
      state.activeNewLoss = 10.0;
      state.recoveryState = RecoveryState.recoveryGate;
      state.recoveryStepInCycle = 1;

      // When consecutiveLossesStreak < 3, recovery can be allowed
      state.consecutiveLossesStreak = 2;
      expect(state.canEnterRecovery(), isTrue);

      // When consecutiveLossesStreak reaches 3, recovery MUST be blocked unconditionally
      state.consecutiveLossesStreak = 3;
      expect(state.canEnterRecovery(), isFalse,
          reason: 'consecutiveLossesStreak >= 3 must unconditionally block recovery from ever betting round 4');

      // In observation mode with 20 rounds, winning 1 round must decrement EXACTLY 1 (to 19, never 18)
      state.observationRoundsRemaining = 20;
      state.recoveryState = RecoveryState.observation;
      state.isLossStreakBaseBetLocked = true;

      state.observationRoundsRemaining--;
      expect(state.observationRoundsRemaining, equals(19),
          reason: 'Each round must strictly decrement observation counter by 1, never double-counted');
    });

    test('Scenario 20: Round 4 after 3 losses is 100% guaranteed Base Bet and blocks recovery unconditionally', () {
      // Setup: Round 1 (Base Bet) lost, Round 2 (Rec 1) lost, Round 3 (Rec 2) lost
      state.activeNewLoss = 15.0;
      state.consecutiveLossesStreak = 3;
      state.observationRoundsRemaining = 20;
      state.isLossStreakBaseBetLocked = true;
      state.recoveryState = RecoveryState.observation;
      state.recoveryStepInCycle = 0;
      state.currentRecoveryCycle = 2;

      // In Round 4:
      // 1. canEnterRecovery MUST be false
      expect(state.canEnterRecovery(), isFalse);

      // 2. approvedForRecovery MUST be false even if an OmniPredictionResult reports High Edge
      const aggressiveOmni = OmniPredictionResult(
        column: 'A',
        confidence: 0.99,
        rationale: 'Max Edge Golden Highway',
        probabilityDistribution: {'A': 0.90, 'B': 0.05, 'C': 0.05},
        activeStrategyMode: 'Aggressive',
        isHighConfidence: true,
        recoveryClearance: RecoveryClearance.full100,
        consensusGrade: 'ALPHA',
        modelAgreementCount: 3,
        mathematicalEdge: 0.25,
        chaosIndex: 0.05,
        recommendedFluidFraction: 1.0,
        marketRegime: 'TRENDING',
        isGoldenHighway: true,
        isCasinoTargeting: false,
      );
      expect(state.canEnterRecovery(omniResult: aggressiveOmni), isFalse,
          reason: 'Even with 99% confidence and fullSpeed clearance, Round 4 after 3 losses is strictly prohibited from recovery');

      // 3. Current bet amount must strictly be Base Bet floor, never recovery
      state.currentBetAmount = state.lockedBaseBet!;
      expect(state.currentBetAmount, equals(0.0001));
      expect(state.isCurrentlyRecoveryRound, isFalse);
    });

    test('Scenario 21: Full User Directive Lifecycle (Continuous 15-25 Base Bet -> 3 Recovery Shots -> Return to 15-25 Base Bet / Win -> Base Bet)', () {
      // 1. Initial State: Bot plays only Base Bet for 15-25 rounds
      state.observationRoundsRemaining = 20;
      state.isLossStreakBaseBetLocked = true;
      state.recoveryState = RecoveryState.observation;
      state.recoveryStepInCycle = 0;
      state.currentRecoveryCycle = 1;

      // During Base Bet observation, recovery is locked out even if Base Bet loses
      state.activeNewLoss = 0.0005;
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Must play Base Bet continuously for 15-25 rounds without triggering recovery');

      // 2. Complete 15-25 rounds -> "เมื่อครบ 15-25 ตา แล้วทวงทันที"
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.consecutiveLossesStreak = 0;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue,
          reason: 'When 15-25 rounds complete and debt exists, trigger recovery shot 1 immediately');

      // 3. Recovery Shot 1 loses -> "ไม่ชนะ ทวงอีก 2 ตา": ออกไม้ 2
      state.activeNewLoss += 0.002;
      state.recoveryStepInCycle = 2;
      expect(state.canEnterRecovery(), isTrue, reason: 'Shot 1 lost -> Shot 2 immediately');

      // 4. Recovery Shot 2 loses -> ออกไม้ 3
      state.activeNewLoss += 0.006;
      state.recoveryStepInCycle = 3;
      expect(state.canEnterRecovery(), isTrue, reason: 'Shot 2 lost -> Shot 3 immediately');

      // 5. Recovery Shot 3 loses -> "ไม่ชนทั้ง 2 ตา ก็กลับไป Base bet รอ ครบ 15-25 ตา แล้วทวงทันที"
      state.activeNewLoss += 0.018;
      state.recoveryStepInCycle = 0;
      state.consecutiveLossesStreak = 3;
      state.isLossStreakBaseBetLocked = true;
      state.observationRoundsRemaining = 18; // 15-25 rounds
      state.currentRecoveryCycle = 2; // Advance to Cycle 2
      state.recoveryState = RecoveryState.observation;

      // Round 4 after 3 recovery losses MUST be Base Bet, recovery strictly blocked
      expect(state.canEnterRecovery(), isFalse,
          reason: 'All 3 recovery shots failed -> retreat to Base Bet for 15-25 rounds, no shot 4');

      // 6. Observation 18 rounds complete in Cycle 2 -> "แล้วทวงทันที"
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.consecutiveLossesStreak = 0;
      state.recoveryStepInCycle = 1;
      state.recoveryState = RecoveryState.recoveryGate;
      expect(state.canEnterRecovery(), isTrue,
          reason: 'Cycle 2 observation completed -> trigger recovery shot 1 immediately');
      expect(state.currentRecoveryCycle, equals(2));

      // 7. Shot 1 in Cycle 2 WINS -> "ชนะกลับไป Base Bet"
      state.subtractProfitFromDebt(state.totalAccumulatedLoss);
      expect(state.totalAccumulatedLoss, equals(0.0));
      state.resetDebt();
      state.observationRoundsRemaining = 22; // 15-25 rounds
      state.isLossStreakBaseBetLocked = true;
      state.recoveryState = RecoveryState.observation;
      state.recoveryStepInCycle = 0;
      state.currentRecoveryCycle = 1;

      expect(state.canEnterRecovery(), isFalse,
          reason: 'Recovery won -> returns to Base Bet for 15-25 rounds in Cycle 1');
      expect(state.recoveryStepInCycle, equals(0));
      expect(state.currentRecoveryCycle, equals(1));
    });
  });
}

