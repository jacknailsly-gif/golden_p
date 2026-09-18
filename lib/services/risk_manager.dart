import 'dart:math';
import 'package:flutter/foundation.dart';

class DynamicRiskManager {
  final double baseBetFloor;
  final double recoveryMultiplier; // Payout multiplier e.g. 0.47
  final double hardStopLossBalance;
  final double targetProfitLimit;

  double _totalAccumulatedDebt = 0.0;
  double _sessionStartBalance = 0.0;

  DynamicRiskManager({
    this.baseBetFloor = 0.000009,
    this.recoveryMultiplier = 0.47,
    this.hardStopLossBalance = 0.01,
    this.targetProfitLimit = 50.0,
  });

  void initializeSession(double initialBalance) {
    _sessionStartBalance = initialBalance;
    _totalAccumulatedDebt = 0.0;
  }

  void recordWin(double betAmount) {
    double profit = betAmount * recoveryMultiplier;
    _totalAccumulatedDebt = max(0.0, _totalAccumulatedDebt - profit);
    debugPrint('[RISK MANAGER] 🌟 Win! Debt remaining: ${_totalAccumulatedDebt.toStringAsFixed(8)}');
  }

  void recordLoss(double betAmount) {
    _totalAccumulatedDebt += betAmount;
    debugPrint('[RISK MANAGER] 🚨 Loss! Total Debt: ${_totalAccumulatedDebt.toStringAsFixed(8)}');
  }

  /// Calculates next bet size (1-Shot 100% Full Recovery with Safety Bounds)
  double calculateNextBet(double currentBalance, int consecutiveLosses) {
    // 1. Check Hard Stop-Loss
    if (currentBalance <= hardStopLossBalance) {
      debugPrint('[RISK MANAGER 🛑] Hard Stop-Loss triggered! Balance below safety floor.');
      return 0.0;
    }

    // 2. Dynamic Base Bet (0.001% of balance)
    double dynamicBase = max(currentBalance * 0.00001, baseBetFloor);

    // 3. If no debt -> Base Bet
    if (_totalAccumulatedDebt <= 0.00000001) {
      return dynamicBase;
    }

    // 4. 1-Shot 100% Full Debt Recovery
    double targetProfit = _totalAccumulatedDebt + (dynamicBase * recoveryMultiplier);
    double recoveryBet = targetProfit / recoveryMultiplier;

    // 5. Never bet more than 90% of current balance
    if (recoveryBet > currentBalance * 0.90) {
      debugPrint('[RISK MANAGER ⚠️] Recovery bet exceeded 90% capital buffer. Clamped.');
      recoveryBet = currentBalance * 0.90;
    }

    return recoveryBet;
  }
}
