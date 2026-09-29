import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

# 1. Add back missing methods
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

  double getStopProfitPercent(GameMode mode) => getState(mode).stopProfitPercent ?? 5.0;
  bool isStopProfitEnabledFor(GameMode mode) => getState(mode).isStopProfitEnabled ?? false;
  void setStopProfitEnabled(bool val, {required GameMode mode}) {
    getState(mode).isStopProfitEnabled = val;
    notifyListeners();
  }
  void setStopProfitPercent(double val, {required GameMode mode}) {
    getState(mode).stopProfitPercent = val;
    notifyListeners();
  }
"""
content = content.replace("bool get isBreakActive => _isBreakActive;", missing_methods)

# 2. Fix the `generatePostLossObservationRounds` to not have parameters and wait 3-5 rounds
content = content.replace(
    "final int obsRounds = state.generatePostLossObservationRounds();",
    "final int obsRounds = 3 + Random().nextInt(3); // 3-5 rounds"
)

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
