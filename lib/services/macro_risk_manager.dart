import 'dart:math';

class MacroRiskManager {
  MacroRiskManager._privateConstructor();
  static final MacroRiskManager instance = MacroRiskManager._privateConstructor();

  final List<RoundData> _recentRounds = [];
  final int maxRoundsToKeep = 100;

  int _currentLossThreshold = 0;
  int _lossesSinceLastBreak = 0;
  int _pendingBreakMinutes = 0;

  void recordRound(bool isWin, double currentBalance) {
    _recentRounds.add(RoundData(isWin: isWin, balance: currentBalance));
    if (_recentRounds.length > maxRoundsToKeep) {
      _recentRounds.removeAt(0);
    }

    // V49.0: Randomized Break Threshold
    if (isWin) {
      _currentLossThreshold = 0;
      _lossesSinceLastBreak = 0;
      _pendingBreakMinutes = 0;
    } else {
      _lossesSinceLastBreak++;
      
      if (_currentLossThreshold == 0) {
        // Randomly pick a threshold of 2, 3, or 4 losses
        _currentLossThreshold = 2 + Random().nextInt(3); 
      }

      if (_lossesSinceLastBreak >= _currentLossThreshold) {
        _pendingBreakMinutes = _currentLossThreshold; // e.g. pause for 2, 3, or 4 mins
        _lossesSinceLastBreak = 0; // Reset to wait for the next N losses
        _currentLossThreshold = 0; // Pick a new random threshold next time
      }
    }
  }

  double calculateHostilityIndex() {
    if (_recentRounds.isEmpty) return 0.0;
    
    int wins = _recentRounds.where((r) => r.isWin).length;
    double winRate = wins / _recentRounds.length;
    double theoreticalWinRate = 0.6667;
    
    if (winRate >= theoreticalWinRate) return 0.0;
    if (_recentRounds.length < 10) return 0.0;
    
    return (theoreticalWinRate - winRate) / theoreticalWinRate;
  }

  int getBreakDurationMinutes() {
    double hostility = calculateHostilityIndex();
    
    // Check if a randomized break was triggered by recordRound
    if (_pendingBreakMinutes > 0) {
      int breakTime = _pendingBreakMinutes;
      _pendingBreakMinutes = 0; // Consume the break
      return breakTime;
    }
    
    // Fallback: If hostility is very high but not a direct streak, take a 5 min break
    if (hostility > 0.5) return 5;
    
    return 0; // No break needed
  }

  bool shouldTakeBreak() {
    return getBreakDurationMinutes() > 0;
  }

  bool isSafeToRecover() {
    double hostility = calculateHostilityIndex();
    // If hostility is > 0.3 (win rate dropped significantly), it is unsafe to escalate bets.
    return hostility <= 0.3;
  }

  void clearHistory() {
    _recentRounds.clear();
    _currentLossThreshold = 0;
    _lossesSinceLastBreak = 0;
    _pendingBreakMinutes = 0;
  }
}

class RoundData {
  final bool isWin;
  final double balance;
  RoundData({required this.isWin, required this.balance});
}
