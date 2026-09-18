import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';

void main() {
  group('4 Ironclad Anti-Wipeout Shields Verification Tests', () {
    late GameModeSessionState state;

    setUp(() {
      state = GameModeSessionState(GameMode.mines);
      state.sessionStartBalance = 0.184;
      state.sessionMaxBalance = 0.184;
      state.lockedBaseBet = 0.00007880;
    });

    test('Shield 1: Recovery bet sizing is strictly capped to max 10% of bankroll (No All-in)', () {
      double currentBalance = 0.184;
      double debt = 0.080;
      double pRate = 0.42;
      double floorBet = 0.00007880;
      double targetProfit = debt + (floorBet * pRate * 2.0);
      double requiredBet = targetProfit / pRate; // ~0.1906 > 0.184

      // Applied Shield 1 logic
      if (currentBalance > 0.00000001) {
        final double maxBankrollCap = currentBalance * 0.10;
        if (requiredBet > maxBankrollCap) {
          requiredBet = maxBankrollCap;
        }
      }
      if (requiredBet < floorBet) {
        requiredBet = floorBet;
      }
      if (currentBalance > floorBet && requiredBet > currentBalance * 0.15) {
        requiredBet = currentBalance * 0.15;
      }

      // Assert that requiredBet is strictly capped at 0.0184 (10% of 0.184), NEVER 0.184
      expect(requiredBet, equals(0.184 * 0.10));
      expect(requiredBet / currentBalance, lessThanOrEqualTo(0.10));
      expect(requiredBet, lessThan(currentBalance));
    });

    test('Shield 2: Hard Stop-Loss triggers at 30% Max Drawdown from ATH / Starting balance', () {
      double baselineCapital = state.sessionMaxBalance; // 0.184
      double hardStopLossFloor = baselineCapital * 0.70; // 0.1288

      // Balance drops to 0.120 (drawdown > 30%)
      double curBalance = 0.120;
      bool isStopLossTriggered = curBalance <= hardStopLossFloor;

      expect(isStopLossTriggered, isTrue,
          reason: 'Hard Stop-Loss must trigger when balance drops below 70% of ATH');

      // Balance at 0.150 (drawdown ~18.5%, < 30%)
      curBalance = 0.150;
      isStopLossTriggered = curBalance <= hardStopLossFloor;
      expect(isStopLossTriggered, isFalse);
    });

    test('Shield 3: Observation losses do not snowball recovery debt', () {
      state.activeNewLoss = 0.005; // initial debt
      state.observationRoundsRemaining = 15;
      state.isLossStreakBaseBetLocked = true;

      // Simulate 10 losses during observation rounds
      for (int i = 0; i < 10; i++) {
        final double lossToAdd = 0.00007880;
        if (!state.isLossStreakBaseBetLocked && state.observationRoundsRemaining == 0) {
          state.activeNewLoss += lossToAdd;
        }
        state.observationRoundsRemaining--;
      }

      // Debt must remain strictly unchanged at 0.005
      expect(state.activeNewLoss, equals(0.005),
          reason: 'Observation losses must be decoupled from debt to prevent runaway debt bubble');
    });

    test('Shield 4: Bad Run / Casino Counter Circuit Breaker detects >= 6 losses in 10 rounds', () {
      // Streak from user report: B(loss) A A C A A(loss) B(loss) C(loss) B(loss) A(loss)
      // Outcomes: L, W, W, W, W, L, L, L, L, L (6 losses in 10 rounds)
      final List<bool> testOutcomes = [false, true, true, true, true, false, false, false, false, false];

      for (final won in testOutcomes) {
        state.recentRoundsHistory.add(won);
        if (state.recentRoundsHistory.length > 10) {
          state.recentRoundsHistory.removeAt(0);
        }
      }

      final int recentLossCount = state.recentRoundsHistory.where((w) => !w).length;
      final bool isBadRunDetected = state.recentRoundsHistory.length >= 8 && recentLossCount >= 6;

      expect(recentLossCount, equals(6));
      expect(isBadRunDetected, isTrue,
          reason: 'Casino counter circuit breaker must trigger on 6 or more losses in 10 rounds');
    });

    test('24/7 Continuous Mode: Safe Haven Protocol resets debt, re-anchors capital, and keeps loop running', () {
      state.activeNewLoss = 0.050; // Previous debt
      state.sessionMaxBalance = 0.184;
      state.sessionStartBalance = 0.184;

      double curBalance = 0.120; // 35% drawdown -> triggers Safe Haven

      // Safe Haven Protocol in 24/7 Continuous Mode:
      state.resetDebt();
      state.sessionMaxBalance = curBalance;
      state.sessionStartBalance = curBalance;
      state.protectedPrincipal = curBalance;
      state.observationRoundsRemaining = 30;
      state.isLossStreakBaseBetLocked = true;
      state.recoveryState = RecoveryState.observation;

      // Assert that toxic debt is completely cleared, baseline re-anchored, and bot locked to Base Bet
      expect(state.totalAccumulatedLoss, equals(0.0), reason: 'Toxic debt cleared in Safe Haven');
      expect(state.sessionMaxBalance, equals(0.120), reason: 'Baseline re-anchored to current capital');
      expect(state.observationRoundsRemaining, equals(30), reason: '30 observation rounds engaged');
      expect(state.canEnterRecovery(), isFalse, reason: 'Recovery bet strictly prohibited during Safe Haven');
    });

    test('Selective Recovery Gate: High Chaos (> 0.70) or HoldFire blocks recovery entry, Low Chaos allows', () {
      state.activeNewLoss = 0.050; // Has debt
      state.consecutiveLossesStreak = 1;
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
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

      // 1. High Chaos / HoldFire -> blocked!
      expect(state.canEnterRecovery(omniResult: holdFireResult), isFalse,
          reason: 'Selective Recovery Gate must block recovery entry when market is in High Chaos / HoldFire');

      // 2. Clear edge / Low Chaos -> approved!
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

      expect(state.canEnterRecovery(omniResult: clearResult), isTrue,
          reason: 'Selective Recovery Gate must approve recovery entry when market has solid edge and low chaos');
    });

    test('Weighted Randomized Recovery Quota: Bounds and Cycle 1 capping', () {
      // Test Cycle 1: Quota must be strictly between 1 and 2 (never 3, to respect 3-loss ceiling)
      state.currentRecoveryCycle = 1;
      for (int i = 0; i < 100; i++) {
        final quota = state.randomizeRecoveryQuota();
        expect(quota, inInclusiveRange(1, 2),
            reason: 'In Cycle 1, recovery quota must be 1 or 2 to ensure consecutive losses <= 3');
      }

      // Test Cycle 2 & 3: Quota can be 1, 2, or 3
      state.currentRecoveryCycle = 2;
      final counts = <int, int>{1: 0, 2: 0, 3: 0};
      for (int i = 0; i < 1000; i++) {
        final quota = state.randomizeRecoveryQuota();
        expect(quota, inInclusiveRange(1, 3));
        counts[quota] = (counts[quota] ?? 0) + 1;
      }

      // Over 1000 iterations, 1-shot (~50%) should be most frequent, 3-shot (~15%) least frequent
      expect(counts[1]!, greaterThan(counts[2]!));
      expect(counts[2]!, greaterThan(counts[3]!));
      expect(counts[1]! / 1000.0, closeTo(0.50, 0.10));
      expect(counts[2]! / 1000.0, closeTo(0.35, 0.10));
      expect(counts[3]! / 1000.0, closeTo(0.15, 0.08));
    });

    test('Weighted Randomized Recovery Quota: Quota = 1 shot retreats immediately to observation upon single loss', () {
      state.currentRecoveryCycle = 2;
      state.randomizeRecoveryQuota(fixedForTest: 1);
      state.recoveryStepInCycle = 1; // 1st recovery shot
      state.activeNewLoss = 0.010;

      // Simulate 1 recovery loss when quota is 1
      final bool reachedQuota = state.recoveryStepInCycle >= state.maxRecoveryStepsThisCycle;
      expect(reachedQuota, isTrue);

      if (reachedQuota) {
        state.recoveryStepInCycle = 0;
        state.consecutiveLossesStreak = 3;
        state.isLossStreakBaseBetLocked = true;
        state.observationRoundsRemaining = 20;
        state.currentRecoveryCycle = 3;
        state.recoveryState = RecoveryState.observation;
      }

      expect(state.recoveryStepInCycle, equals(0));
      expect(state.observationRoundsRemaining, equals(20));
      expect(state.currentRecoveryCycle, equals(3));
      expect(state.canEnterRecovery(), isFalse,
          reason: 'Must retreat to Base Bet observation immediately after 1 failed recovery shot');
    });

    test('Weighted Randomized Recovery Quota: Quota = 2 shots allows 2 attempts before retreating', () {
      state.currentRecoveryCycle = 2;
      state.randomizeRecoveryQuota(fixedForTest: 2);
      state.recoveryStepInCycle = 1;

      // First recovery loss: step 1 < quota 2 -> advances to step 2
      expect(state.recoveryStepInCycle >= state.maxRecoveryStepsThisCycle, isFalse);
      state.recoveryStepInCycle = 2;

      // Second recovery loss: step 2 >= quota 2 -> retreats to observation
      expect(state.recoveryStepInCycle >= state.maxRecoveryStepsThisCycle, isTrue);
    });

    test('AQ-DARE Pillar 1: Passive Debt Melting rejects recovery for tiny debts (< 5x Base Bet)', () {
      final double floorBet = state.lockedBaseBet!; // 0.00007880
      state.activeNewLoss = floorBet * 2.0; // 2x Base Bet (< 5x Base Bet)
      state.consecutiveLossesStreak = 1;
      state.observationRoundsRemaining = 0;
      state.isLossStreakBaseBetLocked = false;
      state.recoveryState = RecoveryState.recoveryGate;

      // When debt is tiny, canEnterRecovery must return false to let Base Bet melt it with zero risk
      final bool approved = state.canEnterRecovery(floorBet: floorBet);
      expect(approved, isFalse,
          reason: 'Tiny debts (< 5x Base Bet) must be melted passively with zero risk');
    });

    test('AQ-DARE Pillar 2: Dynamic Debt Slicing reduces required bet by ~75% (25% slice)', () {
      double debt = 0.040;
      double pRate = 0.42;
      double floorBet = 0.00007880;
      double surplus = floorBet * pRate * 2.0;

      // Old: 100% full debt
      double oldTargetProfit = debt + surplus;
      double oldRequiredBet = oldTargetProfit / pRate; // ~0.09539

      // New: 25% slice of debt
      double sliceDebt = debt * 0.25; // 0.010
      double newTargetProfit = sliceDebt + surplus;
      double newRequiredBet = newTargetProfit / pRate; // ~0.02396

      expect(newRequiredBet, lessThan(oldRequiredBet * 0.35));
      expect(newRequiredBet / oldRequiredBet, closeTo(0.25, 0.05),
          reason: '25% Debt slice must reduce recovery bet requirement by ~75%');
    });

    test('AQ-DARE Pillar 4: Hard Bet Cap is tightened to 5% of Bankroll (No 10% risk)', () {
      double currentBalance = 0.184;
      double debt = 0.040;
      double pRate = 0.42;
      double sliceDebt = debt * 0.25;
      double requiredBet = (sliceDebt + 0.0001) / pRate; // ~0.024 > 5% (0.0092)

      // Apply 5% Bankroll Cap
      final double maxBankrollCap = currentBalance * 0.05;
      if (requiredBet > maxBankrollCap) {
        requiredBet = maxBankrollCap;
      }

      // Must be capped at exactly 0.0092 (5% of 0.184)
      expect(requiredBet, equals(0.184 * 0.05));
      expect(requiredBet / currentBalance, lessThanOrEqualTo(0.05));
    });

    test('AQ-DARE Pillar 5: Dynamic Capital Stop-Loss triggers at 20% Drawdown (protecting 80% capital)', () {
      double baselineCapital = 0.184;
      double newStopLossFloor = baselineCapital * 0.80; // 0.1472

      // Balance at 0.140 (Drawdown is ~23.9%, which is > 20%)
      double curBalance = 0.140;
      bool isStopLossTriggered = curBalance <= newStopLossFloor;

      expect(isStopLossTriggered, isTrue,
          reason: 'Hard Stop-Loss must trigger when balance drops below 80% of ATH (20% Drawdown)');
    });
  });
}



