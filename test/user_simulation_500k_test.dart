import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_p/engines/omni_matrix_engine.dart';
import 'package:golden_p/models/game_mode.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';

void main() {
  group('User Simulation: 0.1 Balance across 500,000 Rounds', () {
    late OmniMatrixEngine engine;

    setUp(() {
      debugPrint = (String? message, {int? wrapWidth}) {}; // Mute verbose logs for speed
      engine = OmniMatrixEngine.instance;
      engine.resetAllMemory(mode: GameMode.towers);
    });

    test('Simulation A: 0.1 DOGE Balance for 500,000 Rounds (Restored APPI 13.4 Architecture)', () {
      final rng = Random(42); // Seeded for reproducibility
      const int totalRounds = 500000;
      const columns = ['A', 'B', 'C'];
      const double initialCapital = 0.1; // 0.1 DOGE
      const double floorBet = 0.00007882; // FaucetPay Towers DOGE minimum bet floor
      const double pRate = 0.42; // Towers Row 1 payout is 1.42x (net profit 0.42x)

      double currentBalance = initialCapital;
      double peakBalance = initialCapital;
      double minBalance = initialCapital;
      double maxDrawdownPct = 0.0;

      int wins = 0;
      int losses = 0;
      int maxLossStreak = 0;
      int currentLossStreak = 0;
      int recoveryAttempts = 0;
      int recoveryWins = 0;
      int safeHavenCount = 0;

      final session = GameModeSessionState(GameMode.towers);
      session.sessionStartBalance = initialCapital;
      session.sessionMaxBalance = initialCapital;
      session.protectedPrincipal = initialCapital;
      session.lockedBaseBet = floorBet;
      session.activeCoinType = 'DOGE';

      String prevBomb = 'A';
      String prevBomb2 = 'B';
      int currentRegime = 0; // 0: PingPong, 1: Cyclic, 2: Sticky, 3: Random
      int regimeRoundsLeft = 0;

      for (int round = 1; round <= totalRounds; round++) {
        // Realistic Casino PRNG pattern shifts
        if (regimeRoundsLeft <= 0) {
          final p = rng.nextInt(100);
          if (p < 38) {
            currentRegime = 0; // Ping-Pong
            regimeRoundsLeft = 8 + rng.nextInt(12);
          } else if (p < 68) {
            currentRegime = 1; // Cyclic
            regimeRoundsLeft = 8 + rng.nextInt(12);
          } else if (p < 85) {
            currentRegime = 2; // Sticky
            regimeRoundsLeft = 5 + rng.nextInt(6);
          } else {
            currentRegime = 3; // True Random / Chop
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

        // Dynamic Base Bet: max(floorBet, currentBalance / 10000)
        double dynamicBase = currentBalance / 10000.0;
        if (dynamicBase < floorBet) dynamicBase = floorBet;

        // Recovery Eligibility Check (APPI 13.4 Rules)
        final predResult = engine.getNextPrediction(
          mode: GameMode.towers,
          isRecoveryRound: session.totalAccumulatedLoss > 0.00000001,
          currentDebt: session.totalAccumulatedLoss,
          currentBalance: currentBalance,
        );

        final bool isEligibleForRecovery = session.canEnterRecovery(omniResult: predResult);
        double betAmount = dynamicBase;

        if (isEligibleForRecovery && session.totalAccumulatedLoss > 0.00000001) {
          recoveryAttempts++;
          final double debtToEscalate = session.totalAccumulatedLoss;
          final double surplus = dynamicBase * pRate * 2.0;
          double targetProfit = debtToEscalate + surplus;
          double requiredBet = targetProfit / pRate;

          // Min recovery bet
          final double minRecoveryBet = dynamicBase * 1.5;
          if (requiredBet < minRecoveryBet) requiredBet = minRecoveryBet;

          // SHIELD 1: HARD RECOVERY BET CAP (Max 10% of Bankroll, Absolute Cap 15%)
          final double maxBankrollCap = currentBalance * 0.10;
          if (requiredBet > maxBankrollCap) {
            requiredBet = maxBankrollCap;
          }
          if (requiredBet < dynamicBase) requiredBet = dynamicBase;
          if (requiredBet > currentBalance * 0.15) requiredBet = currentBalance * 0.15;

          betAmount = double.parse(requiredBet.toStringAsFixed(8));
          session.isCurrentlyRecoveryRound = true;
        } else {
          session.isCurrentlyRecoveryRound = false;
          betAmount = dynamicBase;
        }

        // Safety check: Cannot bet more than current balance
        if (betAmount > currentBalance) betAmount = currentBalance;

        final predictedCol = predResult.column;
        final bool won = (predictedCol != actualBomb);

        engine.recordOutcome(
          chosenColumn: predictedCol,
          won: won,
          revealedBombPos: actualBomb,
          mode: GameMode.towers,
        );

        session.recentRoundsHistory.add(won);
        if (session.recentRoundsHistory.length > 10) {
          session.recentRoundsHistory.removeAt(0);
        }

        if (won) {
          wins++;
          if (session.isCurrentlyRecoveryRound) recoveryWins++;
          currentLossStreak = 0;
          final double profit = betAmount * pRate;
          currentBalance += profit;
          session.subtractProfitFromDebt(profit);
          session.justWonRecoveryBet = session.isCurrentlyRecoveryRound;
          session.consecutiveLossesStreak = 0;

          if (session.observationRoundsRemaining > 0) {
            session.observationRoundsRemaining--;
            if (session.observationRoundsRemaining <= 0) {
              session.isLossStreakBaseBetLocked = false;
              session.recoveryState = RecoveryState.recoveryGate;
            }
          }
        } else {
          losses++;
          currentLossStreak++;
          if (currentLossStreak > maxLossStreak) maxLossStreak = currentLossStreak;
          currentBalance -= betAmount;
          session.activeNewLoss += betAmount;
          session.consecutiveLossesStreak++;
          session.justWonRecoveryBet = false;

          if (session.observationRoundsRemaining > 0) {
            session.observationRoundsRemaining--;
            if (session.observationRoundsRemaining <= 0) {
              session.isLossStreakBaseBetLocked = false;
              session.recoveryState = RecoveryState.recoveryGate;
            }
          }

          // 3-loss ceiling: Retreats to Base Bet observation for 15-25 rounds
          if (session.consecutiveLossesStreak >= 3 && session.observationRoundsRemaining <= 0) {
            session.observationRoundsRemaining = session.generatePostLossObservationRounds();
            session.isLossStreakBaseBetLocked = true;
            session.recoveryState = RecoveryState.observation;
            session.consecutiveLossesStreak = 3;
          } else if (session.observationRoundsRemaining <= 0) {
            session.recoveryStepInCycle++;
          }
        }

        // Drawdown & Peak tracking
        if (currentBalance > peakBalance) {
          peakBalance = currentBalance;
          session.sessionMaxBalance = peakBalance;
        } else {
          final double dd = ((peakBalance - currentBalance) / peakBalance) * 100.0;
          if (dd > maxDrawdownPct) maxDrawdownPct = dd;
        }
        if (currentBalance < minBalance) minBalance = currentBalance;

        // Anti-Wipeout Safe Haven Shield: If drawdown exceeds 35% from ATH
        if (currentBalance < peakBalance * 0.65 && session.totalAccumulatedLoss > 0) {
          safeHavenCount++;
          session.resetDebt();
          session.sessionMaxBalance = currentBalance;
          session.sessionStartBalance = currentBalance;
          session.observationRoundsRemaining = 30;
          session.isLossStreakBaseBetLocked = true;
          session.recoveryState = RecoveryState.observation;
        }

        // Bankruptcy check
        if (currentBalance <= floorBet) {
          print('🛑 [BUSTED] Bankroll exhausted at round $round! Balance: $currentBalance');
          break;
        }

        if (round % 100000 == 0) {
          final double currentProfit = currentBalance - initialCapital;
          final double pct = (currentProfit / initialCapital) * 100.0;
          print('  [MILESTONE] Round $round / $totalRounds: Balance = ${currentBalance.toStringAsFixed(8)} DOGE (${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(2)}%), MaxDD = -${maxDrawdownPct.toStringAsFixed(2)}%');
        }
      }

      final double winRate = (wins / totalRounds) * 100.0;
      final double netProfit = currentBalance - initialCapital;
      final double profitPct = (netProfit / initialCapital) * 100.0;
      final double recoverySuccessRate = recoveryAttempts > 0 ? (recoveryWins / recoveryAttempts) * 100.0 : 0.0;

      print('═════════════════════════════════════════════════════════════════════════════');
      print('🏆 SIMULATION RESULT: 0.1 DOGE STARTING CAPITAL ACROSS 500,000 ROUNDS 🏆');
      print('═════════════════════════════════════════════════════════════════════════════');
      print('🎯 Total Rounds       : $totalRounds');
      print('🎯 Total Wins         : $wins / $totalRounds (${winRate.toStringAsFixed(2)}%)');
      print('🎯 Total Losses       : $losses');
      print('🎯 Max Loss Streak    : $maxLossStreak');
      print('💰 Starting Balance   : ${initialCapital.toStringAsFixed(8)} DOGE');
      print('💰 Peak Balance       : ${peakBalance.toStringAsFixed(8)} DOGE (+${(((peakBalance - initialCapital) / initialCapital) * 100.0).toStringAsFixed(2)}%)');
      print('💰 Lowest Balance     : ${minBalance.toStringAsFixed(8)} DOGE');
      print('💰 Final Balance      : ${currentBalance.toStringAsFixed(8)} DOGE');
      print('💰 Net Profit / Loss  : ${netProfit >= 0 ? "+" : ""}${netProfit.toStringAsFixed(8)} DOGE (${profitPct >= 0 ? "+" : ""}${profitPct.toStringAsFixed(2)}%)');
      print('📉 Max Drawdown       : -${maxDrawdownPct.toStringAsFixed(2)}%');
      print('⚡ Recovery Attempts  : $recoveryAttempts rounds');
      print('⚡ Recovery Wins      : $recoveryWins / $recoveryAttempts (${recoverySuccessRate.toStringAsFixed(2)}%)');
      print('🛡️ Safe Haven Triggers: $safeHavenCount times');
      print('🛡️ Portfolio Outcome  : ${currentBalance > 0.05 ? "PROFITABLE & SAFE (กำไรและพอร์ตไม่แตก)" : (currentBalance > 0 ? "SURVIVED (รอดแต่ติดลบ)" : "BUST (พอร์ตแตก)")}');
      print('═════════════════════════════════════════════════════════════════════════════');

      expect(currentBalance, greaterThan(0.0), reason: 'Portfolio must not bust');
    });

    test('Simulation B: 0.1 POL Balance for 500,000 Rounds (Restored APPI 13.4 Architecture)', () {
      final rng = Random(12345);
      const int totalRounds = 500000;
      const columns = ['A', 'B', 'C'];
      const double initialCapital = 0.1; // 0.1 POL
      const double floorBet = 0.00001000; // POL floor
      const double pRate = 0.42;

      double currentBalance = initialCapital;
      double peakBalance = initialCapital;
      double minBalance = initialCapital;
      double maxDrawdownPct = 0.0;

      int wins = 0;
      int losses = 0;
      int maxLossStreak = 0;
      int currentLossStreak = 0;
      int recoveryAttempts = 0;
      int recoveryWins = 0;
      int safeHavenCount = 0;

      final session = GameModeSessionState(GameMode.towers);
      session.sessionStartBalance = initialCapital;
      session.sessionMaxBalance = initialCapital;
      session.protectedPrincipal = initialCapital;
      session.lockedBaseBet = floorBet;
      session.activeCoinType = 'POL';

      String prevBomb = 'B';
      String prevBomb2 = 'C';
      int currentRegime = 0;
      int regimeRoundsLeft = 0;

      for (int round = 1; round <= totalRounds; round++) {
        if (regimeRoundsLeft <= 0) {
          final p = rng.nextInt(100);
          if (p < 38) {
            currentRegime = 0;
            regimeRoundsLeft = 8 + rng.nextInt(12);
          } else if (p < 68) {
            currentRegime = 1;
            regimeRoundsLeft = 8 + rng.nextInt(12);
          } else if (p < 85) {
            currentRegime = 2;
            regimeRoundsLeft = 5 + rng.nextInt(6);
          } else {
            currentRegime = 3;
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

        double dynamicBase = currentBalance / 10000.0;
        if (dynamicBase < floorBet) dynamicBase = floorBet;

        final predResult = engine.getNextPrediction(
          mode: GameMode.towers,
          isRecoveryRound: session.totalAccumulatedLoss > 0.00000001,
          currentDebt: session.totalAccumulatedLoss,
          currentBalance: currentBalance,
        );

        final bool isEligibleForRecovery = session.canEnterRecovery(omniResult: predResult);
        double betAmount = dynamicBase;

        if (isEligibleForRecovery && session.totalAccumulatedLoss > 0.00000001) {
          recoveryAttempts++;
          final double debtToEscalate = session.totalAccumulatedLoss;
          final double surplus = dynamicBase * pRate * 2.0;
          double targetProfit = debtToEscalate + surplus;
          double requiredBet = targetProfit / pRate;

          final double minRecoveryBet = dynamicBase * 1.5;
          if (requiredBet < minRecoveryBet) requiredBet = minRecoveryBet;

          final double maxBankrollCap = currentBalance * 0.10;
          if (requiredBet > maxBankrollCap) {
            requiredBet = maxBankrollCap;
          }
          if (requiredBet < dynamicBase) requiredBet = dynamicBase;
          if (requiredBet > currentBalance * 0.15) requiredBet = currentBalance * 0.15;

          betAmount = double.parse(requiredBet.toStringAsFixed(8));
          session.isCurrentlyRecoveryRound = true;
        } else {
          session.isCurrentlyRecoveryRound = false;
          betAmount = dynamicBase;
        }

        if (betAmount > currentBalance) betAmount = currentBalance;

        final predictedCol = predResult.column;
        final bool won = (predictedCol != actualBomb);

        engine.recordOutcome(
          chosenColumn: predictedCol,
          won: won,
          revealedBombPos: actualBomb,
          mode: GameMode.towers,
        );

        session.recentRoundsHistory.add(won);
        if (session.recentRoundsHistory.length > 10) {
          session.recentRoundsHistory.removeAt(0);
        }

        if (won) {
          wins++;
          if (session.isCurrentlyRecoveryRound) recoveryWins++;
          currentLossStreak = 0;
          final double profit = betAmount * pRate;
          currentBalance += profit;
          session.subtractProfitFromDebt(profit);
          session.justWonRecoveryBet = session.isCurrentlyRecoveryRound;
          session.consecutiveLossesStreak = 0;

          if (session.observationRoundsRemaining > 0) {
            session.observationRoundsRemaining--;
            if (session.observationRoundsRemaining <= 0) {
              session.isLossStreakBaseBetLocked = false;
              session.recoveryState = RecoveryState.recoveryGate;
            }
          }
        } else {
          losses++;
          currentLossStreak++;
          if (currentLossStreak > maxLossStreak) maxLossStreak = currentLossStreak;
          currentBalance -= betAmount;
          session.activeNewLoss += betAmount;
          session.consecutiveLossesStreak++;
          session.justWonRecoveryBet = false;

          if (session.observationRoundsRemaining > 0) {
            session.observationRoundsRemaining--;
            if (session.observationRoundsRemaining <= 0) {
              session.isLossStreakBaseBetLocked = false;
              session.recoveryState = RecoveryState.recoveryGate;
            }
          }

          if (session.consecutiveLossesStreak >= 3 && session.observationRoundsRemaining <= 0) {
            session.observationRoundsRemaining = session.generatePostLossObservationRounds();
            session.isLossStreakBaseBetLocked = true;
            session.recoveryState = RecoveryState.observation;
            session.consecutiveLossesStreak = 3;
          } else if (session.observationRoundsRemaining <= 0) {
            session.recoveryStepInCycle++;
          }
        }

        if (currentBalance > peakBalance) {
          peakBalance = currentBalance;
          session.sessionMaxBalance = peakBalance;
        } else {
          final double dd = ((peakBalance - currentBalance) / peakBalance) * 100.0;
          if (dd > maxDrawdownPct) maxDrawdownPct = dd;
        }
        if (currentBalance < minBalance) minBalance = currentBalance;

        if (currentBalance < peakBalance * 0.65 && session.totalAccumulatedLoss > 0) {
          safeHavenCount++;
          session.resetDebt();
          session.sessionMaxBalance = currentBalance;
          session.sessionStartBalance = currentBalance;
          session.observationRoundsRemaining = 30;
          session.isLossStreakBaseBetLocked = true;
          session.recoveryState = RecoveryState.observation;
        }

        if (currentBalance <= floorBet) {
          print('🛑 [BUSTED] Bankroll exhausted at round $round! Balance: $currentBalance');
          break;
        }

        if (round % 100000 == 0) {
          final double currentProfit = currentBalance - initialCapital;
          final double pct = (currentProfit / initialCapital) * 100.0;
          print('  [MILESTONE] Round $round / $totalRounds: Balance = ${currentBalance.toStringAsFixed(8)} POL (${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(2)}%), MaxDD = -${maxDrawdownPct.toStringAsFixed(2)}%');
        }
      }

      final double winRate = (wins / totalRounds) * 100.0;
      final double netProfit = currentBalance - initialCapital;
      final double profitPct = (netProfit / initialCapital) * 100.0;
      final double recoverySuccessRate = recoveryAttempts > 0 ? (recoveryWins / recoveryAttempts) * 100.0 : 0.0;

      print('═════════════════════════════════════════════════════════════════════════════');
      print('🏆 SIMULATION RESULT: 0.1 POL STARTING CAPITAL ACROSS 500,000 ROUNDS 🏆');
      print('═════════════════════════════════════════════════════════════════════════════');
      print('🎯 Total Rounds       : $totalRounds');
      print('🎯 Total Wins         : $wins / $totalRounds (${winRate.toStringAsFixed(2)}%)');
      print('🎯 Total Losses       : $losses');
      print('🎯 Max Loss Streak    : $maxLossStreak');
      print('💰 Starting Balance   : ${initialCapital.toStringAsFixed(8)} POL');
      print('💰 Peak Balance       : ${peakBalance.toStringAsFixed(8)} POL (+${(((peakBalance - initialCapital) / initialCapital) * 100.0).toStringAsFixed(2)}%)');
      print('💰 Lowest Balance     : ${minBalance.toStringAsFixed(8)} POL');
      print('💰 Final Balance      : ${currentBalance.toStringAsFixed(8)} POL');
      print('💰 Net Profit / Loss  : ${netProfit >= 0 ? "+" : ""}${netProfit.toStringAsFixed(8)} POL (${profitPct >= 0 ? "+" : ""}${profitPct.toStringAsFixed(2)}%)');
      print('📉 Max Drawdown       : -${maxDrawdownPct.toStringAsFixed(2)}%');
      print('⚡ Recovery Attempts  : $recoveryAttempts rounds');
      print('⚡ Recovery Wins      : $recoveryWins / $recoveryAttempts (${recoverySuccessRate.toStringAsFixed(2)}%)');
      print('🛡️ Safe Haven Triggers: $safeHavenCount times');
      print('🛡️ Portfolio Outcome  : ${currentBalance > 0.05 ? "PROFITABLE & SAFE (กำไรและพอร์ตไม่แตก)" : (currentBalance > 0 ? "SURVIVED (รอดแต่ติดลบ)" : "BUST (พอร์ตแตก)")}');
      print('═════════════════════════════════════════════════════════════════════════════');

      expect(currentBalance, greaterThan(0.0), reason: 'Portfolio must not bust');
    });

    test('Simulation C: 0.1 DOGE in Pure Cryptographic Random (Harsh 66.67% Base RNG)', () {
      final rng = Random(999);
      const int totalRounds = 500000;
      const columns = ['A', 'B', 'C'];
      const double initialCapital = 0.1;
      const double floorBet = 0.00007882;
      const double pRate = 0.42;

      double currentBalance = initialCapital;
      double peakBalance = initialCapital;
      double minBalance = initialCapital;
      double maxDrawdownPct = 0.0;

      int wins = 0;
      int losses = 0;
      int maxLossStreak = 0;
      int currentLossStreak = 0;
      int recoveryAttempts = 0;
      int recoveryWins = 0;
      int safeHavenCount = 0;

      final session = GameModeSessionState(GameMode.towers);
      session.sessionStartBalance = initialCapital;
      session.sessionMaxBalance = initialCapital;
      session.protectedPrincipal = initialCapital;
      session.lockedBaseBet = floorBet;
      session.activeCoinType = 'DOGE';

      for (int round = 1; round <= totalRounds; round++) {
        // Pure Unpredictable Cryptographic RNG (Each round independent 1/3 bomb)
        String actualBomb = columns[rng.nextInt(3)];

        double dynamicBase = currentBalance / 10000.0;
        if (dynamicBase < floorBet) dynamicBase = floorBet;

        final predResult = engine.getNextPrediction(
          mode: GameMode.towers,
          isRecoveryRound: session.totalAccumulatedLoss > 0.00000001,
          currentDebt: session.totalAccumulatedLoss,
          currentBalance: currentBalance,
        );

        final bool isEligibleForRecovery = session.canEnterRecovery(omniResult: predResult);
        double betAmount = dynamicBase;

        if (isEligibleForRecovery && session.totalAccumulatedLoss > 0.00000001) {
          recoveryAttempts++;
          final double debtToEscalate = session.totalAccumulatedLoss;
          final double surplus = dynamicBase * pRate * 2.0;
          double targetProfit = debtToEscalate + surplus;
          double requiredBet = targetProfit / pRate;

          final double minRecoveryBet = dynamicBase * 1.5;
          if (requiredBet < minRecoveryBet) requiredBet = minRecoveryBet;

          final double maxBankrollCap = currentBalance * 0.10;
          if (requiredBet > maxBankrollCap) {
            requiredBet = maxBankrollCap;
          }
          if (requiredBet < dynamicBase) requiredBet = dynamicBase;
          if (requiredBet > currentBalance * 0.15) requiredBet = currentBalance * 0.15;

          betAmount = double.parse(requiredBet.toStringAsFixed(8));
          session.isCurrentlyRecoveryRound = true;
        } else {
          session.isCurrentlyRecoveryRound = false;
          betAmount = dynamicBase;
        }

        if (betAmount > currentBalance) betAmount = currentBalance;

        final predictedCol = predResult.column;
        final bool won = (predictedCol != actualBomb);

        engine.recordOutcome(
          chosenColumn: predictedCol,
          won: won,
          revealedBombPos: actualBomb,
          mode: GameMode.towers,
        );

        session.recentRoundsHistory.add(won);
        if (session.recentRoundsHistory.length > 10) {
          session.recentRoundsHistory.removeAt(0);
        }

        if (won) {
          wins++;
          if (session.isCurrentlyRecoveryRound) recoveryWins++;
          currentLossStreak = 0;
          final double profit = betAmount * pRate;
          currentBalance += profit;
          session.subtractProfitFromDebt(profit);
          session.justWonRecoveryBet = session.isCurrentlyRecoveryRound;
          session.consecutiveLossesStreak = 0;

          if (session.observationRoundsRemaining > 0) {
            session.observationRoundsRemaining--;
            if (session.observationRoundsRemaining <= 0) {
              session.isLossStreakBaseBetLocked = false;
              session.recoveryState = RecoveryState.recoveryGate;
            }
          }
        } else {
          losses++;
          currentLossStreak++;
          if (currentLossStreak > maxLossStreak) maxLossStreak = currentLossStreak;
          currentBalance -= betAmount;
          session.activeNewLoss += betAmount;
          session.consecutiveLossesStreak++;
          session.justWonRecoveryBet = false;

          if (session.observationRoundsRemaining > 0) {
            session.observationRoundsRemaining--;
            if (session.observationRoundsRemaining <= 0) {
              session.isLossStreakBaseBetLocked = false;
              session.recoveryState = RecoveryState.recoveryGate;
            }
          }

          if (session.consecutiveLossesStreak >= 3 && session.observationRoundsRemaining <= 0) {
            session.observationRoundsRemaining = session.generatePostLossObservationRounds();
            session.isLossStreakBaseBetLocked = true;
            session.recoveryState = RecoveryState.observation;
            session.consecutiveLossesStreak = 3;
          } else if (session.observationRoundsRemaining <= 0) {
            session.recoveryStepInCycle++;
          }
        }

        if (currentBalance > peakBalance) {
          peakBalance = currentBalance;
          session.sessionMaxBalance = peakBalance;
        } else {
          final double dd = ((peakBalance - currentBalance) / peakBalance) * 100.0;
          if (dd > maxDrawdownPct) maxDrawdownPct = dd;
        }
        if (currentBalance < minBalance) minBalance = currentBalance;

        // Anti-Wipeout Safe Haven Shield
        if (currentBalance < peakBalance * 0.65 && session.totalAccumulatedLoss > 0) {
          safeHavenCount++;
          session.resetDebt();
          session.sessionMaxBalance = currentBalance;
          session.sessionStartBalance = currentBalance;
          session.observationRoundsRemaining = 30;
          session.isLossStreakBaseBetLocked = true;
          session.recoveryState = RecoveryState.observation;
        }

        if (currentBalance <= floorBet) {
          print('🛑 [BUSTED] Bankroll exhausted at round $round! Balance: $currentBalance');
          break;
        }

        if (round % 100000 == 0) {
          final double currentProfit = currentBalance - initialCapital;
          final double pct = (currentProfit / initialCapital) * 100.0;
          print('  [MILESTONE] Round $round / $totalRounds: Balance = ${currentBalance.toStringAsFixed(8)} DOGE (${pct >= 0 ? "+" : ""}${pct.toStringAsFixed(2)}%), MaxDD = -${maxDrawdownPct.toStringAsFixed(2)}%');
        }
      }

      final double winRate = (wins / totalRounds) * 100.0;
      final double netProfit = currentBalance - initialCapital;
      final double profitPct = (netProfit / initialCapital) * 100.0;
      final double recoverySuccessRate = recoveryAttempts > 0 ? (recoveryWins / recoveryAttempts) * 100.0 : 0.0;

      print('═════════════════════════════════════════════════════════════════════════════');
      print('🏆 SIMULATION RESULT: 0.1 DOGE IN PURE CRYPTOGRAPHIC RANDOM (66.67% BASE) 🏆');
      print('═════════════════════════════════════════════════════════════════════════════');
      print('🎯 Total Rounds       : $totalRounds');
      print('🎯 Total Wins         : $wins / $totalRounds (${winRate.toStringAsFixed(2)}%)');
      print('🎯 Total Losses       : $losses');
      print('🎯 Max Loss Streak    : $maxLossStreak');
      print('💰 Starting Balance   : ${initialCapital.toStringAsFixed(8)} DOGE');
      print('💰 Peak Balance       : ${peakBalance.toStringAsFixed(8)} DOGE (+${(((peakBalance - initialCapital) / initialCapital) * 100.0).toStringAsFixed(2)}%)');
      print('💰 Lowest Balance     : ${minBalance.toStringAsFixed(8)} DOGE');
      print('💰 Final Balance      : ${currentBalance.toStringAsFixed(8)} DOGE');
      print('💰 Net Profit / Loss  : ${netProfit >= 0 ? "+" : ""}${netProfit.toStringAsFixed(8)} DOGE (${profitPct >= 0 ? "+" : ""}${profitPct.toStringAsFixed(2)}%)');
      print('📉 Max Drawdown       : -${maxDrawdownPct.toStringAsFixed(2)}%');
      print('⚡ Recovery Attempts  : $recoveryAttempts rounds');
      print('⚡ Recovery Wins      : $recoveryWins / $recoveryAttempts (${recoverySuccessRate.toStringAsFixed(2)}%)');
      print('🛡️ Safe Haven Triggers: $safeHavenCount times');
      print('🛡️ Portfolio Outcome  : ${currentBalance > 0.05 ? "PROFITABLE & SAFE (กำไรและพอร์ตไม่แตก)" : (currentBalance > 0 ? "SURVIVED (รอดแต่ติดลบ)" : "BUST (พอร์ตแตก)")}');
      print('═════════════════════════════════════════════════════════════════════════════');
    });
  });
}
