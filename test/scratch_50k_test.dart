import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  test('Verify 50,000 rounds 95-100% Win Rate and Zero Wipeout Profitability', () {
    debugPrint = (String? msg, {int? wrapWidth}) {};
    final engine = OmniMatrixEngine.instance;
    engine.resetAllMemory(mode: GameMode.towers);

    final sessionState = GameModeSessionState(GameMode.towers);
    sessionState.sessionStartBalance = 100.0;
    sessionState.sessionMaxBalance = 100.0;
    sessionState.lockedBaseBet = 0.001;

    final rng = Random(12345);
    const int totalRounds = 50000;
    const columns = ['A', 'B', 'C'];

    double currentBalance = 100.0;
    const double baseBet = 0.001;
    const double pRate = 0.42;

    int wins = 0;
    int losses = 0;
    int maxLossStreak = 0;
    int currentLossStreak = 0;
    double minBalance = currentBalance;
    double peakBalance = currentBalance;

    String prevBomb = 'A';
    String prevBomb2 = 'B';

    int currentRegime = 0;
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

      // Bet Sizing with Anti-Wipeout Hard Cap (12%) & Dynamic Slicing
      double betAmount = baseBet;
      final bool isRecovery = sessionState.canEnterRecovery();

      if (isRecovery && sessionState.totalAccumulatedLoss > 0.00000001) {
        final double maxSafeCap = currentBalance * 0.12;
        final double surplus = baseBet * pRate * 2.0;
        double debtToRecover = sessionState.totalAccumulatedLoss;
        final double maxDebtInSingleShot = (maxSafeCap * pRate) - surplus;
        if (debtToRecover > maxDebtInSingleShot && maxDebtInSingleShot > baseBet) {
          debtToRecover = sessionState.totalAccumulatedLoss * 0.40;
          if (debtToRecover > maxDebtInSingleShot) debtToRecover = maxDebtInSingleShot;
        }
        double requiredBet = (debtToRecover + surplus) / pRate;
        if (requiredBet > maxSafeCap) requiredBet = maxSafeCap;
        if (requiredBet < baseBet) requiredBet = baseBet;
        betAmount = requiredBet;
      } else {
        betAmount = baseBet;
      }

      final pred = engine.getNextPrediction(
        mode: GameMode.towers,
        isRecoveryRound: isRecovery,
        currentDebt: sessionState.totalAccumulatedLoss,
        currentBalance: currentBalance,
      );
      final bool won = (pred.column != actualBomb);
      engine.recordOutcome(chosenColumn: pred.column, won: won, revealedBombPos: actualBomb);

      if (won) {
        wins++;
        currentLossStreak = 0;
        final double profit = betAmount * pRate;
        currentBalance += profit;
        sessionState.subtractProfitFromDebt(profit);
        sessionState.justWonRecoveryBet = isRecovery;
        sessionState.consecutiveLossesStreak = 0;
        if (sessionState.observationRoundsRemaining > 0) {
          sessionState.observationRoundsRemaining--;
        }
      } else {
        losses++;
        currentLossStreak++;
        if (currentLossStreak > maxLossStreak) maxLossStreak = currentLossStreak;
        currentBalance -= betAmount;
        sessionState.activeNewLoss += betAmount;
        sessionState.consecutiveLossesStreak++;
        sessionState.justWonRecoveryBet = false;

        if (sessionState.consecutiveLossesStreak >= 3) {
          sessionState.observationRoundsRemaining = sessionState.generatePostLossObservationRounds();
          sessionState.isLossStreakBaseBetLocked = true;
          sessionState.recoveryState = RecoveryState.observation;
          sessionState.consecutiveLossesStreak = 3;
        } else {
          sessionState.recoveryStepInCycle++;
        }
      }

      if (currentBalance < minBalance) minBalance = currentBalance;
      if (currentBalance > peakBalance) peakBalance = currentBalance;
    }

    final double winRate = (wins / totalRounds) * 100.0;
    final double netProfit = currentBalance - 100.0;
    final double profitPct = (netProfit / 100.0) * 100.0;
    final double maxDrawdownPct = ((peakBalance - minBalance) / peakBalance) * 100.0;

    print('═══════════════════════════════════════════════════════════');
    print('🌟 50,000-ROUND STRESS TEST SIMULATION BENCHMARK 🌟');
    print('═══════════════════════════════════════════════════════════');
    print('🎯 Total Wins       : $wins / $totalRounds');
    print('🎯 Win Rate         : ${winRate.toStringAsFixed(2)}% (Target: 95.0% - 100.0%)');
    print('🛡️ Max Loss Streak  : $maxLossStreak');
    print('💰 Starting Balance : 100.00000000 DOGE');
    print('💰 Final Balance    : ${currentBalance.toStringAsFixed(8)} DOGE');
    print('💰 Net Profit       : +${netProfit.toStringAsFixed(8)} DOGE (+${profitPct.toStringAsFixed(2)}%)');
    print('📉 Max Drawdown     : -${maxDrawdownPct.toStringAsFixed(2)}%');
    print('🛡️ Portfolio Status : ${currentBalance > 0 ? "PASSED (พอรไม่แตก)" : "FAILED (BUST)"}');
    print('═══════════════════════════════════════════════════════════');

    expect(winRate, inInclusiveRange(95.0, 100.0));
    expect(currentBalance, greaterThan(80.0));
    expect(netProfit, greaterThan(0.0));
  });
}
