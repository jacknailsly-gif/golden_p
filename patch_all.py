import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add missing methods
missing_methods = """
  Map<GameMode, DateTime?> _breakEndTimeByMode = {};

  bool isBreakActiveFor(GameMode mode) {
    final endTime = _breakEndTimeByMode[mode];
    if (endTime == null) return false;
    if (DateTime.now().isAfter(endTime)) {
      _breakEndTimeByMode[mode] = null;
      return false;
    }
    return true;
  }

  bool get isBreakActive => _isBreakActive || isBreakActiveFor(_activeGameMode);

  Duration getBreakRemainingDuration(GameMode mode) {
    final endTime = _breakEndTimeByMode[mode];
    if (endTime == null) return Duration.zero;
    final diff = endTime.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String getBreakRemainingFormatted(GameMode mode) {
    final d = getBreakRemainingDuration(mode);
    return "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  void cancelBreak({required GameMode mode}) {
    _breakEndTimeByMode[mode] = null;
    notifyListeners();
  }

  double getStopProfitPercent(GameMode mode) => _stopProfitPercent;
  bool isStopProfitEnabledFor(GameMode mode) => _isStopProfitEnabled;
  void setStopProfitEnabled(bool val, {required GameMode mode}) {
    _isStopProfitEnabled = val;
    notifyListeners();
  }
  void setStopProfitPercent(double val, {required GameMode mode}) {
    _stopProfitPercent = val;
    notifyListeners();
  }
"""

content = content.replace("bool get isBreakActive => _isBreakActive;", missing_methods, 1)

# Remove the old stop profit methods (the ones without the mode param)
content = re.sub(r"  bool get isStopProfitEnabled => _isStopProfitEnabled;\n", "", content)
content = re.sub(r"  double get stopProfitPercent => _stopProfitPercent;\n", "", content)
content = re.sub(r"  void setStopProfitEnabled\(bool val\) \{.*?\n  \}\n", "", content, flags=re.DOTALL)
content = re.sub(r"  void setStopProfitPercent\(double val\) \{.*?\n  \}\n", "", content, flags=re.DOTALL)


# 2. Fix maxRecoveryStepsThisCycle to always be 1
content = re.sub(
    r"int maxRecoveryStepsThisCycle = 2;.*?\n  }",
    """int maxRecoveryStepsThisCycle = 1;
  double savedScrollY = 0.0;

  int randomizeRecoveryQuota({int? fixedForTest}) {
    maxRecoveryStepsThisCycle = 1;
    return 1;
  }""",
    content,
    flags=re.DOTALL
)

# 3. Fix _detectVisualOutcome condition order
content = content.replace('''
          if (state.observationRoundsRemaining > 0) {
            state.observationRoundsRemaining--;
''', '''
          if (state.consecutiveLossesStreak >= 3) {
            // FORCE OBSERVATION IMMEDIATELY! Do not let it process observation decrement!
            state.recoveryStepInCycle = 0;
            state.isLossStreakBaseBetLocked = true;
            state.isCurrentlyRecoveryRound = false;
            final int obsRounds = 3 + Random().nextInt(3);
            state.observationRoundsRemaining = state.observationRoundsRemaining > obsRounds ? state.observationRoundsRemaining : obsRounds;
            state.currentRecoveryCycle = 2;
            transitionRecoveryState(mode, RecoveryState.observation, reason: 'Normal Base Bet lost 3 consecutive times -> FORCE Observation');
          }

          if (state.observationRoundsRemaining > 0) {
            state.observationRoundsRemaining--;
''')

# Remove the old `else if (state.consecutiveLossesStreak >= 3)` block
content = re.sub(
    r"\} else if \(state\.consecutiveLossesStreak >= 3\) \{.*?await _ensureBaseBet\(runToken, mode: mode\);",
    "} else if (false) {",
    content,
    flags=re.DOTALL
)


with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
