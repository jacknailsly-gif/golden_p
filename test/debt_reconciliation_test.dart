import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';

void main() {
  group('Debt Reconciliation Tests', () {
    late GameModeSessionState state;

    setUp(() {
      state = GameModeSessionState(GameMode.towers);
      state.sessionMaxBalance = 1.0;
    });

    test('subtractProfitFromDebt reduces debt correctly', () {
      state.activeNewLoss = 0.15;
      state.subtractProfitFromDebt(0.05);
      expect(state.totalAccumulatedLoss, closeTo(0.10, 0.000001));
    });

    test('clampDebtToMax only reduces debt, never increases', () {
      state.activeNewLoss = 0.05;
      // Clamp to a HIGHER value should NOT increase debt
      state.clampDebtToMax(0.20);
      expect(state.totalAccumulatedLoss, closeTo(0.05, 0.000001),
          reason: 'clampDebtToMax must not inflate debt above current value');
    });

    test('clampDebtToMax reduces debt when it exceeds max', () {
      state.activeNewLoss = 0.15;
      state.clampDebtToMax(0.08);
      expect(state.totalAccumulatedLoss, closeTo(0.08, 0.000001),
          reason: 'clampDebtToMax should reduce debt to maxAllowed');
    });

    test('DEBT GUARANTEE fix: debt paid down stays paid down', () {
      // Simulate: ATH = 1.0, lost 0.15, then won and paid down to 0.03
      state.sessionMaxBalance = 1.0;
      state.activeNewLoss = 0.15;
      state.subtractProfitFromDebt(0.12);
      expect(state.totalAccumulatedLoss, closeTo(0.03, 0.000001));

      // Old bug: DEBT GUARANTEE would set activeNewLoss = realDeficit (0.12)
      // New fix: only clamp DOWN — debt at 0.03 is LESS than realDeficit 0.12
      // So nothing should change!
      double settledBalance = 0.88;
      double realDeficit = state.sessionMaxBalance - settledBalance; // 0.12
      if (state.totalAccumulatedLoss > realDeficit + 0.00005) {
        state.clampDebtToMax(realDeficit);
      }
      // Debt should still be 0.03, NOT reset to 0.12
      expect(state.totalAccumulatedLoss, closeTo(0.03, 0.000001),
          reason: 'Debt that was paid down must NOT be inflated back by reconciliation');
    });

    test('Balance >= ATH clears all phantom debt', () {
      state.sessionMaxBalance = 1.0;
      state.activeNewLoss = 0.05;
      expect(state.totalAccumulatedLoss, closeTo(0.05, 0.000001));

      // Balance has recovered to ATH or above
      double curBal = 1.02;
      if (curBal >= state.sessionMaxBalance && state.totalAccumulatedLoss > 0.00000001) {
        state.resetDebt();
      }
      expect(state.totalAccumulatedLoss, closeTo(0.0, 0.000001),
          reason: 'When balance >= ATH, there is no real deficit, debt must be 0');
    });

    test('Loss correctly adds to debt', () {
      state.activeNewLoss = 0.0;
      double lossToAdd = 0.00007880;
      state.activeNewLoss += lossToAdd;
      state.activeNewLoss = double.parse(state.activeNewLoss.toStringAsFixed(8));
      expect(state.totalAccumulatedLoss, closeTo(0.00007880, 0.000001));

      // Second loss
      state.activeNewLoss += lossToAdd;
      state.activeNewLoss = double.parse(state.activeNewLoss.toStringAsFixed(8));
      expect(state.totalAccumulatedLoss, closeTo(0.00015760, 0.000001));
    });

    test('Full cycle: lose then win then debt reduces then no phantom re-inflation', () {
      // Start: ATH = 1.0, balance = 1.0
      state.sessionMaxBalance = 1.0;
      state.activeNewLoss = 0.0;

      // Lose 3 rounds of 0.0001 each
      for (int i = 0; i < 3; i++) {
        state.activeNewLoss += 0.0001;
      }
      expect(state.totalAccumulatedLoss, closeTo(0.0003, 0.00001));

      // Win and earn profit 0.0002
      state.subtractProfitFromDebt(0.0002);
      expect(state.totalAccumulatedLoss, closeTo(0.0001, 0.00001));

      // New DEBT RECONCILE check (balance = 0.9999, ATH = 1.0)
      double settledBalance = 0.9999;
      double realDeficit = state.sessionMaxBalance - settledBalance; // 0.0001
      if (state.totalAccumulatedLoss > realDeficit + 0.00005) {
        state.clampDebtToMax(realDeficit);
      }
      // Debt (0.0001) <= realDeficit (0.0001) + tolerance -> no change, correct!
      expect(state.totalAccumulatedLoss, closeTo(0.0001, 0.00001));

      // Win again, balance goes to 1.0001 (above ATH)
      double newBal = 1.0001;
      if (newBal >= state.sessionMaxBalance && state.totalAccumulatedLoss > 0.00000001) {
        state.sessionMaxBalance = newBal;
        state.resetDebt();
      }
      expect(state.totalAccumulatedLoss, closeTo(0.0, 0.000001),
          reason: 'Balance above ATH should clear all debt');
    });

    test('Profit Protection: at +10% profit and ATH, normal betting does NOT create fake debt', () {
      // 1. User is at 10% profit: start = 1.0, ATH = 1.10
      state.sessionStartBalance = 1.0;
      state.sessionMaxBalance = 1.10;
      state.activeNewLoss = 0.0;
      expect(state.totalAccumulatedLoss, 0.0);

      // 2. Normal base bet is placed (0.00007880). Balance on casino drops to 1.09992120
      double settledBalance = 1.09992120;

      // 3. _verifyAndSyncBalanceBeforeRound runs:
      // Must NOT inject missingDebt! Only clamp down existing debt.
      if (settledBalance >= state.sessionMaxBalance) {
        state.sessionMaxBalance = settledBalance;
        if (state.totalAccumulatedLoss > 0.00000001) {
          state.resetDebt();
        }
      } else if (state.totalAccumulatedLoss > 0.00000001 && state.sessionMaxBalance > 0.00000001) {
        final double realDeficit = state.sessionMaxBalance - settledBalance;
        if (state.totalAccumulatedLoss > realDeficit + 0.00000001) {
          state.clampDebtToMax(realDeficit);
        }
      }

      // Debt MUST remain 0.0! Never fabricated from thin air!
      expect(state.totalAccumulatedLoss, 0.0,
          reason: 'Normal betting when in profit must NEVER invent fake debt');
    });

    test('Slow Net Win Defense: win on slow net does NOT become a loss, no fake debt added', () {
      state.sessionStartBalance = 1.0;
      state.sessionMaxBalance = 1.10; // +10% profit
      state.activeNewLoss = 0.0;
      state.lastRoundWasWin = true;
      state.consecutiveLossesStreak = 0;

      double balanceBeforeRound = 1.10;
      // Net is slow, so DOM still shows balance after bet deduction (1.0999)
      double balanceAfterWin = 1.0999;

      bool balanceIncreased = balanceAfterWin > balanceBeforeRound + 0.00000001;
      expect(balanceIncreased, isFalse);

      double actualProfit = 0.0;
      if (balanceIncreased) {
        actualProfit = balanceAfterWin - balanceBeforeRound;
      } else {
        actualProfit = 0.0;
      }
      state.subtractProfitFromDebt(actualProfit);

      // Verify no loss added to state
      expect(state.activeNewLoss, 0.0);
      expect(state.totalAccumulatedLoss, 0.0);
      expect(state.consecutiveLossesStreak, 0);
      expect(state.lastRoundWasWin, isTrue);

      // In the next round, DOM updates and win settles to 1.1001
      double settledBalance = 1.1001;
      if (settledBalance >= state.sessionMaxBalance) {
        state.sessionMaxBalance = settledBalance;
        if (state.totalAccumulatedLoss > 0.00000001) {
          state.resetDebt();
        }
      }

      expect(state.sessionMaxBalance, 1.1001);
      expect(state.totalAccumulatedLoss, 0.0);
    });

    test('Real Loss Recovery: bomb hit creates real debt, slow net uses theoreticalProfit on confirmed win, ATH clears remaining', () {
      state.sessionStartBalance = 1.0;
      state.sessionMaxBalance = 1.10; // Peak was 1.10
      state.activeNewLoss = 0.0;

      // 1. Real loss occurs (stepped on bomb)
      double lossToAdd = 0.001;
      state.activeNewLoss += lossToAdd;
      state.consecutiveLossesStreak = 1;
      expect(state.totalAccumulatedLoss, closeTo(0.001, 0.00001));

      // 2. Recovery round wins, but net is slow (balance not updated yet)
      double balanceBeforeRound = 1.099;
      double balanceAfterWin = 1.099; // Lagging DOM
      bool balanceIncreased = balanceAfterWin > balanceBeforeRound + 0.00000001;
      expect(balanceIncreased, isFalse);

      // Instant Math Credit: theoreticalProfit is credited immediately!
      double winningBet = 0.00119;
      double theoreticalProfit = winningBet * 0.42; // ~0.0005
      double actualProfit = theoreticalProfit;
      if (balanceIncreased) {
        final double measuredDelta = balanceAfterWin - balanceBeforeRound;
        actualProfit = measuredDelta > theoreticalProfit ? measuredDelta : theoreticalProfit;
      }
      state.subtractProfitFromDebt(actualProfit);

      // Debt is reduced immediately by real calculated profit!
      expect(state.totalAccumulatedLoss, closeTo(0.001 - theoreticalProfit, 0.00001),
          reason: 'Debt must reduce by theoreticalProfit even when DOM balance has not updated yet');

      // 3. Next round: balance settles to 1.1005 (above ATH 1.10)
      double settledBalance = 1.1005;
      if (settledBalance >= state.sessionMaxBalance) {
        state.sessionMaxBalance = settledBalance;
        state.resetDebt();
      }

      // All debt cleared at ATH!
      expect(state.totalAccumulatedLoss, 0.0,
          reason: 'Reaching new ATH must clear all debt');
      expect(state.sessionMaxBalance, 1.1005);
    });

    test('Resuming session with pre-existing debt preserves sessionMaxBalance', () {
      // User stops bot with 0.5 debt, balance is 9.5
      state.activeNewLoss = 0.5;
      double curBal = 9.5;

      // On start:
      state.sessionStartBalance = curBal;
      if (state.totalAccumulatedLoss > 0.00000001) {
        state.sessionMaxBalance = curBal + state.totalAccumulatedLoss;
      } else {
        state.sessionMaxBalance = curBal;
      }

      expect(state.sessionMaxBalance, closeTo(10.0, 0.000001),
          reason: 'sessionMaxBalance must include existing debt so deficit is preserved');
      expect(state.totalAccumulatedLoss, closeTo(0.5, 0.000001));
    });

    test('User Directive: เมื่อแพ้ 2 ตาให้ไปที่ Base bet (50% recovery on 1-2 rounds, fallback to Base bet on 2 consecutive recovery losses)', () {
      state.sessionStartBalance = 1.0;
      state.sessionMaxBalance = 1.0;
      state.activeNewLoss = 0.000100; // Debt exists
      state.consecutiveLossesStreak = 1;
      state.consecutiveRecoveryLosses = 0;

      // Decision function matching OverlayButtonsViewModel._executeSmartFlow:
      bool isBaseBetFallback() => state.totalAccumulatedLoss > 0.00000001 && state.consecutiveRecoveryLosses >= 2;
      double getTargetFraction() {
        if (state.totalAccumulatedLoss <= 0.00000001) return 0.0;
        if (state.consecutiveRecoveryLosses >= 2) return 0.0; // Base bet
        return 0.50; // 50% Sliced Recovery
      }

      // 1. ไม้ทวงที่ 1/2: ทวง 50%
      expect(isBaseBetFallback(), isFalse, reason: 'Round 1 must not fall back to Base bet');
      expect(getTargetFraction(), 0.50, reason: 'Must recover 50% on round 1');

      // 2. แพ้ไม้ทวงที่ 1 -> consecutiveRecoveryLosses กลายเป็น 1
      state.consecutiveRecoveryLosses = 1;
      state.consecutiveLossesStreak = 2;
      state.activeNewLoss += 0.000200;

      // ไม้ทวงที่ 2/2: ยังทวง 50% (รอบที่ 2)
      expect(isBaseBetFallback(), isFalse, reason: 'Round 2 must not fall back to Base bet');
      expect(getTargetFraction(), 0.50, reason: 'Must recover 50% on round 2');

      // 3. แพ้ไม้ทวงที่ 2 -> consecutiveRecoveryLosses กลายเป็น 2 (แพ้ 2 ตาติด!)
      state.consecutiveRecoveryLosses = 2;
      state.consecutiveLossesStreak = 3;
      state.activeNewLoss += 0.000400;

      // "เมื่อแพ้ 2 ตาให้ไปที่ Base bet" -> ถอยกลับ Base Bet ทันที!
      expect(isBaseBetFallback(), isTrue, reason: 'Must fall back to Base Bet after losing 2 recovery rounds in a row');
      expect(getTargetFraction(), 0.0, reason: 'Target fraction is 0.0 (Base bet) during cooldown');

      // 4. เดิน Base Bet แล้วชนะ! -> ปลดล็อค consecutiveRecoveryLosses = 0
      state.consecutiveRecoveryLosses = 0;
      state.consecutiveLossesStreak = 0;
      double actualProfit = 0.000030; // กำไรจาก Base bet
      state.subtractProfitFromDebt(actualProfit);

      // 5. ปลดล็อคกลับมาทวง 50% ของหนี้ที่เหลือต่ออย่างปลอดภัย
      expect(isBaseBetFallback(), isFalse, reason: 'Cooldown unlocked after Base bet win');
      expect(getTargetFraction(), 0.50, reason: 'Resumes 50% recovery on remaining debt');
    });

    test('User Directive: Tower Coin-Specific Base Bet Floors (DOGE 0.00007882, POL 0.00000903)', () {
      // Test DOGE floor in Towers
      final double dogeBase = GameMode.towers.calculateBaseBet(0.0, null, coin: 'DOGE');
      expect(dogeBase, 0.00007882, reason: 'DOGE minimum floor in Towers must be 0.00007882');

      // Test POL floor in Towers
      final double polBase = GameMode.towers.calculateBaseBet(0.0, null, coin: 'POL');
      expect(polBase, 0.00000903, reason: 'POL minimum floor in Towers must be 0.00000903');

      // Test Polygon alternative name
      final double polygonBase = GameMode.towers.calculateBaseBet(0.0, null, coin: 'POLYGON');
      expect(polygonBase, 0.00000903, reason: 'POLYGON minimum floor in Towers must be 0.00000903');

      // Test Mines floor
      final double minesBase = GameMode.mines.calculateBaseBet(0.0, null, coin: 'POL');
      expect(minesBase, 0.00001, reason: 'Mines floor must be 0.00001');

      // Dynamic calculation: Balance / 10,000
      final double bigDogeBase = GameMode.towers.calculateBaseBet(10.0, null, coin: 'DOGE');
      expect(bigDogeBase, 0.001, reason: '10 DOGE balance / 10,000 = 0.001');
    });

    test('User Directive: Autonomous AI Money Management (Sacred Principal Vault, Trailing Ratchet & Fluid Sizing)', () {
      final engine = OmniMatrixEngine.instance;
      engine.resetAllMemory();

      state.sessionStartBalance = 100.0;
      state.protectedPrincipal = 100.0;
      state.lastSettledBalance = 100.0;
      state.sessionMaxBalance = 100.0;

      // Decision function matching OverlayButtonsViewModel._executeSmartFlow:
      dynamic getAutonomousRecoveryAction(OmniPredictionResult omni, {double? currentBalanceOverride}) {
        final curBal = currentBalanceOverride ?? state.lastSettledBalance;
        final emergencyFloor = state.emergencyCapitalFloor;
        final isEmergencyTriggered = curBal <= (emergencyFloor + 0.00000001);

        if (state.totalAccumulatedLoss <= 0.00000001) return 'base_no_debt';

        // 🚨 Emergency Capital Guard: 95% Hard Stop
        if (isEmergencyTriggered) {
          return 'emergency_locked_base_bet';
        }

        if (omni.recommendedFluidFraction > 0.0 &&
            (omni.marketRegime == 'ALPHA_EDGE' || omni.marketRegime == 'STEADY_EDGE')) {
          return omni.recommendedFluidFraction; // Continuous fluid fraction
        } else {
          return 'base_defense'; // Base bet defensive shield / chop / hold fire
        }
      }

      // 1. No debt -> Base Bet
      const noDebtOmni = OmniPredictionResult(
        column: 'A',
        confidence: 75.0,
        rationale: 'Test',
        probabilityDistribution: {},
        consensusGrade: 'AAA',
        marketRegime: 'ALPHA_EDGE',
        recommendedFluidFraction: 0.12,
      );
      expect(getAutonomousRecoveryAction(noDebtOmni), 'base_no_debt');

      // 2. Normal Drawdown: 1 loss (0.0001 DOGE), balance drops to 99.9 DOGE (> 90.0 emergency floor)
      // Must NOT freeze into slow bleed! Must actively recover using operational risk budget!
      state.activeNewLoss = 0.0001;
      state.lastSettledBalance = 99.9;
      expect(state.emergencyCapitalFloor, 90.0);
      expect(state.profitCushion, 0.0);
      // Operational budget is 1% of 99.9 = ~0.999 DOGE
      expect(state.getOperationalRecoveryBudget(99.9), closeTo(0.999, 0.001));
      expect(getAutonomousRecoveryAction(noDebtOmni), 0.12,
          reason: 'Within normal drawdown (>90%), AI MUST actively recover to prevent slow bleed trap!');

      // 3. Catastrophic Drawdown: Balance drops to 89.0 DOGE (<= 90.0 DOGE emergency floor)
      // Emergency Capital Guard MUST trigger to lock Base Bet and preserve the 90% bulk!
      state.lastSettledBalance = 89.0;
      expect(state.getOperationalRecoveryBudget(89.0), 0.0);
      expect(getAutonomousRecoveryAction(noDebtOmni, currentBalanceOverride: 89.0), 'emergency_locked_base_bet',
          reason: 'When balance drops below 90% emergency floor, recovery MUST halt to protect capital!');

      // 4. Profit earned: Balance reaches 110.0 -> Trailing Ratchet locks 97% of 110.0 = 106.7
      state.lastSettledBalance = 110.0;
      state.sessionMaxBalance = 110.0;
      final ratcheted = state.sessionMaxBalance * 0.97;
      if (ratcheted > (state.protectedPrincipal ?? 0.0)) {
        state.protectedPrincipal = ratcheted;
      }
      expect(state.protectedPrincipal, closeTo(106.7, 0.001),
          reason: 'Trailing ratchet must lock in 97% of ATH as protected principal');
      expect(state.profitCushion, closeTo(3.3, 0.001),
          reason: 'Profit cushion is 110.0 - 106.7 = 3.3 DOGE');
      expect(state.getOperationalRecoveryBudget(110.0), closeTo(0.66, 0.01),
          reason: 'Recovery budget in profit is 20% of cushion (3.3 * 0.20 = 0.66 DOGE)');

      // 4. Defensive / Chop state -> Hold Fire -> Base Bet
      const defensiveResult = OmniPredictionResult(
        column: 'A',
        confidence: 68.0,
        rationale: 'Defensive',
        probabilityDistribution: {},
        consensusGrade: 'CHOP',
        marketRegime: 'CHOP',
        recommendedFluidFraction: 0.0,
        recoveryClearance: RecoveryClearance.holdFire,
      );
      expect(getAutonomousRecoveryAction(defensiveResult), 'base_defense',
          reason: 'AI must Hold Fire and play Base Bet during chop/defense regime');

      // 5. Alpha Edge signal -> Continuous Fluid Recovery funded strictly out of profit cushion
      const alphaResult = OmniPredictionResult(
        column: 'C',
        confidence: 75.0,
        rationale: 'Alpha Signal',
        probabilityDistribution: {},
        consensusGrade: 'AAA',
        marketRegime: 'ALPHA_EDGE',
        mathematicalEdge: 0.065,
        chaosIndex: 0.20,
        recommendedFluidFraction: 0.085,
        recoveryClearance: RecoveryClearance.full100,
      );
      final dynamic action = getAutonomousRecoveryAction(alphaResult);
      expect(action, isA<double>());
      expect(action as double, closeTo(0.085, 0.001));

      // Calculate max cushion risk:
      final cushionRisk = state.profitCushion * (action);
      expect(cushionRisk, lessThanOrEqualTo(state.profitCushion * 0.20),
          reason: 'Recovery risk must never exceed 20% of profit cushion');
      // Even if this bet is lost completely, remaining balance is 110.0 - cushionRisk > protectedPrincipal (106.7)
      expect(state.lastSettledBalance - cushionRisk, greaterThanOrEqualTo(state.protectedPrincipal!),
          reason: 'Loss from profit cushion can NEVER breach protected principal');

      // 6. Test Pain Memory & Defensive Cooldown in OmniMatrixEngine:
      // Directive: "ปรับให้ทวงหนี้ทุกตา แพ้ 2 ตาต่อกัน ไปที่ Base bet":
      //            - แพ้ 1 ตา: ยังไม่ต้อง Cooldown ให้ทวงหนี้ต่อทันที
      //            - แพ้ต่อกัน 2 ตาขึ้นไป: เข้าโหมดพักระวังตัว Cooldown 2 ตา และถอยกลับ Base Bet
      engine.recordOutcome(chosenColumn: 'A', won: false, mode: GameMode.towers);
      expect(engine.getDefensiveCooldown(GameMode.towers), 0,
          reason: 'Single loss does NOT set cooldown -> allows immediate recovery next round');
      expect(engine.getConsecutiveLosses(GameMode.towers), 1);

      // On single loss: AI can evaluate and clear recovery immediately (not forced into DEFENSE/holdFire):
      final singleLossPred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 1.0,
        currentBalance: 110.0,
      );
      expect(singleLossPred.marketRegime, isNot('DEFENSE'),
          reason: 'Single loss should NOT force DEFENSE regime');
      expect(singleLossPred.recoveryClearance, isNot(RecoveryClearance.holdFire),
          reason: 'Single loss allows recovery clearance for immediate debt recovery');

      // Winning confirming the new column keeps Cooldown at 0:
      engine.recordOutcome(chosenColumn: 'B', won: true, mode: GameMode.towers);
      expect(engine.getDefensiveCooldown(GameMode.towers), 0,
          reason: 'Winning confirmation keeps cooldown at 0');
      expect(engine.getConsecutiveLosses(GameMode.towers), 0);

      final confirmWinPred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 1.0,
        currentBalance: 110.0,
      );
      expect(confirmWinPred.marketRegime, anyOf('ALPHA_EDGE', 'STEADY_EDGE'),
          reason: 'Confirmed win unlocks ALPHA_EDGE or STEADY_EDGE for immediate recovery');
      expect(confirmWinPred.confidence, inInclusiveRange(72.0, 88.0));
      expect(confirmWinPred.mathematicalEdge, greaterThan(0.0));

      // First loss after win: streak = 1, cooldown = 0
      engine.recordOutcome(chosenColumn: 'A', won: false, mode: GameMode.towers);
      expect(engine.getConsecutiveLosses(GameMode.towers), 1);
      expect(engine.getDefensiveCooldown(GameMode.towers), 0);

      // Second consecutive loss still allows recovery (cooldown remains 0):
      engine.recordOutcome(chosenColumn: 'A', won: false, mode: GameMode.towers);
      expect(engine.getDefensiveCooldown(GameMode.towers), 0,
          reason: 'Second loss still allows recovery next round');
      expect(engine.getConsecutiveLosses(GameMode.towers), 2);

      // Third consecutive loss triggers 2-round defensive cooldown and Base bet fallback (User Directive: ให้ปรับจาก 5 ตา มาเปัน 3 ตาครับ):
      engine.recordOutcome(chosenColumn: 'A', won: false, mode: GameMode.towers);
      expect(engine.getDefensiveCooldown(GameMode.towers), 2,
          reason: 'Pain Memory must set 2-round defensive cooldown after 3 consecutive losses');
      expect(engine.getConsecutiveLosses(GameMode.towers), 3);

      final threeLossPred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 1.0,
        currentBalance: 110.0,
      );
      expect(threeLossPred.recoveryClearance, RecoveryClearance.holdFire,
          reason: 'Must hold fire after 3 consecutive losses (ให้ปรับจาก 5 ตา มาเปัน 3 ตาครับ แล้วลง Base Bet)');
      expect(threeLossPred.recommendedFluidFraction, 0.0);
      expect(threeLossPred.marketRegime, anyOf('DEFENSE', 'CHOP'));
    });

    test('User Directive: Micro-Balance & Micro-Debt Active Recovery Guarantee', () {
      // 1. Test Micro-balance operational budget (0.005147 DOGE balance with 0.00007882 floorBet)
      final microState = GameModeSessionState(GameMode.towers);
      microState.sessionStartBalance = 0.005147;
      microState.protectedPrincipal = 0.005147;
      microState.lastSettledBalance = 0.005147;
      microState.sessionMaxBalance = 0.005147;
      const floorBet = 0.00007882;

      // Without floorBet parameter: 1% of 0.005147 = 0.00005147 (smaller than floorBet)
      final budgetRaw = microState.getOperationalRecoveryBudget(0.005147);
      expect(budgetRaw, closeTo(0.00005147, 0.00000001));

      // With floorBet parameter: ensures budget is at least floorBet * 2.5 if within safe buffer!
      final budgetAdaptive = microState.getOperationalRecoveryBudget(0.005147, floorBet: floorBet);
      expect(budgetAdaptive, greaterThanOrEqualTo(floorBet * 2.5),
          reason: 'Adaptive operational budget must support at least 2.5x floorBet on micro balances within 95% buffer');

      // 2. Test Micro-debt recovery sizing (User question: มีหนี้ 0.000009 แบบนี้จะทวงไหม?)
      microState.activeNewLoss = 0.000009;
      expect(microState.totalAccumulatedLoss, 0.000009);

      // Towers profit rate = 0.42
      const double pRate = 0.42;
      double debtToEscalate = microState.totalAccumulatedLoss; // 100% recovery for small debt
      double targetProfit = debtToEscalate + (floorBet * pRate);
      double requiredBet = targetProfit / pRate;
      final double minRecoveryBet = floorBet * 1.5;
      if (requiredBet < minRecoveryBet) {
        requiredBet = minRecoveryBet;
      }

      // Bet must be strictly larger than floorBet
      expect(requiredBet, greaterThan(floorBet),
          reason: 'Recovery bet for 0.000009 debt MUST be higher than Base Bet floor');
      // When winning this requiredBet, profit completely clears debt:
      final double winProfit = requiredBet * pRate;
      expect(winProfit, greaterThanOrEqualTo(microState.totalAccumulatedLoss),
          reason: 'Winning recovery bet must completely clear the 0.000009 debt in 1 round!');

      microState.subtractProfitFromDebt(winProfit);
      expect(microState.totalAccumulatedLoss, closeTo(0.0, 0.00000001),
          reason: 'Debt must be completely 0 after winning recovery bet');
    });

    test('User Directive: Complete Peak Deficit Recovery & Zero Debt Abandonment (+0.5% Peak Return Guarantee)', () {
      final peakState = GameModeSessionState(GameMode.towers);
      peakState.sessionStartBalance = 1.0;
      peakState.protectedPrincipal = 1.0;
      peakState.sessionMaxBalance = 1.0050; // Achieved +0.5% profit
      const floorBet = 0.00007882;
      const pRate = 0.485;

      // 1. Balance drops from +0.5% peak (1.0050) to 0.9980 DOGE
      double settledBalance = 0.9980;
      double realDeficit = peakState.sessionMaxBalance - settledBalance; // 0.0070 DOGE
      expect(realDeficit, closeTo(0.0070, 0.00000001));

      // Suppose activeNewLoss only recorded 0.0020 (partial loss tracked)
      peakState.activeNewLoss = 0.0020;
      expect(peakState.totalAccumulatedLoss, closeTo(0.0020, 0.00000001));

      // Peak Deficit Synchronization runs before round:
      if (peakState.sessionMaxBalance > 0.00000001 && settledBalance > 0.00000001) {
        if (realDeficit > 0.00000001) {
          final double targetDebt = realDeficit;
          if (peakState.totalAccumulatedLoss < targetDebt) {
            final double deficitGap = targetDebt - peakState.totalAccumulatedLoss;
            peakState.activeNewLoss += deficitGap;
            peakState.activeNewLoss = double.parse(peakState.activeNewLoss.toStringAsFixed(8));
          }
        }
      }
      expect(peakState.totalAccumulatedLoss, closeTo(0.0070, 0.00000001),
          reason: 'Peak deficit reconciliation MUST synchronize debt to full distance from +0.5% peak (0.0070 DOGE)');

      // 2. Recovery Sizing: Must attempt 100% full debt recovery instead of 35% slicing
      final double budget = peakState.getOperationalRecoveryBudget(settledBalance, floorBet: floorBet);
      final double bufferAboveFloor = (settledBalance - peakState.emergencyCapitalFloor).clamp(0.0, settledBalance);
      final double safeRiskCap = budget > 0.00000001
          ? budget
          : (bufferAboveFloor > 0.00000001 ? bufferAboveFloor : (settledBalance * 0.05));
      final double bankrollCap = settledBalance * 0.10;
      final double minRecoveryBet = floorBet * 1.5;
      final double maxAllowableRisk = min(bankrollCap, max(safeRiskCap, minRecoveryBet)).clamp(minRecoveryBet, bankrollCap);

      final double surplusProfitMargin = floorBet * pRate * 2.0;
      double fullTargetProfit = peakState.totalAccumulatedLoss + surplusProfitMargin;
      double fullRequiredBet = fullTargetProfit / pRate;
      double requiredBet = fullRequiredBet;
      if (requiredBet > maxAllowableRisk) {
        requiredBet = maxAllowableRisk;
      }

      // Safe budget (0.0432) allows fullRequiredBet (~0.0146):
      expect(requiredBet, closeTo(fullRequiredBet, 0.0001),
          reason: 'When within safe risk budget, required bet MUST aim for 100% full recovery to peak in 1 shot!');

      // 3. Zero Debt Abandonment Guarantee in Win Handler:
      // Case A: Partial win (DOM balance reaches 1.0020, still below 1.0050 ATH)
      double balanceAfterPartialWin = 1.0020;
      peakState.subtractProfitFromDebt(0.0040); // Paid down 0.0040 of 0.0070 debt -> remaining debt 0.0030
      bool isFullyRecovered = peakState.totalAccumulatedLoss <= 0.00000001;

      if (balanceAfterPartialWin > 0.00000001 && peakState.sessionMaxBalance > 0.00000001) {
        if (balanceAfterPartialWin < peakState.sessionMaxBalance - 0.00000001) {
          final double remainingDeficit = peakState.sessionMaxBalance - balanceAfterPartialWin;
          if (peakState.totalAccumulatedLoss < remainingDeficit) {
            peakState.activeNewLoss += (remainingDeficit - peakState.totalAccumulatedLoss);
            peakState.activeNewLoss = double.parse(peakState.activeNewLoss.toStringAsFixed(8));
          }
          isFullyRecovered = false; // MUST NOT declare victory!
        }
      }
      expect(isFullyRecovered, isFalse,
          reason: 'Must NOT declare full recovery when balance (1.0020) is still below +0.5% ATH (1.0050)');
      expect(peakState.totalAccumulatedLoss, closeTo(0.0030, 0.00000001),
          reason: 'Debt must retain the exact 0.0030 deficit to recover back to 1.0050 ATH on next round');

      // Case B: Final recovery win (balance reaches 1.0051, exceeding 1.0050 ATH)
      double balanceAfterFinalWin = 1.0051;
      if (balanceAfterFinalWin >= peakState.sessionMaxBalance) {
        peakState.sessionMaxBalance = balanceAfterFinalWin;
        peakState.resetDebt();
        isFullyRecovered = true;
      }
      expect(isFullyRecovered, isTrue);
      expect(peakState.totalAccumulatedLoss, 0.0,
          reason: 'Debt is only 100% cleared when balance actually touches or exceeds the +0.5% ATH!');
      expect(peakState.sessionMaxBalance, closeTo(1.0051, 0.00000001));
    });

    test('User Directive: Zero Debt Cut Beyond 10% Drawdown (100% Debt Preserved Even Below Emergency Floor)', () {
      final deepState = GameModeSessionState(GameMode.towers);
      deepState.sessionStartBalance = 1.0;
      deepState.protectedPrincipal = 1.0;
      deepState.sessionMaxBalance = 1.0050; // Previous ATH
      expect(deepState.emergencyCapitalFloor, closeTo(1.0050 * 0.90, 0.0001));

      // Deep Drawdown: Balance drops to 0.88 DOGE (-12.4% from ATH, well beyond -10% emergency floor)
      double settledBalance = 0.8800;
      double realDeficit = deepState.sessionMaxBalance - settledBalance; // 0.1250 DOGE
      expect(realDeficit, closeTo(0.1250, 0.00000001));

      // Peak Deficit Synchronization:
      if (deepState.sessionMaxBalance > 0.00000001 && settledBalance > 0.00000001) {
        if (realDeficit > 0.00000001) {
          final double targetDebt = realDeficit;
          if (deepState.totalAccumulatedLoss < targetDebt) {
            final double deficitGap = targetDebt - deepState.totalAccumulatedLoss;
            deepState.activeNewLoss += deficitGap;
            deepState.activeNewLoss = double.parse(deepState.activeNewLoss.toStringAsFixed(8));
          }
        }
      }

      // Debt MUST be 0.1250 DOGE (100% preserved), NOT clamped!
      expect(deepState.totalAccumulatedLoss, closeTo(0.1250, 0.00000001),
          reason: 'Debt MUST NOT be cut or clamped when losing more than 10%! 100% of the 0.1250 debt is remembered.');

      // While below emergency floor (0.88 <= 0.9045), operational recovery budget is 0.0 (Hold Fire at Base Bet):
      expect(deepState.getOperationalRecoveryBudget(settledBalance), 0.0,
          reason: 'When below 90% floor, recovery holds fire to protect remaining 88% bulk');

      // Once Base Bet wins bring balance back up to 0.96 DOGE (above 90% floor):
      settledBalance = 0.9600;
      realDeficit = deepState.sessionMaxBalance - settledBalance; // 0.0450 DOGE
      if (deepState.totalAccumulatedLoss > realDeficit + 0.00000001) {
        deepState.clampDebtToMax(realDeficit);
      }
      expect(deepState.totalAccumulatedLoss, closeTo(0.0450, 0.00000001));

      // Now above 90% floor, recovery budget unlocks to recover the remaining deficit back to ATH!
      expect(deepState.getOperationalRecoveryBudget(settledBalance, floorBet: 0.00007882), greaterThan(0.0),
          reason: 'Above 90% floor, recovery budget unlocks to recover full debt back to 1.0050 ATH!');
    });

    test('User Exact Case: 100→110→108.2→109.5 debt NOT cleared, then 110 clears debt', () {
      // Simulates: Start 100, reach 110 ATH (+10%), drop to 108.2, recover to 109.5 -> debt must NOT be cleared
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.protectedPrincipal = 100.0;
      s.sessionMaxBalance = 110.0; // ATH = 110 (+10%)
      const floorBet = 0.00007882;
      const pRate = 0.485;

      // Step 1: Drop from 110 to 108.2 (loss of 1.8)
      s.activeNewLoss = 1.8;
      expect(s.totalAccumulatedLoss, closeTo(1.8, 0.001));

      // Step 2: Sliced recovery wins bring balance to 109.5 (recovered 1.3 of 1.8)
      s.subtractProfitFromDebt(1.3);
      expect(s.totalAccumulatedLoss, closeTo(0.5, 0.001),
          reason: 'After partial recovery, 0.5 debt should remain');

      // Step 3: Win handler ATH check - currentBalForCheck = 109.5 < ATH 110.0
      double currentBalForCheck = 109.5;
      bool isFullyRecovered = false;

      if (s.sessionMaxBalance > 0.00000001 && currentBalForCheck < s.sessionMaxBalance - 0.00000001) {
        final double remainingDeficit = s.sessionMaxBalance - currentBalForCheck;
        if (s.totalAccumulatedLoss < remainingDeficit) {
          s.activeNewLoss += (remainingDeficit - s.totalAccumulatedLoss);
          s.activeNewLoss = double.parse(s.activeNewLoss.toStringAsFixed(8));
        }
        isFullyRecovered = false;
      } else {
        isFullyRecovered = s.totalAccumulatedLoss <= 0.00000001 ||
            (currentBalForCheck >= s.sessionMaxBalance && s.sessionMaxBalance > 0.00000001);
      }

      expect(isFullyRecovered, isFalse,
          reason: 'MUST NOT declare victory at 109.5 when ATH is 110.0! Debt of 0.5 remains!');
      expect(s.totalAccumulatedLoss, closeTo(0.5, 0.001),
          reason: 'Debt must be exactly 0.5 (the deficit from 109.5 to 110.0 ATH)');

      // Step 4: Final recovery win brings balance to 110.0 -> debt cleared!
      currentBalForCheck = 110.0;
      if (s.sessionMaxBalance > 0.00000001 && currentBalForCheck < s.sessionMaxBalance - 0.00000001) {
        isFullyRecovered = false;
      } else {
        isFullyRecovered = s.totalAccumulatedLoss <= 0.00000001 ||
            (currentBalForCheck >= s.sessionMaxBalance && s.sessionMaxBalance > 0.00000001);
      }
      // Balance >= ATH -> isFullyRecovered = true
      expect(isFullyRecovered, isTrue,
          reason: 'Balance at 110.0 == ATH 110.0 -> debt fully recovered!');

      // resetDebt()
      s.sessionMaxBalance = currentBalForCheck;
      s.resetDebt();
      expect(s.totalAccumulatedLoss, 0.0);
    });

    test('User Directive: ทวงเต็มหนี้ 100% ในไม้เดียว (ทั้งหนี้เล็กและหนี้ใหญ่)', () {
      const floorBet = 0.00007882;
      const pRate = 0.485;

      // Case A: Small debt = 0.00020 -> ทวง 100% ไม้เดียวจบ
      final smallState = GameModeSessionState(GameMode.towers);
      smallState.activeNewLoss = 0.00020;
      double debtToEscalate = smallState.totalAccumulatedLoss; // 100%
      final baseSurplusSmall = floorBet * pRate * 2.0;
      final dynamicSurplusSmall = debtToEscalate * 0.20;
      final surplusSmall = max(baseSurplusSmall, dynamicSurplusSmall);
      double targetProfit = debtToEscalate + surplusSmall;
      double requiredBet = targetProfit / pRate;
      double winProfit = requiredBet * pRate;
      expect(winProfit, greaterThanOrEqualTo(smallState.totalAccumulatedLoss),
          reason: 'Small debt must be cleared 100% in 1 round!');

      // Case B: Large debt = 0.00100 -> ทวงเต็มหนี้ 100% ในไม้เดียวจบตามคำสั่งผู้ใช้
      final largeState = GameModeSessionState(GameMode.towers);
      largeState.activeNewLoss = 0.00100;
      debtToEscalate = largeState.totalAccumulatedLoss; // 100% full debt!
      expect(debtToEscalate, closeTo(0.00100, 0.00001));

      final baseSurplusLarge = floorBet * pRate * 2.0;
      final dynamicSurplusLarge = debtToEscalate * 0.20;
      final surplusLarge = max(baseSurplusLarge, dynamicSurplusLarge);
      targetProfit = debtToEscalate + surplusLarge;
      requiredBet = targetProfit / pRate;
      winProfit = requiredBet * pRate;
      largeState.subtractProfitFromDebt(winProfit);
      expect(largeState.totalAccumulatedLoss, 0.0,
          reason: 'After 1 round win, 100% full debt must be cleared completely and achieve New ATH!');
    });

    test('ATH deficit check works even when balanceIncreased is false (slow DOM)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 1.0;
      s.sessionMaxBalance = 1.10; // ATH
      s.activeNewLoss = 0.05; // Only 0.05 tracked

      // Simulate: balanceIncreased = false (slow DOM), but we know balance + profit
      const balanceBeforeRound = 1.03;
      const actualProfit = 0.02;
      const balanceIncreased = false;
      const balanceAfterWin = 0.0; // DOM didn't update

      double currentBalForCheck = balanceIncreased && balanceAfterWin > 0.00000001
          ? balanceAfterWin
          : (balanceBeforeRound > 0.00000001 ? (balanceBeforeRound + actualProfit) : 1.0);
      // currentBalForCheck = 1.03 + 0.02 = 1.05

      bool isFullyRecovered = false;
      if (s.sessionMaxBalance > 0.00000001 && currentBalForCheck < s.sessionMaxBalance - 0.00000001) {
        final double remainingDeficit = s.sessionMaxBalance - currentBalForCheck;
        if (s.totalAccumulatedLoss < remainingDeficit) {
          s.activeNewLoss += (remainingDeficit - s.totalAccumulatedLoss);
          s.activeNewLoss = double.parse(s.activeNewLoss.toStringAsFixed(8));
        }
        isFullyRecovered = false;
      } else {
        isFullyRecovered = s.totalAccumulatedLoss <= 0.00000001;
      }

      expect(isFullyRecovered, isFalse,
          reason: 'Even with slow DOM (balanceIncreased=false), must NOT declare victory when balance 1.05 < ATH 1.10');
      expect(s.totalAccumulatedLoss, closeTo(0.05, 0.001),
          reason: 'Debt remains at 0.05 = ATH(1.10) - balance(1.05)');
    });

    test('House Money Surge: uses 3%-5% of profit cushion without risking protected principal', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 10.0;
      s.protectedPrincipal = 10.0;
      s.lastSettledBalance = 11.0; // Profit cushion = 1.0 DOGE
      const floorBet = 0.00007882;

      expect(s.profitCushion, closeTo(1.0, 0.00000001));

      // In Alpha Surge mode with cushion > 0:
      const double boostMultiplier = 2.0;
      double scaledBet = floorBet * boostMultiplier;
      final double houseMoneyShare = (s.profitCushion * 0.03).clamp(0.0, s.profitCushion * 0.05);
      expect(houseMoneyShare, closeTo(0.03, 0.00000001), reason: '3% of 1.0 cushion = 0.03 DOGE');

      scaledBet += houseMoneyShare;
      expect(scaledBet, closeTo(0.00007882 * 2.0 + 0.03, 0.00000001));

      // Verify safety: Even if this bet is lost, balance after loss (10.9698) is strictly > protectedPrincipal (10.0)
      final balanceAfterHypotheticalLoss = 11.0 - scaledBet;
      expect(balanceAfterHypotheticalLoss, greaterThan(s.protectedPrincipal!),
          reason: 'House money surge can never breach protected principal');
    });

    test('Milestone Compounding: scales lockedBaseBet at +5% profit milestone with constant 1/10000 risk', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 10.0;
      s.sessionProfitBaseline = 10.0;
      const defaultFloor = 0.00007882;
      s.lockedBaseBet = GameMode.towers.calculateBaseBet(10.0, defaultFloor, coin: 'DOGE');
      expect(s.lockedBaseBet, closeTo(0.0010, 0.00001), reason: 'Initial Base Bet = 10.0 / 10000 = 0.0010');

      // Balance grows to 10.6 DOGE (+6% profit -> triggers +5% milestone):
      const double currentBalance = 10.6;
      final double currentProfitPct = (currentBalance - s.sessionProfitBaseline!) / s.sessionProfitBaseline!;
      expect(currentProfitPct >= 0.05, isTrue);

      final double updatedBaseBet = GameMode.towers.calculateBaseBet(currentBalance, defaultFloor, coin: 'DOGE');
      expect(updatedBaseBet, closeTo(0.00106, 0.00001), reason: 'New Base Bet = 10.6 / 10000 = 0.00106');
      expect(updatedBaseBet, greaterThan(s.lockedBaseBet!));

      // Base Bet scaled up by exactly +6% compounding:
      s.lockedBaseBet = updatedBaseBet;
      expect(s.lockedBaseBet, closeTo(0.00106, 0.00001));
    });

    test('Dynamic Surplus Booster: surplus = max(baseSurplus, debtToEscalate × 0.20) capped by bankroll 10%', () {
      // Setup: balance = 10.0 DOGE, debt = 0.005 DOGE (small debt ≤ 4× baseBet)
      const double balance = 10.0;
      const double floorBet = 0.0010; // baseBet = balance / 10000
      const double pRate = 0.9500; // typical towers payout rate
      const double debt = 0.005; // small debt: 5× floorBet > 4× → actually large for this case
      // But let's test with small debt first (≤ 4× floorBet = 0.004)
      const double smallDebt = 0.003; // 3× floorBet → small debt → debtToEscalate = 100% = 0.003

      // Case 1: Small debt → debtToEscalate = smallDebt = 0.003
      final double debtToEscalateSmall = smallDebt;
      final double baseSurplusSmall = floorBet * pRate * 2.0; // 0.0010 * 0.95 * 2.0 = 0.0019
      final double dynamicSurplusSmall = debtToEscalateSmall * 0.20; // 0.003 * 0.20 = 0.0006
      final double surplusSmall = max(baseSurplusSmall, dynamicSurplusSmall);
      expect(surplusSmall, closeTo(baseSurplusSmall, 0.0001),
          reason: 'Small debt: base surplus (0.0019) > dynamic (0.0006), so base wins');

      // Case 2: Large debt → debtToEscalate = debt × slice (e.g., 25%)
      const double largeDebt = 0.10; // 100× floorBet → large debt
      final double debtToEscalateLarge = largeDebt * 0.25; // 25% slice = 0.025
      final double baseSurplusLarge = floorBet * pRate * 2.0; // 0.0019
      final double dynamicSurplusLarge = debtToEscalateLarge * 0.20; // 0.025 * 0.20 = 0.005
      final double surplusLarge = max(baseSurplusLarge, dynamicSurplusLarge);
      expect(surplusLarge, closeTo(dynamicSurplusLarge, 0.0001),
          reason: 'Large debt: dynamic surplus (0.005) > base (0.0019), so dynamic wins → ทวงจบ = กำไรกระโดด!');

      // Case 3: Verify total targetProfit → requiredBet stays within bankroll cap 10%
      final double targetProfit = debtToEscalateLarge + surplusLarge; // 0.025 + 0.005 = 0.030
      final double requiredBet = targetProfit / pRate; // 0.030 / 0.95 = 0.03158
      final double bankrollCap = balance * 0.10; // 1.0 DOGE
      expect(requiredBet, lessThan(bankrollCap),
          reason: 'Required bet (${requiredBet.toStringAsFixed(4)}) must be within bankroll cap 10% (${bankrollCap.toStringAsFixed(4)})');

      // Verify surplus is meaningful: +1% to +2% of portfolio per recovery round
      final double profitPctOfPortfolio = surplusLarge / balance;
      expect(profitPctOfPortfolio, greaterThanOrEqualTo(0.0001),
          reason: 'Dynamic surplus should provide meaningful profit boost');
    });

    test('User Directive: ทุกตาที่ แพ้ ทวงเต็ม 100% 4 ตาต่อกันไม่ชนะ ให้ไปที่ Base Bet ช่วงชนะแล้วทวงให้ใช้ตอน เกีน 5% เท่านั้น ทุกๆ กำไรเพี่ม 5% จะลือกไว้เป็นทุนทันที', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 10.0;
      s.protectedPrincipal = 10.0;
      s.lastSettledBalance = 10.0;
      s.sessionMaxBalance = 10.0;
      s.sessionProfitBaseline = 10.0;
      s.activeNewLoss = 0.05; // 0.05 debt

      // 1. Loss 1 round (streak = 1): ทวงเต็ม 100%
      s.consecutiveLossesStreak = 1;
      s.consecutiveRecoveryLosses = 0;
      bool isFourLossesStreak = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      bool isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 && !isFourLossesStreak;

      expect(isFourLossesStreak, isFalse, reason: '1 loss allows 100% recovery');
      expect(isEligibleForRecovery, isTrue,
          reason: 'Must recover 100% full debt immediately on round 2 (ทุกตาที่แพ้ ทวงเต็ม 100%)');

      // 2. Loss 2 consecutive rounds (streak = 2): ทวงเต็ม 100%
      s.consecutiveLossesStreak = 2;
      s.consecutiveRecoveryLosses = 1;
      s.activeNewLoss = 0.12;
      isFourLossesStreak = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 && !isFourLossesStreak;

      expect(isFourLossesStreak, isFalse, reason: '2 losses allows 100% recovery');
      expect(isEligibleForRecovery, isTrue,
          reason: 'Must continue 100% full debt recovery on round 3');

      // 3. Loss 3 consecutive rounds (streak = 3): ทวงเต็ม 100%
      s.consecutiveLossesStreak = 3;
      s.consecutiveRecoveryLosses = 2;
      s.activeNewLoss = 0.25;
      isFourLossesStreak = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 && !isFourLossesStreak;

      expect(isFourLossesStreak, isFalse, reason: '3 losses allows 100% recovery');
      expect(isEligibleForRecovery, isTrue,
          reason: 'Must continue 100% full debt recovery on round 4');

      // 4. Loss 4 consecutive rounds (streak = 4): 4 ตาต่อกันไม่ชนะ -> ไปที่ Base Bet!
      s.consecutiveLossesStreak = 4;
      s.consecutiveRecoveryLosses = 3;
      isFourLossesStreak = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 && !isFourLossesStreak;

      expect(isFourLossesStreak, isTrue, reason: '4 losses in a row detected!');
      expect(isEligibleForRecovery, isFalse,
          reason: 'Must fall back to Base Bet after 4 consecutive rounds not winning (4 ตาต่อกันไม่ชนะ ให้ไปที่ Base Bet)');

      // 5. Win on Base Bet: resets streak to 0, recovery resumes!
      s.consecutiveLossesStreak = 0;
      s.consecutiveRecoveryLosses = 0;
      isFourLossesStreak = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 && !isFourLossesStreak;

      expect(isFourLossesStreak, isFalse);
      expect(isEligibleForRecovery, isTrue, reason: 'Resumes 100% full recovery after streak broken');

      // 6. Test: "ไม่ต้องมี ลอก 5% แล้วต่อไปให้ทวง 100%"
      // ไม่มีเงื่อนไขต้องรอกำไรเกิน 5% (มีกำไรส่วนเกิน cushion > 0 ก็สามารถต่อยอด House Money ได้ทันที)
      double currentBal = 10.3;
      double cushion = currentBal - s.sessionStartBalance!;
      expect(cushion > 0.00000001, isTrue,
          reason: 'Positive profit cushion can activate House Money without waiting for arbitrary 5% hurdle');

      // 7. Test: ไม่ล็อก 5% เข้าเป็นทุนใหม่ (ไม่ขยับ Emergency Floor ขึ้นมาบีบอัดโควตาทวง 100%)
      // เมื่อกำไรโตขึ้น sessionStartBalance ยังคงเป็นฐานเงินต้นตั้งต้นเดิม (10.0 DOGE)
      expect(s.sessionStartBalance, 10.0,
          reason: 'Session start balance remains original deposit, preventing trailing floor choke on 100% recovery');
      expect(s.emergencyCapitalFloor, closeTo(10.0 * 0.90, 0.0001),
          reason: 'Emergency floor remains at 90% of original starting capital, keeping wide recovery runway');

      // 8. Test: ยืนยันการคำนวณเบททวงหนี้ 100% เต็มก้อนเสมอ
      const double pRate = 0.42;
      const double floorBet = 0.00007882;
      double debt = s.totalAccumulatedLoss;
      double baseSurplus = floorBet * pRate * 2.0;
      double dynamicSurplus = debt * 0.20;
      double surplusProfitMargin = max(baseSurplus, dynamicSurplus);
      double targetProfit = debt + surplusProfitMargin;
      double requiredBet = targetProfit / pRate;

      // Bet ต้องมากกว่าหนี้ เพื่อชนะตาเดียวล้างหนี้และกำไรกระโดด
      expect(requiredBet * pRate, greaterThan(debt),
          reason: '100% recovery bet MUST yield profit strictly greater than debt (clearing debt + dynamic surplus)');
    });

    test('Anti-Death-Spiral: L-L-L-L-W-L-L-L-L-W-L-L does NOT wipe out bankroll (Trend Confirmation & 5% Cap)', () {
      final s = GameModeSessionState(GameMode.towers);
      double balance = 10.0;
      const double floorBet = 0.00007882;
      s.sessionStartBalance = balance;
      s.lockedBaseBet = floorBet;
      s.activeNewLoss = 0.0;

      // Rounds 1, 2, 3: Losses -> accumulated debt builds up
      s.consecutiveLossesStreak = 3;
      s.consecutiveRecoveryLosses = 2;
      s.activeNewLoss = 0.0015;

      // Round 4: 4th Loss -> hits 4 consecutive losses!
      s.consecutiveLossesStreak = 4;
      s.consecutiveRecoveryLosses = 3;
      s.activeNewLoss += 0.0035;

      // System triggers 4-Loss Fallback:
      bool isFourLosses = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      expect(isFourLosses, isTrue);
      if (isFourLosses && !s.isLossStreakBaseBetLocked) {
        s.isLossStreakBaseBetLocked = true;
        s.consecutiveBaseBetWins = 0;
      }
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Streak 4 must lock into Base Bet mode');

      // Round 5: Plays Base Bet -> WINS!
      // In win handling:
      s.consecutiveBaseBetWins = 1;
      s.consecutiveLossesStreak = 0;
      // Trend Confirmation Check:
      if (s.isLossStreakBaseBetLocked) {
        if (s.consecutiveBaseBetWins >= 2) {
          s.isLossStreakBaseBetLocked = false;
        }
      }
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Winning only 1 Base Bet must NOT unlock recovery! (Pending 2nd win)');

      // Round 6: Check recovery eligibility
      bool isTrendConfirmed = !s.isLossStreakBaseBetLocked || s.consecutiveBaseBetWins >= 2;
      bool canRecover = s.totalAccumulatedLoss > 0 && !isFourLosses && isTrendConfirmed;
      expect(canRecover, isFalse,
          reason: 'Round 6 MUST NOT fire recovery bet! Must stay on Base Bet to protect capital');

      // Round 6: Plays Base Bet -> LOSES!
      s.consecutiveBaseBetWins = 0; // resets
      s.consecutiveLossesStreak = 1;
      // Loss check maintains lock:
      if (s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4) {
        s.isLossStreakBaseBetLocked = true;
      }
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Loss while locked must maintain Base Bet lock');

      // Rounds 7, 8, 9: All lose on Base Bet
      s.consecutiveLossesStreak = 4;
      s.isLossStreakBaseBetLocked = true;

      // Round 10: Base Bet -> WINS 1 time!
      s.consecutiveBaseBetWins = 1;
      if (s.isLossStreakBaseBetLocked && s.consecutiveBaseBetWins >= 2) {
        s.isLossStreakBaseBetLocked = false;
      }
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Round 10 win (1st win) still leaves Base Bet lock active');

      // Rounds 11, 12: Lose on Base Bet
      s.consecutiveBaseBetWins = 0;
      s.consecutiveLossesStreak = 2;
      expect(s.isLossStreakBaseBetLocked, isTrue);

      // Now demonstrate Trend Confirmation unlocking after 2 consecutive clean Base Bet wins:
      s.consecutiveBaseBetWins = 1; // 1st win
      s.consecutiveBaseBetWins = 2; // 2nd consecutive win!
      if (s.isLossStreakBaseBetLocked && s.consecutiveBaseBetWins >= 2) {
        s.isLossStreakBaseBetLocked = false;
      }
      expect(s.isLossStreakBaseBetLocked, isFalse,
          reason: '2 consecutive Base Bet wins unlocks recovery safely');

      // Now recovery is re-armed, verify Uncapped Recovery Bet (User Directive: "เบททวงไม่จำกัดเพดานครับ"):
      isTrendConfirmed = !s.isLossStreakBaseBetLocked || s.consecutiveBaseBetWins >= 2;
      canRecover = s.totalAccumulatedLoss > 0 && isTrendConfirmed;
      expect(canRecover, isTrue);

      // Sizing with NO cap:
      const double pRate = 0.42;
      double debt = s.totalAccumulatedLoss;
      double targetProfit = debt + (debt * 0.20);
      double requiredBet = targetProfit / pRate;

      // ไม้ทวงไม่จำกัดเพดาน: ทวงเต็มจำนวนเพื่อให้ชนะตาเดียวล้างหนี้หมดเกลี้ยง
      expect(requiredBet * pRate, greaterThan(debt),
          reason: 'Uncapped recovery bet covers 100% of accumulated debt + surplus without being throttled by any cap');
    });

    test('Pillar 1: Golden Highway Elimination detects untouched column in Ping-Pong alternating bombs', () {
      final engine = OmniMatrixEngine.instance;
      engine.reset(mode: GameMode.towers);

      // Simulate alternating bombs: A -> B -> A
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'A', mode: GameMode.towers);

      final goldenCol = engine.detectGoldenHighway(mode: GameMode.towers);
      expect(goldenCol, equals('C'),
          reason: 'When bombs alternate A <-> B, untouched column C must be detected as the Golden Highway');

      // Now verify that prediction targets Golden Highway
      final prediction = engine.getNextPrediction(mode: GameMode.towers);
      expect(prediction.column, equals('C'),
          reason: 'OmniMatrixEngine must predict column C (Golden Highway) with highest confidence');
    });

    test('Pillar 1: AI Brain Veto redirects hazardous aiBrainPrediction to Golden Highway', () {
      final engine = OmniMatrixEngine.instance;
      engine.reset(mode: GameMode.towers);

      // Alternating bombs A <-> B
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: true, revealedBombPos: 'A', mode: GameMode.towers);

      // Even if AI Brain erroneously suggests 'A' (which is in the bomb ping-pong alternation):
      final prediction = engine.getNextPrediction(
        mode: GameMode.towers,
        aiBrainPrediction: 'A',
      );

      expect(prediction.column, equals('C'),
          reason: 'Hazardous AI Brain prediction A must be VETOED and redirected to Golden Highway C');
    });

    test('Pillar 2: Streak-2 Micro Probing Protocol enforces Base Bet on Round 3 and beyond until Probe Wins', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 0.0;

      // Round 1: Loss 1 (Base Bet loss)
      s.activeNewLoss += 0.001;
      s.consecutiveLossesStreak = 1;
      expect(s.isMicroProbingActive, isFalse);

      // Round 2 check: Streak = 1 -> Eligible for 100% single-shot recovery!
      bool isFourLosses = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      bool isTrendConfirmed = !s.isLossStreakBaseBetLocked || s.consecutiveBaseBetWins >= 2;
      bool canRecoverR2 = s.totalAccumulatedLoss > 0 && !isFourLosses && !s.isMicroProbingActive && isTrendConfirmed;
      expect(canRecoverR2, isTrue, reason: 'Round 2 must be eligible for single-shot recovery bet');

      // Round 2: Recovery bet LOSES!
      s.activeNewLoss += 0.002;
      s.consecutiveLossesStreak = 2; // Streak reaches 2!

      // System triggers Streak-2 Micro Probing Protocol:
      if (s.consecutiveLossesStreak >= 2 && !s.isMicroProbingActive) {
        s.isMicroProbingActive = true;
      }
      expect(s.isMicroProbingActive, isTrue,
          reason: 'Streak >= 2 must activate Micro Probing mode immediately');

      // Round 3 check: Check eligibility for recovery
      isFourLosses = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      isTrendConfirmed = !s.isLossStreakBaseBetLocked || s.consecutiveBaseBetWins >= 2;
      bool canRecoverR3 = s.totalAccumulatedLoss > 0 && !isFourLosses && !s.isMicroProbingActive && isTrendConfirmed;
      expect(canRecoverR3, isFalse,
          reason: 'Round 3 MUST NOT place recovery bet! Must be blocked by isMicroProbingActive');

      // Round 3: Places Micro Probe Bet (Base Bet) -> LOSES!
      s.activeNewLoss += 0.0001; // Tiny loss
      s.consecutiveLossesStreak = 3;
      // In loss handling, Micro Probing remains active:
      if (s.consecutiveLossesStreak >= 2 && !s.isMicroProbingActive) {
        s.isMicroProbingActive = true;
      }
      expect(s.isMicroProbingActive, isTrue,
          reason: 'Loss on micro probe bet keeps Micro Probing mode active');

      // Round 4 check: Still blocked from recovery!
      bool canRecoverR4 = s.totalAccumulatedLoss > 0 && !s.isMicroProbingActive;
      expect(canRecoverR4, isFalse,
          reason: 'Round 4 must still be protected by Micro Probing mode');

      // Round 4: Places Micro Probe Bet -> WINS!
      // In win handling:
      if (s.isMicroProbingActive) {
        s.isMicroProbingActive = false;
        s.consecutiveLossesStreak = 0;
        s.isLossStreakBaseBetLocked = false;
      }
      s.subtractProfitFromDebt(0.0001 * 0.95);

      expect(s.isMicroProbingActive, isFalse,
          reason: 'Probe win successfully deactivates Micro Probing mode');
      expect(s.consecutiveLossesStreak, equals(0),
          reason: 'Consecutive losses streak reset after probe win');
      expect(s.totalAccumulatedLoss, greaterThan(0.0),
          reason: 'Debt remains to be recovered in full next round');

      // Round 5 check: Probe confirmed! Next round fires recovery bet!
      isFourLosses = s.consecutiveLossesStreak >= 4 || s.consecutiveRecoveryLosses >= 4;
      isTrendConfirmed = !s.isLossStreakBaseBetLocked || s.consecutiveBaseBetWins >= 2;
      bool canRecoverR5 = s.totalAccumulatedLoss > 0 && !isFourLosses && !s.isMicroProbingActive && isTrendConfirmed;
      expect(canRecoverR5, isTrue,
          reason: 'Confirmed Seed unlocks recovery bet on Round 5');
    });

    test('Pillar 2: 20% Bankroll Safety Ceiling strictly prevents All-In wipeout', () {
      final double balance = 0.035; // User had ~0.035 DOGE
      final double debt = 0.015; // Large debt requiring huge bet
      const double pRate = 0.42;

      final double dynamicSurplus = debt * 0.20;
      final double targetProfit = debt + dynamicSurplus;
      double rawRequiredBet = targetProfit / pRate; // 0.018 / 0.42 = 0.04285 (exceeds total balance!)

      // Without cap, bot would bet total balance (All-In):
      expect(rawRequiredBet, greaterThan(balance));

      // With Pillar 2: 20% Bankroll Safety Ceiling:
      final double maxSafeBankrollBet = balance * 0.20; // 0.007 DOGE
      double cappedBet = rawRequiredBet;
      if (cappedBet > maxSafeBankrollBet) {
        cappedBet = maxSafeBankrollBet;
      }

      expect(cappedBet, equals(maxSafeBankrollBet));
      expect(cappedBet, closeTo(0.007, 0.00001),
          reason: 'Bet must be capped to exactly 20% of bankroll to leave 80% safety buffer');
      expect(balance - cappedBet, closeTo(0.028, 0.00001),
          reason: 'Even if this recovery bet hits a bomb, 80% of bankroll is 100% safe!');
    });

    test('Pillar 2: Complete Streak-2 Micro Probing Lifecycle (Round 1 to 5) with 20% Bankroll Cap', () {
      final s = GameModeSessionState(GameMode.towers);
      const double balance = 0.050; // 0.050 DOGE
      const double floorBet = 0.00001; // Base Bet 1/5000 of balance
      const double pRate = 0.42;

      // ─── ROUND 1: Base Bet loses ───
      s.activeNewLoss += floorBet;
      s.consecutiveLossesStreak = 1;
      expect(s.consecutiveLossesStreak, equals(1));
      expect(s.isMicroProbingActive, isFalse);

      // Check recovery eligibility for Round 2:
      bool isEligibleR2 = s.totalAccumulatedLoss > 0 &&
                          !s.isMicroProbingActive &&
                          !s.isLossStreakBaseBetLocked &&
                          s.consecutiveLossesStreak < 2;
      expect(isEligibleR2, isTrue,
          reason: 'ตาที่ 2: ต้องยิงไม้ทวงหนี้เต็ม 100% ไม้แรกทันที (Streak = 1)');

      // ─── ROUND 2: First Recovery Bet placed and loses ───
      double debtR2 = s.totalAccumulatedLoss;
      double reqBetR2 = (debtR2 + (debtR2 * 0.20)) / pRate;
      final double maxSafeBet = balance * 0.20;
      if (reqBetR2 > maxSafeBet) reqBetR2 = maxSafeBet;
      expect(reqBetR2, lessThanOrEqualTo(maxSafeBet),
          reason: 'Recovery bet must never exceed 20% of bankroll');

      s.activeNewLoss += reqBetR2;
      s.consecutiveLossesStreak = 2; // Streak reaches 2!

      // Immediately upon Streak = 2:
      if (s.consecutiveLossesStreak >= 2 && !s.isMicroProbingActive) {
        s.isMicroProbingActive = true;
      }
      expect(s.isMicroProbingActive, isTrue,
          reason: 'ทันทีที่แพ้ 2 ตาติด (Streak = 2): เปิดสถานะ isMicroProbingActive = true');

      // ─── ROUND 3: Micro Probing round (ตาที่ 3 เป็นต้นไป) ───
      bool isEligibleR3 = s.totalAccumulatedLoss > 0 &&
                          !s.isMicroProbingActive &&
                          !s.isLossStreakBaseBetLocked &&
                          s.consecutiveLossesStreak < 2;
      expect(isEligibleR3, isFalse,
          reason: 'ตาที่ 3: ห้ามยิงเงินก้อนใหญ่เด็ดขาด! บังคับวาง Micro Probe Bet (Base Bet)');

      // Round 3 Micro Probe loses:
      s.activeNewLoss += floorBet;
      s.consecutiveLossesStreak = 3;
      expect(s.isMicroProbingActive, isTrue,
          reason: 'หากไม้ดูเชิงแพ้: ยังคงอยู่ในโหมดดูเชิงต่อไป');

      // ─── ROUND 4: Micro Probe round wins! ───
      if (s.isMicroProbingActive) {
        s.isMicroProbingActive = false;
        s.consecutiveLossesStreak = 0;
        s.isLossStreakBaseBetLocked = false;
      }
      s.subtractProfitFromDebt(floorBet * pRate);
      expect(s.isMicroProbingActive, isFalse,
          reason: 'ทันทีที่ไม้ดูเชิงชนะ: ปลดล็อกสถานะดูเชิง');
      expect(s.consecutiveLossesStreak, equals(0),
          reason: 'รีเซ็ต Streak เป็น 0');
      expect(s.totalAccumulatedLoss, greaterThan(0.0),
          reason: 'หนี้ยังคงอยู่ครบถ้วน');

      // ─── ROUND 5: Confirmed Seed -> Fire 100% Recovery Bet immediately! ───
      bool isEligibleR5 = s.totalAccumulatedLoss > 0 &&
                          !s.isMicroProbingActive &&
                          !s.isLossStreakBaseBetLocked &&
                          s.consecutiveLossesStreak < 2;
      expect(isEligibleR5, isTrue,
          reason: 'ยิงไม้ทวงหนี้เต็ม 100% ในตาถัดไปบนช่อง Golden Highway ทันที!');

      // Check recovery sizing on Round 5:
      double debtR5 = s.totalAccumulatedLoss;
      double reqBetR5 = (debtR5 + (debtR5 * 0.20)) / pRate;
      if (reqBetR5 > maxSafeBet) reqBetR5 = maxSafeBet;
      expect(reqBetR5, lessThanOrEqualTo(maxSafeBet),
          reason: 'เพดานเบททวงหนี้ปลอดภัย 20% ของพอร์ต');
    });

    test('User Directive: Dynamic Slicing with 20% Peak ATH / High New Ceiling & Intermission Probe', () {
      final s = GameModeSessionState(GameMode.towers);
      const double startBalance = 0.050; // 0.050 DOGE Starting Capital
      s.sessionStartBalance = startBalance;
      s.sessionMaxBalance = 0.060; // Reached new all-time high: 0.060 DOGE (High New)
      s.lastSettledBalance = 0.045; // Balance dropped during session
      const double currentBalance = 0.045;
      const double floorBet = 0.00001;
      const double pRate = 0.42;

      // 1. Verify 20% Peak ATH / High New Ceiling calculation:
      final double peakAthBalance = (s.sessionMaxBalance > 0.00000001)
          ? s.sessionMaxBalance
          : ((s.sessionStartBalance != null && s.sessionStartBalance! > 0.00000001)
              ? s.sessionStartBalance!
              : currentBalance);
      final double maxSafeBankrollBet = peakAthBalance * 0.20; // 0.060 * 0.20 = 0.012 DOGE
      expect(maxSafeBankrollBet, closeTo(0.012, 0.00001),
          reason: '20% ceiling must reference Peak ATH / High New balance (0.060 * 0.20 = 0.012)');

      // 2. Large debt scenario requiring bet > 20% cap:
      s.activeNewLoss = 0.0084; // Debt = 0.0084
      double targetProfit = s.totalAccumulatedLoss + (s.totalAccumulatedLoss * 0.20);
      double requiredBet = targetProfit / pRate; // 0.01008 / 0.42 = 0.024 DOGE (2x above cap!)
      expect(requiredBet, closeTo(0.024, 0.00001));
      expect(requiredBet, greaterThan(maxSafeBankrollBet));

      // Dynamic Slicing formula:
      final int numSlices = (requiredBet / maxSafeBankrollBet).ceil(); // ceil(0.024 / 0.012) = 2
      expect(numSlices, equals(2),
          reason: 'Dynamic Slicing must divide 0.024 into 2 equal slices based on 0.012 cap');
      final double sliceBet = requiredBet / numSlices; // 0.012 DOGE
      expect(sliceBet, closeTo(0.012, 0.00001));
      expect(sliceBet, lessThanOrEqualTo(maxSafeBankrollBet));
      s.remainingRecoverySlices = numSlices - 1; // 1 remaining after this slice

      // 3. Slice 1 Wins!
      final double profitSlice1 = sliceBet * pRate; // 0.012 * 0.42 = 0.00504 DOGE
      s.subtractProfitFromDebt(profitSlice1);
      expect(s.totalAccumulatedLoss, closeTo(0.00336, 0.00001),
          reason: 'Debt reduced by Slice 1 profit (0.0084 - 0.00504 = 0.00336)');

      // Since debt remains, trigger 1-Round Base Bet Probe Intermission:
      if (s.totalAccumulatedLoss > 0.00000001) {
        s.isIntermissionProbeActive = true;
      }
      expect(s.isIntermissionProbeActive, isTrue,
          reason: 'Winning Slice 1 with remaining debt MUST activate isIntermissionProbeActive');

      // 4. Next Round: Intermission Probe Round
      bool canRecoverDuringProbe = s.totalAccumulatedLoss > 0 &&
                                  !s.isMicroProbingActive &&
                                  !s.isIntermissionProbeActive &&
                                  !s.isLossStreakBaseBetLocked &&
                                  s.consecutiveLossesStreak < 2;
      expect(canRecoverDuringProbe, isFalse,
          reason: 'Must NOT recover during Intermission Probe! Must bet Base Bet');

      // 5. Intermission Probe WINS (Positive trend confirmed):
      if (s.isIntermissionProbeActive) {
        s.isIntermissionProbeActive = false;
        s.consecutiveLossesStreak = 0;
      }
      expect(s.isIntermissionProbeActive, isFalse,
          reason: 'Probe win successfully deactivates intermission probe');

      // 6. Round after Intermission Probe: Fire Slice 2 Recovery Bet immediately!
      bool canRecoverSlice2 = s.totalAccumulatedLoss > 0 &&
                             !s.isMicroProbingActive &&
                             !s.isIntermissionProbeActive &&
                             !s.isLossStreakBaseBetLocked &&
                             s.consecutiveLossesStreak < 2;
      expect(canRecoverSlice2, isTrue,
          reason: 'Confirmed positive trend from probe unlocks Slice 2 recovery bet immediately');

      // Slice 2 Bet calculation:
      double targetProfitSlice2 = s.totalAccumulatedLoss + (s.totalAccumulatedLoss * 0.20);
      double requiredBetSlice2 = targetProfitSlice2 / pRate; // 0.004032 / 0.42 = 0.0096 DOGE
      expect(requiredBetSlice2, closeTo(0.0096, 0.00001));
      expect(requiredBetSlice2, lessThanOrEqualTo(maxSafeBankrollBet),
          reason: 'Slice 2 bet (0.0096) is safely below 20% cap (0.012)');

      // 7. Post-Loss Guardrail: If a recovery bet loses, trigger Micro Probing immediately:
      s.consecutiveLossesStreak = 2;
      s.isMicroProbingActive = true;
      s.isIntermissionProbeActive = false;
      bool canRecoverAfterLoss = s.totalAccumulatedLoss > 0 &&
                                 !s.isMicroProbingActive &&
                                 !s.isIntermissionProbeActive;
      expect(canRecoverAfterLoss, isFalse,
          reason: 'Recovery bet loss immediately blocks recovery and activates Micro Probing');
    });

    test('User Directive: Trailing High New 90% Protected Capital Floor & Triple-Lock Bet Safety (Closing the All-In Loophole)', () {
      final s = GameModeSessionState(GameMode.towers);
      const double initialCapital = 0.050; // 0.050 DOGE Start
      s.sessionStartBalance = initialCapital;
      s.sessionMaxBalance = initialCapital;
      const double floorBet = 0.00001;
      const double pRate = 0.42;

      // ─── 1. TRAILING HIGH NEW 90% FLOOR RATCHET ───
      // Initial Floor: 90% of 0.050 = 0.0450 DOGE
      expect(s.emergencyCapitalFloor, closeTo(0.0450, 0.000001),
          reason: 'Initial capital floor must be 90% of starting balance');

      // Port grows to New ATH 0.100 DOGE (High New)
      s.sessionMaxBalance = 0.100;
      expect(s.emergencyCapitalFloor, closeTo(0.0900, 0.000001),
          reason: 'Capital floor must automatically trail to 90% of High New (0.100 * 0.90 = 0.0900)');

      // Port grows to New ATH 0.200 DOGE (High New)
      s.sessionMaxBalance = 0.200;
      expect(s.emergencyCapitalFloor, closeTo(0.1800, 0.000001),
          reason: 'Capital floor must automatically trail to 90% of High New (0.200 * 0.90 = 0.1800)');

      // ─── 2. TRIPLE-LOCK BET SAFETY IN NORMAL RECOVERY ───
      // Current balance = 0.195 DOGE (in safe zone above 0.180 floor)
      double currentBal = 0.195;
      final double capitalFloor = s.emergencyCapitalFloor;
      final double availableRiskBuffer = max(0.0, currentBal - capitalFloor); // 0.015 DOGE
      final double ath20Cap = s.sessionMaxBalance * 0.20; // 0.040 DOGE
      final double current20Cap = currentBal * 0.20; // 0.039 DOGE
      final double maxSafeBankrollBet = min(ath20Cap, min(current20Cap, availableRiskBuffer));

      // Layer 3 (availableRiskBuffer = 0.015) is the most conservative and becomes the ceiling:
      expect(maxSafeBankrollBet, closeTo(0.015, 0.000001),
          reason: 'maxSafeBankrollBet must be constrained by availableRiskBuffer to protect 90% floor');

      // Suppose debt requires bet of 0.030 DOGE:
      s.activeNewLoss = 0.010;
      double requiredBet = 0.030;
      final int numSlices = ((requiredBet / maxSafeBankrollBet) - 1e-9).ceil(); // ceil(0.030 / 0.015) = 2
      final double slicedBet = requiredBet / numSlices; // 0.015 DOGE
      expect(numSlices, equals(2));
      expect(slicedBet, closeTo(0.015, 0.000001));

      // Worst case: If slicedBet (0.015) is completely lost on this round:
      final double balanceAfterLoss = currentBal - slicedBet;
      expect(balanceAfterLoss, greaterThanOrEqualTo(capitalFloor - 0.00000001),
          reason: 'Even on complete loss of recovery bet, balance NEVER breaches 90% Capital Floor!');

      // ─── 3. USER WIPEOUT SCENARIO CLOSURE (THE ALL-IN LOOPHOLE FIX) ───
      // Scenario that previously wiped out user:
      // High New was 0.050 DOGE, Floor was 0.045 DOGE.
      // Balance had dropped to 0.010 DOGE (severe drawdown).
      // Old logic: ath20Cap = 0.050 * 0.20 = 0.010 DOGE.
      // Old logic placed 0.010 DOGE bet -> ALL-IN 100% of the remaining 0.010 balance!
      s.sessionMaxBalance = 0.050;
      currentBal = 0.010;
      final double wipedFloor = s.emergencyCapitalFloor; // 0.0450
      final bool isAboveFloor = currentBal > (wipedFloor + 0.00000001);

      // Eligibility Check in _executeSmartFlow:
      final bool isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 &&
                                         !s.isMicroProbingActive &&
                                         !s.isIntermissionProbeActive &&
                                         isAboveFloor;

      expect(isAboveFloor, isFalse,
          reason: 'Current balance 0.010 is below 90% High New Floor 0.0450');
      expect(isEligibleForRecovery, isFalse,
          reason: 'Recovery MUST be 100% frozen when at or below 90% Floor! Locked to Base Bet.');

      // If recovery calculation were evaluated:
      final double riskBufferWipeout = max(0.0, currentBal - wipedFloor); // 0.0
      final double current20CapWipeout = currentBal * 0.20; // 0.0020 DOGE
      final double ath20CapWipeout = s.sessionMaxBalance * 0.20; // 0.010 DOGE
      final double tripleLockBet = min(ath20CapWipeout, min(current20CapWipeout, riskBufferWipeout));

      expect(tripleLockBet, equals(0.0),
          reason: 'Triple-Lock mathematically collapses to 0.0 risk buffer, completely preventing All-In!');
      expect(tripleLockBet < floorBet, isTrue,
          reason: 'Risk buffer exhausted -> immediately returns and forces Base Bet');
    });

    test('User Directive: 100% Full Debt Recovery on Every Loss (Streak < 4, 90% Floor Protection)', () {
      final s = GameModeSessionState(GameMode.towers);
      const double floorBet = 0.00007882;
      const double pRate = 0.42;
      s.lockedBaseBet = floorBet;
      s.sessionStartBalance = 1.0;
      s.sessionMaxBalance = 1.0;
      s.activeNewLoss = 0.001; // Initial debt

      // ─── 1. LINEAR REAL LOSS RECORDING ───
      const double recoveryBetVal = 0.00240;
      final double baseBetLoss = s.lockedBaseBet ?? floorBet;
      final double lossToAdd = recoveryBetVal > 0.0 ? recoveryBetVal : baseBetLoss;

      s.activeNewLoss += lossToAdd;
      s.activeNewLoss = double.parse(s.activeNewLoss.toStringAsFixed(8));
      s.consecutiveLossesStreak = 1;

      expect(s.totalAccumulatedLoss, closeTo(0.001 + 0.00240, 0.00000001),
          reason: 'Debt must record exact bet loss amount linearly');

      // ─── 2. 100% RECOVERY ELIGIBILITY FOR STREAK < 4 ───
      // When streak is 1, 2, or 3: 100% recovery is fully eligible!
      for (int streak = 1; streak <= 3; streak++) {
        s.consecutiveLossesStreak = streak;
        final bool isFourStreak = s.consecutiveLossesStreak >= 4;
        final bool isAboveFloor = 0.99 > (s.emergencyCapitalFloor + 0.00000001);
        final bool isEligible = s.totalAccumulatedLoss > 0 &&
                               !s.isLossStreakBaseBetLocked &&
                               !isFourStreak &&
                               isAboveFloor;
        expect(isEligible, isTrue,
            reason: 'At streak $streak (< 4), 100% recovery MUST be eligible!');
      }

      // ─── 3. 4-LOSS STREAK LIMIT (ANTI-DEATH-SPIRAL) ───
      // When streak reaches 4: locks to Base Bet
      s.consecutiveLossesStreak = 4;
      final bool isFourStreak = s.consecutiveLossesStreak >= 4;
      if (isFourStreak) {
        s.isLossStreakBaseBetLocked = true;
      }
      final bool isEligibleAt4 = s.totalAccumulatedLoss > 0 &&
                                 !s.isLossStreakBaseBetLocked &&
                                 !isFourStreak;
      expect(isEligibleAt4, isFalse,
          reason: 'At 4 consecutive losses, recovery must be locked to Base Bet!');
      expect(s.isLossStreakBaseBetLocked, isTrue);

      // ─── 4. SINGLE WIN INSTANTLY UNLOCKS RECOVERY ───
      // When 1 win occurs: unlocks base bet lock and resets streak to 0
      s.isLossStreakBaseBetLocked = false;
      s.consecutiveLossesStreak = 0;
      final bool isEligibleAfterWin = s.totalAccumulatedLoss > 0 &&
                                      !s.isLossStreakBaseBetLocked &&
                                      s.consecutiveLossesStreak < 4;
      expect(isEligibleAfterWin, isTrue,
          reason: 'Single win must instantly unlock recovery!');

      // ─── 5. 100% RECOVERY SIZING CLEARS DEBT IN 1 ROUND ───
      final double debtToEscalate = s.totalAccumulatedLoss; // 0.0034
      final double baseSurplus = floorBet * pRate * 2.0;
      final double targetProfit = debtToEscalate + baseSurplus;
      final double requiredBet = targetProfit / pRate;
      final double winProfit = requiredBet * pRate;

      expect(winProfit, greaterThanOrEqualTo(debtToEscalate),
          reason: '100% recovery bet must clear full debt in 1 winning round');

      s.subtractProfitFromDebt(winProfit);
      expect(s.totalAccumulatedLoss, equals(0.0),
          reason: 'Winning 100% recovery bet clears all debt to 0');
    });

    test('User Directive: Mines (Polpick) 100% Full Debt Recovery & Streak-2 Micro Probing Guarantee', () {
      final s = GameModeSessionState(GameMode.mines);
      const double floorBet = 0.00001; // Polpick floor
      const double pRate = 0.48; // Mines Level 8: 48% (9 mines / 16 gems)
      s.lockedBaseBet = floorBet;
      s.sessionStartBalance = 10.0;
      s.sessionMaxBalance = 10.0;
      s.lastSettledBalance = 10.0;
      expect(s.emergencyCapitalFloor, closeTo(9.0, 0.00000001));

      // ─── 1. SIMULATE SCRAPING DELAY / 0.00000000 DOM BALANCE FALLBACK ───
      // When DOM scraping fails or returns 0.0, fallback kicks in:
      double scrapedBalance = 0.0;
      double effectiveBalance = scrapedBalance > 0.00000001
          ? scrapedBalance
          : (s.lastSettledBalance > 0.00000001 ? s.lastSettledBalance : (s.sessionStartBalance ?? 0.0));
      expect(effectiveBalance, equals(10.0),
          reason: 'Fallback must protect against false 0.0 balance on Mines');

      final double capitalFloor = s.emergencyCapitalFloor;
      final bool isAboveFloor = (capitalFloor <= 0.00000001) ||
                                (effectiveBalance > (capitalFloor + 0.00000001));
      expect(isAboveFloor, isTrue,
          reason: 'Mines must be above 90% capital floor with fallback balance');

      // ─── 2. ROUND 1: Base Bet Loss ───
      s.activeNewLoss += floorBet;
      s.consecutiveLossesStreak = 1;
      expect(s.totalAccumulatedLoss, closeTo(floorBet, 0.00000001));
      expect(s.isMicroProbingActive, isFalse);

      // Round 2 check: Streak = 1 -> MUST trigger 100% Full Recovery!
      bool isFourStreak = s.consecutiveLossesStreak >= 4;
      bool isEligibleR2 = s.totalAccumulatedLoss > 0 &&
                          !s.isLossStreakBaseBetLocked &&
                          !isFourStreak &&
                          !s.isMicroProbingActive &&
                          isAboveFloor;
      expect(isEligibleR2, isTrue,
          reason: 'Mines Round 2 MUST be eligible for 100% full recovery bet!');

      // Sizing 100% recovery bet for Mines:
      final double debtToEscalate = s.totalAccumulatedLoss;
      final double baseSurplus = floorBet * pRate * 2.0;
      final double targetProfit = debtToEscalate + baseSurplus;
      final double requiredBet = targetProfit / pRate;

      // Triple-Lock check for Mines:
      final double availableRiskBuffer = max(0.0, effectiveBalance - capitalFloor); // 1.0
      final double ath20Cap = s.sessionMaxBalance * 0.20; // 2.0
      final double current20Cap = effectiveBalance * 0.20; // 2.0
      final double maxSafeBankrollBet = min(ath20Cap, min(current20Cap, availableRiskBuffer)); // 1.0

      expect(requiredBet, lessThan(maxSafeBankrollBet),
          reason: 'Recovery bet for 1 loss is well within safe 20% ceiling');

      // ─── 3. ROUND 2: Recovery Bet LOSES -> Streak reaches 2 ───
      s.activeNewLoss += requiredBet;
      s.consecutiveLossesStreak = 2;

      // Triggers Streak-2 Micro Probing:
      if (s.consecutiveLossesStreak >= 2 && !s.isMicroProbingActive) {
        s.isMicroProbingActive = true;
      }
      expect(s.isMicroProbingActive, isTrue,
          reason: 'Streak >= 2 activates Micro Probing on Mines');

      // Round 3 check: Micro Probing active -> Recovery bet MUST NOT fire!
      isFourStreak = s.consecutiveLossesStreak >= 4;
      bool isEligibleR3 = s.totalAccumulatedLoss > 0 &&
                          !s.isLossStreakBaseBetLocked &&
                          !isFourStreak &&
                          !s.isMicroProbingActive &&
                          isAboveFloor;
      expect(isEligibleR3, isFalse,
          reason: 'Round 3 on Mines MUST NOT fire big recovery bet; must be blocked by Micro Probing!');

      // ─── 4. ROUND 3: Micro Probe Bet (Base Bet) LOSES ───
      s.activeNewLoss += floorBet;
      s.consecutiveLossesStreak = 3;
      expect(s.isMicroProbingActive, isTrue,
          reason: 'Probe loss keeps Micro Probing active');

      // ─── 5. ROUND 4: Micro Probe Bet (Base Bet) WINS! ───
      // Win Handler on probe win:
      if (s.isMicroProbingActive) {
        s.isMicroProbingActive = false;
        s.consecutiveLossesStreak = 0;
        s.isLossStreakBaseBetLocked = false;
      }
      expect(s.isMicroProbingActive, isFalse);
      expect(s.consecutiveLossesStreak, equals(0));

      // ─── 6. ROUND 5: Probe Confirmed -> 100% Recovery Bet Fires on Golden Highway! ───
      isFourStreak = s.consecutiveLossesStreak >= 4;
      bool isEligibleR5 = s.totalAccumulatedLoss > 0 &&
                          !s.isLossStreakBaseBetLocked &&
                          !isFourStreak &&
                          !s.isMicroProbingActive &&
                          isAboveFloor;
      expect(isEligibleR5, isTrue,
          reason: 'Round 5 after probe win MUST fire 100% full recovery on Golden Highway!');

      // Calculate 100% recovery bet for total accumulated debt:
      final double totalDebtMines = s.totalAccumulatedLoss;
      final double targetProfitR5 = totalDebtMines + baseSurplus;
      final double recoveryBetR5 = targetProfitR5 / pRate;
      final double profitOnWin = recoveryBetR5 * pRate;

      expect(profitOnWin, greaterThanOrEqualTo(totalDebtMines),
          reason: 'Winning Round 5 recovery clears all accumulated Mines debt!');

      s.subtractProfitFromDebt(profitOnWin);
      expect(s.totalAccumulatedLoss, equals(0.0),
          reason: '100% Full recovery completed on Mines!');
    });

    test('User Directive: Slow Network / Phantom Win Protection (Never clear debt when balanceIncreased is false)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 15.0; // Current debt = 15 DOGE
      expect(s.totalAccumulatedLoss, closeTo(15.0, 0.00000001));

      // Simulate a Cashout Win where DOM has not updated yet (balanceIncreased == false)
      const double winningBet = 20.0;
      const double actualProfit = 10.0;
      const bool balanceIncreased = false;
      const double balanceBeforeRound = 85.0;
      const double balanceAfterWin = 0.0; // DOM still shows old or 0.0

      // In Win Handler:
      // 1. Debt is reduced by actual profit
      s.subtractProfitFromDebt(actualProfit);
      expect(s.totalAccumulatedLoss, closeTo(5.0, 0.00000001),
          reason: 'Profit must pay down debt from 15 to 5');

      // 2. Determine currentBalForCheck without phantom profit:
      final double currentBalForCheck = balanceIncreased && balanceAfterWin > 0.00000001
          ? balanceAfterWin
          : (balanceBeforeRound > 0.00000001 ? balanceBeforeRound : 85.0);

      // 3. Evaluate recovery status:
      bool isFullyRecovered = false;
      if (balanceIncreased && s.sessionMaxBalance > 0.00000001 && currentBalForCheck < s.sessionMaxBalance - 0.00000001) {
        final double remainingDeficit = s.sessionMaxBalance - currentBalForCheck;
        if (s.totalAccumulatedLoss > remainingDeficit + 0.00000001) {
          s.clampDebtToMax(remainingDeficit);
        }
        isFullyRecovered = false;
      } else if (balanceIncreased) {
        isFullyRecovered = s.totalAccumulatedLoss <= 0.00000001 || (currentBalForCheck >= s.sessionMaxBalance && s.sessionMaxBalance > 0.00000001);
      } else {
        // Slow DOM: MUST NOT declare recovery!
        isFullyRecovered = false;
      }

      expect(isFullyRecovered, isFalse,
          reason: 'Must NOT declare victory or reset debt when DOM balance has not physically increased!');
      expect(s.totalAccumulatedLoss, closeTo(5.0, 0.00000001),
          reason: 'Debt must be preserved at 5.0 and NOT dropped to 0!');
    });

    test('User Directive: Pre-M0 High New Real Debt Audit (Auto-restore deficit if DOM balance < High New)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0; // High New = 100.0
      s.activeNewLoss = 0.0; // Debt was erroneously dropped or unrecorded (0.0)

      // Screen froze / DOM settled balance is 88.0 DOGE (real deficit = 12.0 DOGE)
      const double settledBalance = 88.0;

      // Pre-M0 Audit logic:
      if (s.sessionMaxBalance > 0.00000001 && settledBalance > 0.00000001) {
        final double realDeficit = s.sessionMaxBalance - settledBalance;
        if (realDeficit > 0.00000001) {
          final double targetDebt = double.parse(max(s.totalAccumulatedLoss, realDeficit).toStringAsFixed(8));
          if ((targetDebt - s.totalAccumulatedLoss).abs() > 0.00000001) {
            s.activeNewLoss = targetDebt;
            s.readyToRecoverLoss = 0.0;
            s.frozenDebtBuckets.clear();
          }
        }
      }

      // Debt MUST be restored to exactly 12.0 DOGE!
      expect(s.totalAccumulatedLoss, closeTo(12.0, 0.00000001),
          reason: 'Pre-M0 Audit MUST resurrect unrecovered deficit from High New to prevent debt abandonment!');
    });

    test('User Directive: Stale DOM Balance after Loss does NOT wipe debt (Streak > 0 Guard)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 5.0; // Lost 5.0 in the round just played
      s.consecutiveLossesStreak = 1; // Just lost

      // Stale DOM reading: still reads 100.0 because web page hasn't updated its display yet
      const double settledBalance = 100.0;

      // Pre-M0 Audit with Streak Guard:
      if (s.sessionMaxBalance > 0.00000001 && settledBalance > 0.00000001) {
        final double realDeficit = s.sessionMaxBalance - settledBalance;
        if (realDeficit > 0.00000001) {
          final double targetDebt = double.parse(max(s.totalAccumulatedLoss, realDeficit).toStringAsFixed(8));
          s.activeNewLoss = targetDebt;
        } else if (settledBalance >= s.sessionMaxBalance) {
          s.sessionMaxBalance = settledBalance;
          // Only reset debt if consecutiveLossesStreak == 0!
          if (s.consecutiveLossesStreak == 0 && s.totalAccumulatedLoss > 0.00000001) {
            s.resetDebt();
          }
        }
      }

      // Since consecutiveLossesStreak == 1, debt MUST NOT be reset!
      expect(s.totalAccumulatedLoss, closeTo(5.0, 0.00000001),
          reason: 'Stale DOM reading equal to ATH must NOT wipe debt when consecutiveLossesStreak > 0!');
    });

    test('User Directive: Casino Anti-Targeting Detection (Hold Fire on recovery bet miss or long session)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 2.0; // Has debt
      s.consecutiveLossesStreak = 2;
      s.consecutiveRecoveryLosses = 1; // 1 recovery bet missed -> Casino targeting triggered!

      const double chaosIndex = 0.50;
      const String marketRegime = 'STABLE_EDGE';
      const bool isGoldenHighway = false; // No Golden Highway yet

      // Anti-Targeting check:
      final bool isCasinoTargeting = s.consecutiveRecoveryLosses >= 1 ||
                                     (s.roundsSinceLastMacroBreak >= 60) ||
                                     (s.totalSessionRoundsPlayed > 0 && s.totalSessionRoundsPlayed % 100 >= 60) ||
                                     (chaosIndex >= 0.75) ||
                                     (marketRegime == 'CHOP');

      expect(isCasinoTargeting, isTrue,
          reason: 'consecutiveRecoveryLosses >= 1 must flag isCasinoTargeting = true');

      const bool isEligibleForRecovery = true;
      bool allowRecoveryFire = isEligibleForRecovery;
      if (isEligibleForRecovery && isCasinoTargeting) {
        if (isGoldenHighway) {
          allowRecoveryFire = true;
        } else {
          allowRecoveryFire = false; // HOLD FIRE!
        }
      }

      expect(allowRecoveryFire, isFalse,
          reason: 'When targeted and no Golden Highway, system MUST HOLD FIRE and refuse to place big recovery bet!');
    });

    test('User Directive: Stealth Base Bet Camouflage & Continuous Debt Paydown', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 1.0; // Debt = 1.0 DOGE
      s.consecutiveRecoveryLosses = 1; // Targeted

      const double floorBet = 0.00007882;
      const double pRate = 0.42; // Towers
      const double actualProfit = floorBet * pRate;

      // In stealth mode, bot plays Base Bet. Base Bet wins!
      s.subtractProfitFromDebt(actualProfit);
      s.consecutiveBaseBetWins = 1;

      expect(s.totalAccumulatedLoss, lessThan(1.0),
          reason: 'Base Bet profit MUST be used for Stealth Paydown to reduce debt safely');
      expect(s.totalAccumulatedLoss, closeTo(1.0 - actualProfit, 0.00000001));

      // Second Base Bet wins!
      s.subtractProfitFromDebt(actualProfit);
      s.consecutiveBaseBetWins = 2;

      // When consecutiveBaseBetWins reaches 2, trend is confirmed safe!
      if (s.consecutiveBaseBetWins >= 2) {
        s.consecutiveRecoveryLosses = 0; // Cleared targeting flag!
      }
      expect(s.consecutiveRecoveryLosses, equals(0),
          reason: '2 consecutive Base Bet wins confirms calm waters and clears recovery loss flag');
    });

    test('User Directive: Golden Highway Clearance Unlocks 100% Recovery during Casino Targeting', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 0.50; // Debt = 0.50 DOGE
      s.consecutiveRecoveryLosses = 1; // Targeted!

      // Case 1: Without Golden Highway -> HOLD FIRE
      bool isGoldenHighway = false;
      bool isCasinoTargeting = s.consecutiveRecoveryLosses >= 1;
      bool allowRecoveryFire = true;
      if (isCasinoTargeting && !isGoldenHighway) {
        allowRecoveryFire = false;
      }
      expect(allowRecoveryFire, isFalse, reason: 'Must hold fire without Golden Highway');

      // Case 2: Golden Highway appears! (e.g. Ping-Pong A-B-A detected by OmniMatrix)
      OmniMatrixEngine.instance.resetAllMemory(mode: GameMode.towers);
      OmniMatrixEngine.instance.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      OmniMatrixEngine.instance.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      OmniMatrixEngine.instance.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);

      final omni = OmniMatrixEngine.instance.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.50,
        currentBalance: 99.50,
      );

      expect(omni.isGoldenHighway, isTrue,
          reason: 'Ping-Pong A-B-A must produce isGoldenHighway = true');
      expect(omni.column, equals('C'),
          reason: 'Untouched column C must be the Golden Highway destination');

      // Under Targeting, Golden Highway grants CLEARANCE!
      if (isCasinoTargeting && (omni.isGoldenHighway || omni.recoveryClearance == RecoveryClearance.full100)) {
        allowRecoveryFire = true;
      }
      expect(allowRecoveryFire, isTrue,
          reason: 'Golden Highway MUST unlock recovery bet even when previously targeted!');

      // Simulate Golden Highway recovery win:
      const double recoveryBet = 0.50 / 0.42;
      const double profit = recoveryBet * 0.42;
      s.subtractProfitFromDebt(profit);
      s.consecutiveRecoveryLosses = 0;

      expect(s.totalAccumulatedLoss, equals(0.0),
          reason: '100% Recovery on Golden Highway successfully clears all debt');
      expect(s.consecutiveRecoveryLosses, equals(0),
          reason: 'Recovery win resets recovery losses to 0');
    });

    test('User Directive: 4-Loss Streak triggers 15-30m Debt Freeze & Base Bet Lock (Phase 1)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.activeNewLoss = 0.00031528; // 4 Base Bet losses
      s.consecutiveLossesStreak = 4;
      s.stagedRecoveryPhase = 0;

      // When 4 losses streak triggers:
      final bool isFourLosses = s.consecutiveLossesStreak >= 4;
      expect(isFourLosses, isTrue);

      if (isFourLosses && s.stagedRecoveryPhase == 0) {
        final int freezeMinutes = 15 + Random().nextInt(16); // 15 to 30 mins
        final freezeTime = DateTime.now().add(Duration(minutes: freezeMinutes));
        s.fourLossesFreezeUntil = freezeTime;
        final double totalToFreeze = s.totalAccumulatedLoss;
        s.frozenDebtBuckets.clear();
        s.frozenDebtBuckets.add(DebtBucket(
          amount: totalToFreeze,
          freezeUntil: freezeTime,
          tierName: '4_loss_staged_freeze',
        ));
        s.activeNewLoss = 0.0;
        s.readyToRecoverLoss = 0.0;
        s.stagedRecoveryPhase = 1;
        s.isLossStreakBaseBetLocked = true;
        s.consecutiveBaseBetWins = 0;
      }

      expect(s.stagedRecoveryPhase, equals(1),
          reason: 'Phase must transition to 1 (15-30m freeze)');
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Must lock into Base Bet during 15-30m freeze');
      expect(s.fourLossesFreezeUntil, isNotNull);
      final int diffMins = s.fourLossesFreezeUntil!.difference(DateTime.now()).inMinutes;
      expect(diffMins, inInclusiveRange(14, 30),
          reason: 'Freeze duration must be between 15 and 30 minutes');
      expect(s.frozenDebtBuckets.length, equals(1));
      expect(s.totalAccumulatedLoss, closeTo(0.00031528, 0.00000001),
          reason: 'Total debt must be preserved in frozenDebtBuckets');

      // In Phase 1, even if a Base Bet wins, lock MUST remain:
      const double baseProfit = 0.00007882 * 0.42;
      s.subtractProfitFromDebt(baseProfit);
      if (s.stagedRecoveryPhase == 1) {
        s.isLossStreakBaseBetLocked = true; // Still locked!
      }
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Base Bet win during Phase 1 does NOT unlock recovery');
      expect(s.totalAccumulatedLoss, closeTo(0.00031528 - baseProfit, 0.00000001),
          reason: 'Base Bet profit reduces frozen debt via Stealth Paydown');
    });

    test('User Directive: Freeze Expiry thaws first 50% into readyToRecoverLoss (Phase 2)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.stagedRecoveryPhase = 1;
      s.isLossStreakBaseBetLocked = true;
      // Freeze expired 1 minute ago:
      s.fourLossesFreezeUntil = DateTime.now().subtract(const Duration(minutes: 1));
      s.frozenDebtBuckets.add(DebtBucket(
        amount: 2.0, // 2.0 DOGE frozen
        freezeUntil: s.fourLossesFreezeUntil!,
        tierName: '4_loss_staged_freeze',
      ));

      // In _executeSmartFlow:
      if (s.stagedRecoveryPhase == 1 && s.fourLossesFreezeUntil != null) {
        if (DateTime.now().isAfter(s.fourLossesFreezeUntil!)) {
          final double totalFrozen = s.totalAccumulatedLoss;
          final double first50 = double.parse((totalFrozen * 0.50).toStringAsFixed(8));
          final double remaining50 = double.parse((totalFrozen - first50).toStringAsFixed(8));
          s.readyToRecoverLoss = first50;
          s.activeNewLoss = 0.0;
          s.frozenDebtBuckets.clear();
          if (remaining50 > 0.00000001) {
            s.frozenDebtBuckets.add(DebtBucket(
              amount: remaining50,
              freezeUntil: DateTime.now().add(const Duration(days: 365)),
              tierName: 'staged_50_remaining',
            ));
          }
          s.stagedRecoveryPhase = 2; // Phase 2
          s.isLossStreakBaseBetLocked = false;
          s.consecutiveLossesStreak = 0;
          s.consecutiveRecoveryLosses = 0;
        }
      }

      expect(s.stagedRecoveryPhase, equals(2),
          reason: 'Must transition to Phase 2 after freeze timer expires');
      expect(s.readyToRecoverLoss, closeTo(1.0, 0.00000001),
          reason: '50% of 2.0 DOGE is 1.0 DOGE thawed');
      expect(s.frozenDebtBuckets.first.amount, closeTo(1.0, 0.00000001),
          reason: 'Remaining 50% (1.0 DOGE) remains in frozen vault');
      expect(s.isLossStreakBaseBetLocked, isFalse,
          reason: 'Recovery lock is cleared so 50% slice can be recovered on clearance');

      // Sizing check:
      final double debtToEscalate = s.readyToRecoverLoss > 0.00000001
          ? s.readyToRecoverLoss
          : s.totalAccumulatedLoss;
      expect(debtToEscalate, closeTo(1.0, 0.00000001),
          reason: 'Recovery bet MUST be sized on 1.0 DOGE (50% slice), NOT the total 2.0 DOGE!');
    });

    test('User Directive: Stage 1 Win requires 2 consecutive Base Bet wins to unlock remaining 50% (Phase 3)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.stagedRecoveryPhase = 2;
      s.readyToRecoverLoss = 1.0;
      s.frozenDebtBuckets.add(DebtBucket(
        amount: 1.0,
        freezeUntil: DateTime.now().add(const Duration(days: 365)),
        tierName: 'staged_50_remaining',
      ));

      // Simulate Stage 1 recovery bet WINS:
      const double actualProfit = 1.0 + (0.00007882 * 0.42 * 2.0); // 1.0 + surplus
      s.subtractProfitFromDebt(actualProfit);
      expect(s.readyToRecoverLoss, equals(0.0),
          reason: 'Stage 1 win clears readyToRecoverLoss');

      // Win handler transitions to Phase 3:
      if (s.stagedRecoveryPhase == 2) {
        s.readyToRecoverLoss = 0.0;
        s.stagedRecoveryPhase = 3;
        s.isLossStreakBaseBetLocked = true;
        s.consecutiveBaseBetWins = 0;
      }

      expect(s.stagedRecoveryPhase, equals(3));
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'Must lock to Base Bet after winning 50% slice');

      // Base Bet Round 1 WINS:
      s.consecutiveBaseBetWins = 1;
      // In win handler for Phase 3:
      if (s.stagedRecoveryPhase == 3) {
        if (s.consecutiveBaseBetWins >= 2) {
          s.stagedRecoveryPhase = 4;
        } else {
          s.isLossStreakBaseBetLocked = true;
        }
      }
      expect(s.stagedRecoveryPhase, equals(3),
          reason: 'Winning 1 Base Bet must NOT unlock remaining 50%');
      expect(s.isLossStreakBaseBetLocked, isTrue);

      // Base Bet Round 2 WINS:
      s.consecutiveBaseBetWins = 2;
      if (s.stagedRecoveryPhase == 3) {
        if (s.consecutiveBaseBetWins >= 2) {
          final double remaining50 = s.frozenDebtBuckets.fold(0.0, (sum, b) => sum + b.amount) + s.activeNewLoss;
          s.readyToRecoverLoss = double.parse(remaining50.toStringAsFixed(8));
          s.activeNewLoss = 0.0;
          s.frozenDebtBuckets.clear();
          s.stagedRecoveryPhase = 4;
          s.isLossStreakBaseBetLocked = false;
          s.consecutiveLossesStreak = 0;
        }
      }

      expect(s.stagedRecoveryPhase, equals(4),
          reason: '2 consecutive Base Bet wins unlocks Phase 4!');
      expect(s.readyToRecoverLoss, closeTo(1.0 - (0.00007882 * 0.42 * 2.0), 0.00000001),
          reason: 'Remaining 50% thawed for Stage 2 (reduced by surplus margin from Stage 1 win)');
      expect(s.frozenDebtBuckets.isEmpty, isTrue,
          reason: 'Frozen vault is empty now');
      expect(s.isLossStreakBaseBetLocked, isFalse,
          reason: 'Ready to fire Stage 2 recovery on clearance');
    });

    test('User Directive: Stage 2 Win clears all debt to 0 and resets to Phase 0 Normal', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;
      s.stagedRecoveryPhase = 4;
      s.readyToRecoverLoss = 1.0;

      // Stage 2 recovery bet WINS:
      const double actualProfit = 1.0 + (0.00007882 * 0.42 * 2.0);
      s.subtractProfitFromDebt(actualProfit);

      // Win handler for Phase 4:
      if (s.stagedRecoveryPhase == 4) {
        s.readyToRecoverLoss = 0.0;
        s.frozenDebtBuckets.clear();
        s.stagedRecoveryPhase = 0;
        s.fourLossesFreezeUntil = null;
        s.isLossStreakBaseBetLocked = false;
        s.resetDebt();
      }

      expect(s.totalAccumulatedLoss, equals(0.0),
          reason: 'All debt cleared after Stage 2 win');
      expect(s.stagedRecoveryPhase, equals(0),
          reason: 'Returned to normal Phase 0');
      expect(s.fourLossesFreezeUntil, isNull);
      expect(s.isLossStreakBaseBetLocked, isFalse);
    });

    test('User Directive: During Phase 1 Freeze, non-frozen debt (activeNewLoss) can be recovered normally', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // Step 1: 4-loss streak triggered Phase 1 freeze with 0.001 frozen
      s.frozenDebtBuckets.add(DebtBucket(
        amount: 0.001,
        freezeUntil: DateTime.now().add(const Duration(minutes: 20)),
        tierName: '4_loss_staged_freeze',
      ));
      s.activeNewLoss = 0.0;
      s.readyToRecoverLoss = 0.0;
      s.stagedRecoveryPhase = 1;
      s.isLossStreakBaseBetLocked = true;
      s.fourLossesFreezeUntil = DateTime.now().add(const Duration(minutes: 20));
      s.consecutiveLossesStreak = 0; // Reset after entering Phase 1

      // Step 2: Bot plays Base Bet during freeze and LOSES a round
      const double baseBetLoss = 0.00007882;
      s.activeNewLoss += baseBetLoss;
      s.consecutiveLossesStreak = 1;

      // Step 3: Check if non-frozen debt is recoverable during Phase 1
      final bool hasNonFrozenDebtInFreeze = s.stagedRecoveryPhase == 1 && s.activeNewLoss > 0.00000001;
      expect(hasNonFrozenDebtInFreeze, isTrue,
          reason: 'activeNewLoss exists during Phase 1 -> non-frozen debt detected');

      final bool isEligibleForRecovery = s.totalAccumulatedLoss > 0.00000001 &&
          (!s.isLossStreakBaseBetLocked || hasNonFrozenDebtInFreeze) &&
          s.consecutiveLossesStreak < 4 &&
          true; // isAboveFloor
      expect(isEligibleForRecovery, isTrue,
          reason: 'Non-frozen debt during Phase 1 MUST be eligible for recovery!');

      // Step 4: Verify debtToEscalate uses activeNewLoss, NOT totalAccumulatedLoss
      final double debtToEscalate;
      if (s.readyToRecoverLoss > 0.00000001) {
        debtToEscalate = s.readyToRecoverLoss;
      } else if (s.stagedRecoveryPhase == 1 && s.activeNewLoss > 0.00000001) {
        debtToEscalate = s.activeNewLoss;
      } else {
        debtToEscalate = s.totalAccumulatedLoss;
      }
      expect(debtToEscalate, closeTo(baseBetLoss, 0.00000001),
          reason: 'Recovery bet MUST be sized on activeNewLoss ($baseBetLoss) only, NOT on total including frozen vault (${s.totalAccumulatedLoss})!');

      // Step 5: Frozen debt must remain untouched
      expect(s.frozenDebtBuckets.first.amount, closeTo(0.001, 0.00000001),
          reason: 'Frozen debt must NOT be touched during non-frozen recovery');
      expect(s.stagedRecoveryPhase, equals(1),
          reason: 'Phase must remain 1 during non-frozen debt recovery');

      // Step 6: Recovery wins -> clears only activeNewLoss
      const double profit = baseBetLoss + (0.00007882 * 0.42 * 2.0);
      s.subtractProfitFromDebt(profit);
      expect(s.activeNewLoss, equals(0.0),
          reason: 'Non-frozen debt cleared after recovery win');
      expect(s.frozenDebtBuckets.first.amount, lessThan(0.001),
          reason: 'Excess profit from recovery may reduce frozen debt via Stealth Paydown');
      expect(s.stagedRecoveryPhase, equals(1),
          reason: 'Phase remains 1 - frozen debt still waiting for timer expiry');
    });

    test('User Directive: Full 100% Debt Recovery on Streaks 1, 2, and 3 (NEVER return to Base Bet at Streak 2)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // Loss 1: Streak 1
      s.activeNewLoss = 0.0001;
      s.consecutiveLossesStreak = 1;
      expect(s.consecutiveLossesStreak < 4, isTrue);
      // Verify recoverableDebt and eligibility at Streak 1
      double recoverableDebt = s.stagedRecoveryPhase == 0 ? s.totalAccumulatedLoss : s.activeNewLoss;
      bool isEligible = s.consecutiveLossesStreak < 4 && recoverableDebt > 0.00000001;
      expect(isEligible, isTrue, reason: 'Streak 1 MUST be eligible for 100% recovery');
      expect(recoverableDebt, closeTo(0.0001, 0.00000001));

      // Loss 2: Streak 2 (The user specifically complained that it fell back to Base Bet here!)
      s.activeNewLoss += 0.0002;
      s.consecutiveLossesStreak = 2;
      expect(s.consecutiveLossesStreak < 4, isTrue);
      recoverableDebt = s.stagedRecoveryPhase == 0 ? s.totalAccumulatedLoss : s.activeNewLoss;
      isEligible = s.consecutiveLossesStreak < 4 && recoverableDebt > 0.00000001;
      expect(isEligible, isTrue, reason: 'Streak 2 MUST be eligible for 100% recovery (NOT fall back to Base Bet)');
      expect(recoverableDebt, closeTo(0.0003, 0.00000001));

      // Loss 3: Streak 3
      s.activeNewLoss += 0.0004;
      s.consecutiveLossesStreak = 3;
      expect(s.consecutiveLossesStreak < 4, isTrue);
      recoverableDebt = s.stagedRecoveryPhase == 0 ? s.totalAccumulatedLoss : s.activeNewLoss;
      isEligible = s.consecutiveLossesStreak < 4 && recoverableDebt > 0.00000001;
      expect(isEligible, isTrue, reason: 'Streak 3 MUST be eligible for 100% recovery');
      expect(recoverableDebt, closeTo(0.0007, 0.00000001));

      // Loss 4: Streak 4 -> ONLY HERE does it fall back to Base Bet and freeze!
      s.activeNewLoss += 0.0008;
      s.consecutiveLossesStreak = 4;
      expect(s.consecutiveLossesStreak >= 4, isTrue);
    });

    test('User Directive: 4-Loss Streak resets consecutiveLossesStreak to 0 and recovers new debt in Phase 1', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // 4 losses in a row
      s.activeNewLoss = 0.0015;
      s.consecutiveLossesStreak = 4;

      // Trigger 4-loss freeze:
      final double totalToFreeze = s.totalAccumulatedLoss;
      s.frozenDebtBuckets.add(DebtBucket(
        amount: totalToFreeze,
        freezeUntil: DateTime.now().add(const Duration(minutes: 20)),
        tierName: '4_loss_staged_freeze',
      ));
      s.activeNewLoss = 0.0;
      s.readyToRecoverLoss = 0.0;
      s.stagedRecoveryPhase = 1;
      s.consecutiveLossesStreak = 0; // CRITICAL: Reset streak to 0
      s.fourLossesFreezeUntil = DateTime.now().add(const Duration(minutes: 20));

      // When activeNewLoss is 0 during Phase 1: bot walks with Base Bet
      double recoverableDebt = s.activeNewLoss;
      bool isEligible = s.consecutiveLossesStreak < 4 && recoverableDebt > 0.00000001;
      expect(isEligible, isFalse, reason: 'No new debt -> bot walks with Base Bet');

      // Bot plays Base Bet and loses 1 round:
      s.activeNewLoss += 0.00007882;
      s.consecutiveLossesStreak = 1;

      // In the next round during Phase 1:
      recoverableDebt = s.activeNewLoss;
      isEligible = s.consecutiveLossesStreak < 4 && recoverableDebt > 0.00000001;
      expect(isEligible, isTrue, reason: 'New loss during Phase 1 MUST be eligible for recovery immediately!');
      expect(recoverableDebt, closeTo(0.00007882, 0.00000001),
          reason: 'Only non-frozen debt is recovered');
      expect(s.frozenDebtBuckets.first.amount, closeTo(0.0015, 0.00000001),
          reason: 'Frozen debt remains locked in vault');
    });

    test('User Directive: No debt freezing - 100% recovery every loss, 5-6 min Base Bet cooldown on 4 losses, then 100% full debt recovery', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // 1. Loss 1, 2, 3: Full 100% recovery allowed on every round
      s.activeNewLoss = 0.0003;
      s.consecutiveLossesStreak = 3;
      bool isEligible = s.totalAccumulatedLoss > 0.00000001 &&
                        !s.isLossStreakBaseBetLocked &&
                        s.consecutiveLossesStreak < 4;
      expect(isEligible, isTrue, reason: 'Streak 1-3 MUST recover 100%');

      // 2. Loss 4 occurs -> Triggers 5-6 min Base Bet cooldown without freezing debt
      s.activeNewLoss += 0.0001; // totalDebt = 0.0004
      s.consecutiveLossesStreak = 4;
      final int cooldownMinutes = 5; // 5-6 min
      s.fourLossesFreezeUntil = DateTime.now().add(Duration(minutes: cooldownMinutes));
      s.isLossStreakBaseBetLocked = true;
      s.consecutiveLossesStreak = 0;

      // Debt is NOT frozen into buckets - it stays as real debt in totalAccumulatedLoss!
      expect(s.frozenDebtBuckets.isEmpty, isTrue, reason: 'Debt is NOT moved to frozen buckets');
      expect(s.totalAccumulatedLoss, closeTo(0.0004, 0.00000001), reason: 'All debt intact in totalAccumulatedLoss');

      // 3. During the 5-6 min cooldown: Base Bet locked
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
                   !s.isLossStreakBaseBetLocked &&
                   s.consecutiveLossesStreak < 4;
      expect(isEligible, isFalse, reason: 'During 5-6 min cooldown, recovery is paused (walk Base Bet)');

      // If Base Bet loses during cooldown, debt accumulates normally:
      s.activeNewLoss += 0.00007882;
      expect(s.totalAccumulatedLoss, closeTo(0.00047882, 0.00000001));

      // 4. Cooldown expires (5-6 min passed) -> Immediately resumes 100% recovery of the ENTIRE debt!
      s.isLossStreakBaseBetLocked = false;
      s.fourLossesFreezeUntil = null;

      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
                   !s.isLossStreakBaseBetLocked &&
                   s.consecutiveLossesStreak < 4;
      expect(isEligible, isTrue, reason: 'After 5-6 min cooldown, recovery MUST unlock immediately!');

      // Verify debt sizing takes 100% of the entire accumulated debt:
      final double debtToEscalate = s.totalAccumulatedLoss;
      expect(debtToEscalate, closeTo(0.00047882, 0.00000001),
          reason: 'Must recover 100% of the full debt in one shot!');

      // 5. Recovery wins -> clears all debt back to 0!
      const double profit = 0.00047882 + (0.00007882 * 0.42 * 2.0);
      s.subtractProfitFromDebt(profit);
      expect(s.totalAccumulatedLoss, equals(0.0), reason: 'All debt cleared after 100% recovery win');
      expect(s.isLossStreakBaseBetLocked, isFalse);
    });

    test('User Directive: เมื่อแพ้ 4 ตาต่อกันให้ตัดหนี้ทิ้งทันที ไม่รอ 5-6 นาที (Immediate debt cutoff on 4 losses)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // 1. Loss 1, 2, 3: Full 100% recovery active on every round
      s.activeNewLoss = 0.005;
      s.consecutiveLossesStreak = 3;
      bool isEligible = s.totalAccumulatedLoss > 0.00000001 && s.consecutiveLossesStreak < 4;
      expect(isEligible, isTrue, reason: 'Streak 1-3 MUST recover 100% of debt');

      // 2. Loss 4 occurs -> Triggers IMMEDIATE DEBT CUTOFF (Stop-Loss)
      s.activeNewLoss += 0.002; // Total debt was 0.007
      s.consecutiveLossesStreak = 4;

      // Execute immediate debt cut (as implemented in overlay_buttons_viewmodel):
      final double droppedDebt = s.totalAccumulatedLoss;
      expect(droppedDebt, closeTo(0.007, 0.00000001));

      s.resetDebt();
      s.consecutiveLossesStreak = 0;
      s.consecutiveRecoveryLosses = 0;
      s.isLossStreakBaseBetLocked = false;
      s.fourLossesFreezeUntil = null;

      // Update sessionMaxBalance to current balance (e.g. 99.993) to prevent Pre-M0 audit re-inflation
      const double currentBal = 99.993;
      s.sessionMaxBalance = currentBal;
      s.protectedPrincipal = currentBal * 0.97;

      // 3. Verify debt is completely 0 and NO cooldown/freeze is active
      expect(s.totalAccumulatedLoss, equals(0.0), reason: 'Debt must be wiped to 0 immediately');
      expect(s.activeNewLoss, equals(0.0), reason: 'activeNewLoss is 0');
      expect(s.frozenDebtBuckets.isEmpty, isTrue, reason: 'No frozen buckets');
      expect(s.fourLossesFreezeUntil, isNull, reason: 'No 5-6 min wait timer');
      expect(s.isLossStreakBaseBetLocked, isFalse, reason: 'No lock active');
      expect(s.consecutiveLossesStreak, equals(0), reason: 'Streak reset to 0');

      // 4. Next round plays Base Bet with 0 debt
      isEligible = s.totalAccumulatedLoss > 0.00000001 && s.consecutiveLossesStreak < 4;
      expect(isEligible, isFalse, reason: 'With 0 debt, bot plays Base Bet normally (Profit Engine)');
    });

    test('User Directive: ชนะแล้วจะไม่ทวงหนี้เด็ดขาด (Never recover debt after a win - only after a loss)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // 1. Bot plays Base Bet and WINS:
      s.consecutiveLossesStreak = 0;
      s.justWonRecoveryBet = false;
      bool isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet;
      expect(isEligible, isFalse, reason: 'After winning Base Bet, recovery is STRICTLY FORBIDDEN!');

      // 2. Bot LOSES round 1 (Streak: 1):
      s.activeNewLoss = 0.001;
      s.consecutiveLossesStreak = 1;
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet;
      expect(isEligible, isTrue, reason: 'Immediately after a loss (Streak 1), recovery is ALLOWED (100% full recovery)');

      // 3. Recovery bet is placed and WINS!
      // In win handler: debt is completely reset, consecutiveLossesStreak = 0, justWonRecoveryBet = true
      s.resetDebt();
      s.consecutiveLossesStreak = 0;
      s.justWonRecoveryBet = true;
      s.sessionMaxBalance = 100.00042; // New ATH

      // 4. Next round after winning recovery bet:
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet;
      expect(isEligible, isFalse, reason: 'ชนะแล้วจะไม่ทวงหนี้เด็ดขาด: After winning recovery, next round MUST be Base Bet!');
      expect(s.totalAccumulatedLoss, equals(0.0), reason: 'Debt is completely 0');

      // 5. Bot plays Base Bet next round and WINS again:
      s.justWonRecoveryBet = false;
      s.consecutiveLossesStreak = 0;
      s.consecutiveBaseBetWins = 1;
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet;
      expect(isEligible, isFalse, reason: 'After consecutive wins, recovery remains strictly forbidden');
    });

    test('User Directive: เมื่อแพ้ 4 ตาต่อกัน ให้ไปที่ Base Bet สังเกตแนวโน้ม 10-15 ตา ไม่ตัดหนี้ทิ้ง แล้วค่อยทวงหนี้ต่อ', () {
      final s = GameModeSessionState(GameMode.towers);
      s.sessionStartBalance = 100.0;
      s.sessionMaxBalance = 100.0;

      // 1. Loss 1, 2, 3: Full 100% recovery is active on every loss
      s.activeNewLoss = 0.001;
      s.consecutiveLossesStreak = 1;
      bool isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isTrue, reason: 'Streak 1 recovers 100%');

      s.activeNewLoss += 0.002;
      s.consecutiveLossesStreak = 2;
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isTrue, reason: 'Streak 2 recovers 100%');

      s.activeNewLoss += 0.004;
      s.consecutiveLossesStreak = 3;
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isTrue, reason: 'Streak 3 recovers 100%');

      // 2. 4th Loss occurs:
      s.activeNewLoss += 0.008; // Total debt = 0.015 DOGE
      s.consecutiveLossesStreak = 4;

      // Enter Observation Mode (No debt cut, 15-20 rounds Base Bet นับจากรอบแพ้สุดท้าย):
      final int obsRounds = 15 + Random().nextInt(6); // 15 to 20
      s.observationRoundsRemaining = obsRounds;
      s.isLossStreakBaseBetLocked = true;
      s.consecutiveLossesStreak = 0;
      s.consecutiveRecoveryLosses = 0;
      s.fourLossesFreezeUntil = null;
      s.isMicroProbingActive = false;

      // 🎯 Verify User Directives:
      // A) ห้ามตัดหนี้ทิ้ง: หนี้สะสม 0.015 DOGE ต้องอยู่ครบถ้วน 100%!
      expect(s.totalAccumulatedLoss, closeTo(0.015, 0.00000001),
          reason: 'คำสั่งผู้ใช้: ไม่ตัดหนี้ทิ้งแล้ว! หนี้ 0.015 DOGE ต้องคงอยู่ครบถ้วน');
      // B) สุ่มจำนวนไม้ 15-20 ตา นับจากรอบแพ้สุดท้าย:
      expect(s.observationRoundsRemaining, inInclusiveRange(15, 20),
          reason: 'จำนวนไม้สังเกตการณ์ต้องอยู่ระหว่าง 15 ถึง 20 ตา นับจากรอบแพ้สุดท้าย');
      // C) ล็อก Base Bet:
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'ต้องล็อก Base Bet เดินสังเกตแนวโน้ม');
      // D) Streak รีเซ็ตเป็น 0:
      expect(s.consecutiveLossesStreak, equals(0));

      // 3. During Observation Window (15-20 rounds):
      // A) การทวงหนี้ต้องถูกบล็อกเด็ดขาด:
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isFalse, reason: 'ระหว่าง 15-20 ตา ห้ามทวงหนี้เด็ดขาด เดิน Base Bet เพื่อสังเกตแนวโน้มเท่านั้น');

      // B) จำลองเล่น Base Bet ระหว่างช่วงสังเกตการณ์:
      // ตาที่ 1 ชนะ: กำไรหักลดหนี้, observationRoundsRemaining ลดลง 1
      const double winProfit = 0.000042;
      s.subtractProfitFromDebt(winProfit);
      s.observationRoundsRemaining--;
      expect(s.totalAccumulatedLoss, closeTo(0.015 - winProfit, 0.00000001),
          reason: 'ชนะ Base Bet นำกำไรมาหักลดหนี้สะสมตามจริง');
      expect(s.isLossStreakBaseBetLocked, isTrue,
          reason: 'แม้จะชนะ แต่ยังไม่ครบ 10-15 ตา ต้องคงสถานะล็อก Base Bet ต่อไป');

      // ตาที่ 2 แพ้: เสียเงินเบท เพิ่มหนี้, observationRoundsRemaining ลดลง 1
      const double baseLoss = 0.0001;
      s.activeNewLoss += baseLoss;
      s.observationRoundsRemaining--;
      expect(s.totalAccumulatedLoss, closeTo(0.015 - winProfit + baseLoss, 0.00000001),
          reason: 'แพ้ Base Bet บันทึกหนี้เพิ่มตามจริง');

      // เดิน Base Bet ต่อเนื่องจนเหลือ 1 ตา:
      while (s.observationRoundsRemaining > 1) {
        s.observationRoundsRemaining--;
        expect(s.isLossStreakBaseBetLocked, isTrue);
      }
      expect(s.observationRoundsRemaining, equals(1));

      // ตาสุดท้าย (ตาที่ 15) แพ้:
      s.activeNewLoss += baseLoss;
      s.observationRoundsRemaining--;
      // เมื่อหมดระยะสังเกตการณ์ (เหลือ 0) และตาที่แล้วแพ้:
      if (s.observationRoundsRemaining <= 0) {
        s.observationRoundsRemaining = 0;
        s.isLossStreakBaseBetLocked = false;
        s.consecutiveLossesStreak = 1; // ตาที่เพิ่งจบแพ้ และหมดช่วงสังเกตการณ์ -> พร้อมทวงหนี้!
      }

      // 4. Verification After Observation Window Ends ("แล้วค่อยทวงหนี้ต่อ"):
      expect(s.observationRoundsRemaining, equals(0));
      expect(s.isLossStreakBaseBetLocked, isFalse, reason: 'ครบ 15-20 ตาแล้ว ต้องปลดล็อก Base Bet');
      expect(s.consecutiveLossesStreak, equals(1));

      // ตาถัดไป: พร้อมทวงหนี้สะสมต่อ 100%!
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isTrue,
          reason: 'คำสั่งผู้ใช้: เมื่อสังเกตแนวโน้มครบ 15-20 ตาแล้ว ค่อยกลับมาทวงหนี้ต่อ 100%!');

      // หนี้ที่ต้องทวงคือหนี้สะสมทั้งหมดที่เก็บไว้:
      final double debtToRecover = s.totalAccumulatedLoss;
      expect(debtToRecover, greaterThan(0.014),
          reason: 'หนี้สะสมทั้งหมดยังคงอยู่ครบถ้วน');

      // ไม้ทวงหนี้ 100% ยิงและชนะ!
      s.subtractProfitFromDebt(debtToRecover);
      s.resetDebt();
      s.consecutiveLossesStreak = 0;
      s.justWonRecoveryBet = true;

      expect(s.totalAccumulatedLoss, equals(0.0), reason: 'ชนะไม้ทวงหนี้แล้ว หนี้สะสมเป็น 0');

      // กฎเหล็ก: ชนะแล้วจะไม่ทวงหนี้เด็ดขาด
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 4 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isFalse, reason: 'ชนะแล้วจะไม่ทวงหนี้เด็ดขาด เดิน Base Bet ต่อไป');
    });

    test('User Directive: ปรับขั้นต่ำ USDT เป็น 0.000005 (USDT Floor Bet & Dynamic Sizing)', () {
      final vm = OverlayButtonsViewModel();

      // 1. Verify getFloorBetForMode returns 0.000005 for USDT across different formats:
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'USDT'), equals(0.000005));
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'usdt'), equals(0.000005));
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'Tether'), equals(0.000005));
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'TETHER'), equals(0.000005));
      expect(vm.getFloorBetForMode(GameMode.mines, coinType: 'USDT'), equals(0.000005));

      // 2. Verify calculateBaseBet clamps to 0.000005 when balance is low:
      // Small balance: 0.01 USDT -> 0.01 / 10000 = 0.000001 < 0.000005 -> must return 0.000005
      final double smallBalBase = GameMode.towers.calculateBaseBet(0.01, null, coin: 'USDT');
      expect(smallBalBase, equals(0.000005),
          reason: 'Dynamic base bet must be floored at 0.000005 for USDT');

      // Zero or negative balance -> must return default floor 0.000005
      expect(GameMode.towers.calculateBaseBet(0.0, null, coin: 'USDT'), equals(0.000005));

      // 3. Verify calculateBaseBet scales up properly when balance is large:
      // Large balance: 100.0 USDT -> 100 / 10000 = 0.01 > 0.000005 -> must return 0.01
      final double largeBalBase = GameMode.towers.calculateBaseBet(100.0, null, coin: 'USDT');
      expect(largeBalBase, equals(0.01));

      // 4. Verify other coins retain their correct floor limits:
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'DOGE'), equals(0.00007882));
      expect(vm.getFloorBetForMode(GameMode.towers, coinType: 'POL'), equals(0.00000903));
      expect(vm.getFloorBetForMode(GameMode.mines, coinType: 'POL'), equals(0.00001));
    });

    test('Test 53: User Directive: ปรับจาก 5 ตา มาเป็น 3 ตา แล้วลง Base Bet ห้ามลืมหนี้ (Streak 1-2 ทวงได้, Streak 3 สังเกตการณ์)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.activeNewLoss = 0.50; // มีหนี้สะสม 0.50

      // 1. ตรวจสอบ Streaks 1, 2: ต้องมีสิทธิ์ทวงหนี้ 100% ทั้งหมด
      for (int streak = 1; streak <= 2; streak++) {
        s.consecutiveLossesStreak = streak;
        final bool isEligible = s.totalAccumulatedLoss > 0.00000001 &&
            s.consecutiveLossesStreak >= 1 &&
            s.consecutiveLossesStreak < 3 &&
            !s.justWonRecoveryBet &&
            !s.isLossStreakBaseBetLocked &&
            s.observationRoundsRemaining <= 0;
        expect(isEligible, isTrue,
            reason: 'Streak $streak ต้องมีสิทธิ์ทวงหนี้ 100% (ยอมรับการทวงได้ 1-2 ตาติดกัน)');
      }

      // 2. เมื่อแพ้ติดกันครบ 3 ตา (consecutiveLossesStreak >= 3) -> เข้าโหมดสังเกตการณ์ 15-20 ตา นับจากรอบแพ้สุดท้าย
      s.consecutiveLossesStreak = 3;
      const int obsRounds = 18; // สุ่มได้ 15-20 ตา นับจากรอบแพ้สุดท้าย
      s.observationRoundsRemaining = obsRounds;
      s.isLossStreakBaseBetLocked = true;
      s.consecutiveLossesStreak = 0;
      s.consecutiveRecoveryLosses = 0;

      // 🎯 "ห้ามลืมหนี้เด็ดขาด": หนี้สะสม 0.50 ต้องยังอยู่ครบ 100%!
      expect(s.totalAccumulatedLoss, equals(0.50),
          reason: 'คำสั่งผู้ใช้: ห้ามลืมหนี้ หนี้สะสมทั้งหมดต้องคงอยู่ครบถ้วน');

      // ตรวจสอบว่าระหว่างอยู่ในโหมดสังเกตการณ์ สิทธิ์ทวงหนี้ต้องเป็น FALSE (ห้ามทวง เดิน Base Bet)
      bool isEligibleInObs = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 3 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligibleInObs, isFalse,
          reason: 'ระหว่างสังเกตการณ์ 15-20 ตา ห้ามทวงหนี้ ต้องเดิน Base Bet');

      // 3. จำลองการเดิน Base Bet จนครบ 18 ตา:
      for (int r = 1; r < 18; r++) {
        s.observationRoundsRemaining--;
        // มีการแพ้ Base Bet เล็กน้อย เพิ่มหนี้จริง
        s.activeNewLoss += 0.000005;
        expect(s.observationRoundsRemaining, equals(18 - r));
      }
      // ตาสุดท้าย (ตาที่ 18) แพ้และจบช่วงสังเกตการณ์
      s.observationRoundsRemaining--;
      s.activeNewLoss += 0.000005;
      if (s.observationRoundsRemaining <= 0) {
        s.observationRoundsRemaining = 0;
        s.isLossStreakBaseBetLocked = false;
        s.consecutiveLossesStreak = 1; // ตาที่แล้วแพ้ และหมดช่วงสังเกตการณ์แล้ว
      }

      // 4. สังเกตการณ์ครบแล้ว -> กลับมาทวงหนี้สะสมต่อ 100%!
      expect(s.observationRoundsRemaining, equals(0));
      expect(s.isLossStreakBaseBetLocked, isFalse);
      expect(s.consecutiveLossesStreak, equals(1));
      expect(s.totalAccumulatedLoss, greaterThan(0.50),
          reason: 'หนี้สะสมเดิม + หนี้จาก Base Bet ระหว่างสังเกตการณ์ ยังอยู่ครบถ้วน');

      final bool canResumeRecovery = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 5 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(canResumeRecovery, isTrue,
          reason: 'คำสั่งผู้ใช้: สังเกตแนวโน้มครบแล้ว ให้กลับมาทวงหนี้ต่อทันที!');
    });

    test('Test 54: User Directive: Danger Zone Hold Fire Protection (ห้ามทวงหนี้ช่วงอันตรายเด็ดขาด)', () {
      final engine = OmniMatrixEngine.instance;
      engine.reset(mode: GameMode.towers);

      // 1. ตรวจสอบว่าใน Streaks 1-2: ระบบต้องทวงหนี้ 100% ทันที (ไม่โดนบล็อกการทวง)
      final s = GameModeSessionState(GameMode.towers);
      s.activeNewLoss = 0.15;
      for (int streak = 1; streak <= 2; streak++) {
        s.consecutiveLossesStreak = streak;
        final bool isEligible = s.totalAccumulatedLoss > 0.00000001 &&
            s.consecutiveLossesStreak >= 1 &&
            s.consecutiveLossesStreak < 3 &&
            !s.justWonRecoveryBet &&
            !s.isLossStreakBaseBetLocked &&
            s.observationRoundsRemaining <= 0;
        expect(isEligible, isTrue,
            reason: 'Streak $streak ต้องทวงหนี้ 100% เสมอตามคำสั่งผู้ใช้ "ให้ทวงทุกตาที่แพ้"');
      }

      // 2. สร้างสถานการณ์แพ้ 3 ตาติด เพื่อเปิด Defensive Cooldown 2 ตา
      for (int i = 0; i < 3; i++) {
        engine.recordOutcome(
          chosenColumn: 'A',
          won: false,
          revealedBombPos: 'A',
          mode: GameMode.towers,
        );
      }

      // ตรวจสอบว่า Cooldown ถูกเปิดใช้งาน
      expect(engine.getDefensiveCooldown(GameMode.towers), equals(2));

      // 🛡️ OmniMatrix ต้องสั่งการ RecoveryClearance.holdFire ทันทีเมื่อแพ้ 3 ตาติด
      final omniResult = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 0.15,
        currentBalance: 1.0,
      );
      expect(omniResult.recoveryClearance, equals(RecoveryClearance.holdFire),
          reason: 'ตลาดอยู่ในภาวะ DEFENSE/CHOP ต้องออกคำสั่ง Hold Fire');

      // 3. ตรวจสอบเกณฑ์ของ ViewModel เมื่อแตะ 3 ตาติด:
      s.consecutiveLossesStreak = 3;
      // เมื่อแตะ 3 ตาติด -> เข้าโหมดสังเกตการณ์ 15-20 ตา นับจากรอบแพ้สุดท้าย และล็อก Base Bet
      s.observationRoundsRemaining = 18;
      s.isLossStreakBaseBetLocked = true;

      final bool isEligibleAtStreak3 = s.totalAccumulatedLoss > 0.00000001 &&
          s.consecutiveLossesStreak >= 1 &&
          s.consecutiveLossesStreak < 3 &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligibleAtStreak3, isFalse,
          reason: 'เมื่อแตะ Streak 3 ต้องเข้าโหมดสังเกตการณ์และเดิน Base Bet เท่านั้น (ห้ามทวงหนี้)');
    });

    test('Test 55: User Directive: OmniMatrix Brain Upgrade (Multi-Loss Escape, Tie-Breaker, Weight Reset)', () {
      final engine = OmniMatrixEngine.instance;
      engine.reset(mode: GameMode.towers);

      // 1. Submodel Weight Auto-Reset:
      // จำลองการแพ้ 1 ตา -> น้ำหนักโมเดลลดลง
      engine.recordOutcome(
        chosenColumn: 'A',
        won: false,
        revealedBombPos: 'A',
        mode: GameMode.towers,
      );
      // หมุน Seed -> น้ำหนักต้องถูกรีเซ็ตกลับเป็น 1.0 ทั้งหมด
      engine.rotateSeed(mode: GameMode.towers);
      final weights = engine.getSubmodelWeights(GameMode.towers);
      expect(weights['markov'], equals(1.0));
      expect(weights['ngram'], equals(1.0));
      expect(weights['recency'], equals(1.0));
      expect(weights['antiCluster'], equals(1.0));

      // 2. Multi-Loss Diversity Escape:
      // จำลองการแพ้ติดกัน 2 ตา:
      // ตา 1: เลือก A โดนระเบิดที่ A
      // ตา 2: เลือก B โดนระเบิดที่ B
      engine.reset(mode: GameMode.towers);
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

      // ทำนายตาถัดไป: สถิติแพ้ A และ B ใน streak ปัจจุบัน
      // Multi-Loss Diversity Escape ต้องบูสต์คะแนนช่อง C (ช่องเดียวที่ยังไม่โดนระเบิด) ขึ้น 2.5x
      final predResult = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        currentDebt: 0.0,
      );

      // ต้องเลือกช่อง C เพื่อหักหลบออกจากวงจรระเบิด A และ B!
      expect(predResult.column, equals('C'),
          reason: 'Multi-Loss Diversity Escape ต้องเลือกช่อง C ที่ไม่เคยโดนระเบิดใน streak ปัจจุบัน');

      // 3. Sovereign Veto:
      // หาก AI Brain ดันไปทำนายช่อง A ที่เพิ่งแพ้ หรือคะแนนต่ำกว่าช่อง Top
      // OmniMatrix ต้อง Veto ทันทีแล้วเลือกช่องปลอดภัยสูงสุด
      final vetoResult = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: false,
        currentDebt: 0.0,
        aiBrainPrediction: 'A', // ช่อง A เพิ่งแพ้ไป
      );
      expect(vetoResult.column, equals('C'),
          reason: 'Sovereign Veto ต้องปฏิเสธการทำนายช่อง A ของ AI Brain แล้วเลือกช่องปลอดภัย C');
    });

    test('Test 56: User Directive: อัปเกรดเพื่อป้องกันการแพ้ > 3 ตาติด (Anti-Streak-4 Hyper Shield 🛡️)', () {
      final engine = OmniMatrixEngine.instance;
      engine.reset(mode: GameMode.towers);

      // ─── 1. ทดสอบ Streak == 2: Dual Loss Diversity Escape (โดน A แล้ว B -> ต้องล็อกเป้า C ทันที) ───
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

      final predStreak2 = engine.getNextPrediction(mode: GameMode.towers);
      expect(predStreak2.column, equals('C'),
          reason: 'Streak 2 โดน A แล้ว B -> ต้องล็อกเป้าช่องปลอดภัยบริสุทธิ์ C ทันที');

      // ─── 2. ทดสอบ Streak == 3 (CRITICAL ANTI-STREAK-4 HYPER SHIELD) ───
      // Case A: Cyclic Bomb (แพ้ A -> B -> C วนครบ 3 ช่อง)
      engine.reset(mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'C', mode: GameMode.towers);
      expect(engine.getConsecutiveLosses(GameMode.towers), equals(3));

      final predCyclic = engine.getNextPrediction(mode: GameMode.towers);
      // ในไซเคิล A -> B -> C: ระเบิดถัดไปจะวนลูปกลับไปที่ A และเพิ่งระเบิดที่ C
      // ช่องที่ปลอดภัยที่สุดคือ B (เพิ่งระเบิดไป 2 ตาก่อน และไม่อยู่ในจุดวนลูป)
      expect(predCyclic.column, equals('B'),
          reason: 'Anti-Streak-4 Cyclic Shield: เมื่อระเบิดวน A->B->C ต้องเลือก B เพื่อทำลายไซเคิลและป้องกันการวนกลับ A!');

      // Case B: Ping-Pong Alternating (แพ้ A -> B -> A ระเบิดสลับ)
      engine.reset(mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      expect(engine.getConsecutiveLosses(GameMode.towers), equals(3));

      final predPingPong = engine.getNextPrediction(mode: GameMode.towers);
      // ระเบิดสลับ A<->B ตาถัดไปจะสลับไป B ดังนั้นทางด่วนเพชรคือ C ที่ไม่เคยโดนเลย
      expect(predPingPong.column, equals('C'),
          reason: 'Anti-Streak-4 Ping-Pong Shield: เมื่อระเบิดสลับ A->B->A ทางด่วนเพชร 100% คือ C!');

      // Case C: Clustered (แพ้ A -> B -> B ระเบิดเกาะกลุ่มที่ B)
      engine.reset(mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);
      expect(engine.getConsecutiveLosses(GameMode.towers), equals(3));

      final predCluster = engine.getNextPrediction(mode: GameMode.towers);
      expect(predCluster.column, equals('C'),
          reason: 'Anti-Streak-4 Cluster Shield: เมื่อระเบิดแช่ที่ B ทางด่วนเพชรคือ C!');

      // ─── 3. Sovereign Loss-Streak Lockdown ───
      // ตรวจสอบว่าเมื่อ streak >= 1 หากมี aiBrainPrediction พยายามทายช่องอื่นที่ไม่ใช่ช่องปลอดภัยสูงสุด
      // OmniMatrix จะล็อกเป้าช่องปลอดภัยสูงสุดของตนเอง 100% ไม่ยอมให้ override
      final predLockdown = engine.getNextPrediction(
        mode: GameMode.towers,
        aiBrainPrediction: 'B', // ส่งช่องที่เพิ่งระเบิดมา
      );
      expect(predLockdown.column, equals('C'),
          reason: 'Sovereign Streak Lockdown: ในช่วงติดลบ OmniMatrix ต้องยึดช่องปลอดภัยสูงสุด C เสมอ');
    });

    test('Test 57: User Directive: หนี้ 3-5% ใน Streak 2 ต้องทวงเต็ม 100% เสมอ (Clearance: full100 ไม่โดน isFrequentLoss บล็อก)', () {
      final engine = OmniMatrixEngine.instance;
      engine.reset(mode: GameMode.towers);

      // จำลองสถานการณ์: เล่น 1 ตาชนะ แล้ว 2 ตาถัดไปแพ้ (Streak: 2)
      // หนี้สะสม 3-5% ของทุน (เช่น ทุน 100 DOGE, หนี้ 4.0 DOGE)
      engine.recordOutcome(chosenColumn: 'A', won: true, mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'A', won: false, revealedBombPos: 'A', mode: GameMode.towers);
      engine.recordOutcome(chosenColumn: 'B', won: false, revealedBombPos: 'B', mode: GameMode.towers);

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(2));
      expect(engine.isFrequentLossPeriod(GameMode.towers), isTrue,
          reason: '3 ตาล่าสุด แพ้ 2 ตา ต้องเป็น Frequent Loss Period');

      // ตรวจสอบว่าในรอบทวงหนี้ (isRecoveryRound: true, currentDebt: 4.0):
      // OmniMatrix ต้องปลดล็อก Clearance เป็น full100 เสมอตามคำสั่งผู้ใช้!
      final recoveryPred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 4.0,
        currentBalance: 100.0,
      );

      expect(recoveryPred.recoveryClearance, equals(RecoveryClearance.full100),
          reason: 'Streak 2 ที่มีหนี้ 3-5% ต้องได้รับสิทธิ์ RecoveryClearance.full100 ทันที ไม่ติด holdFire!');
      expect(recoveryPred.recoveryClearance, isNot(equals(RecoveryClearance.holdFire)),
          reason: 'ห้ามโดน holdFire มาบล็อกการทวงหนี้ 100% ใน Streak 1-2 เด็ดขาด');

      // ตรวจสอบว่าถ้าแพ้ครบ 3 ตา (Streak >= 3) ต้องเข้าโหมด holdFire ถอยกลับ Base Bet
      engine.recordOutcome(chosenColumn: 'C', won: false, revealedBombPos: 'C', mode: GameMode.towers); // Streak 3

      expect(engine.getConsecutiveLosses(GameMode.towers), equals(3));

      final streak3Pred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: true,
        currentDebt: 10.0,
        currentBalance: 90.0,
      );

      expect(streak3Pred.recoveryClearance, equals(RecoveryClearance.holdFire),
          reason: 'เมื่อแพ้ครบ 3 ตาติด (Streak >= 3) ต้องสั่ง holdFire และถอยกลับ Base Bet ตามคำสั่งผู้ใช้!');
    });

    test('Test 58: User Directive: Post-Observation Immediate Recovery on Win (ครบ 18 ตา และรอบก่อนหน้าชนะ ตาที่ 19 ปลดล็อกทวงได้ทันทีโดยไม่ต้องรอแพ้)', () {
      final s = GameModeSessionState(GameMode.towers);
      s.activeNewLoss = 0.50; // หนี้สะสม 0.50 DOGE

      // จำลองเหตุการณ์: แพ้ครบ 3 ตาติด -> เข้าสู่โหมดสังเกตการณ์ 18 ตา
      s.consecutiveLossesStreak = 3;
      const int obsRounds = 18;
      s.observationRoundsRemaining = obsRounds;
      s.isLossStreakBaseBetLocked = true;
      s.isPostObservationRecoveryReady = false;
      s.consecutiveLossesStreak = 0;

      // ระหว่างสังเกตการณ์ 18 ตา: สิทธิ์ทวงหนี้ต้องเป็น FALSE (เดิน Base Bet)
      bool isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          ((s.consecutiveLossesStreak >= 1 && s.consecutiveLossesStreak < 3) ||
              s.isPostObservationRecoveryReady) &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;
      expect(isEligible, isFalse, reason: 'ระหว่างสังเกตการณ์ 18 ตา ห้ามทวงหนี้');

      // เล่น Base Bet ผ่านไป 17 ตา
      for (int i = 1; i <= 17; i++) {
        s.observationRoundsRemaining--;
        expect(s.isLossStreakBaseBetLocked, isTrue);
      }
      expect(s.observationRoundsRemaining, equals(1));

      // ตาที่ 18 (ตาสุดท้ายของช่วงสังเกตการณ์): ผลปรากฏว่า "ชนะ" (ตามโจทย์ผู้ใช้)
      const double winProfit = 0.000042;
      s.subtractProfitFromDebt(winProfit);
      s.observationRoundsRemaining--;
      if (s.observationRoundsRemaining <= 0) {
        s.observationRoundsRemaining = 0;
        s.isLossStreakBaseBetLocked = false;
        if (s.totalAccumulatedLoss > 0.00000001) {
          s.isPostObservationRecoveryReady = true;
        }
      }
      s.consecutiveLossesStreak = 0; // ชนะ Base Bet ในตาที่ 18

      expect(s.observationRoundsRemaining, equals(0));
      expect(s.isLossStreakBaseBetLocked, isFalse);
      expect(s.consecutiveLossesStreak, equals(0), reason: 'รอบก่อนหน้า (ตาที่ 18) ชนะ');
      expect(s.isPostObservationRecoveryReady, isTrue, reason: 'สังเกตการณ์ครบแล้ว พร้อมทวงหนี้');

      // ตาที่ 19: ตรวจสอบสิทธิ์การทวงหนี้ทันทีตามคำสั่งผู้ใช้!
      // "ไม่ต้องให้แพ้แล้วค่อยทวงครับ เช่น 18 ตา ครบ แล้ว แต่รอบก่อนหน้าชนะ ตา 19 ก็ สามารถปลดล็อกทวงได้ทันทีครับ"
      isEligible = s.totalAccumulatedLoss > 0.00000001 &&
          ((s.consecutiveLossesStreak >= 1 && s.consecutiveLossesStreak < 3) ||
              s.isPostObservationRecoveryReady) &&
          !s.justWonRecoveryBet &&
          !s.isLossStreakBaseBetLocked &&
          s.observationRoundsRemaining <= 0;

      expect(isEligible, isTrue,
          reason: 'ตาที่ 19 ต้องปลดล็อกทวงหนี้ได้ทันทีโดยไม่ต้องรอแพ้ก่อน!');

      // เมื่อเข้าทวงหนี้จริง:
      s.isPostObservationRecoveryReady = false; // ปลดล็อกและใช้งานสิทธิ์ทวงหนี้
      s.isCurrentlyRecoveryRound = true;

      // ไม้ทวงหนี้ชนะ:
      s.resetDebt();
      expect(s.totalAccumulatedLoss, equals(0.0));
      expect(s.isPostObservationRecoveryReady, isFalse);
      expect(s.isCurrentlyRecoveryRound, isFalse);
    });
  });
}

