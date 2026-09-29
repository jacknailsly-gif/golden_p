import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Remove the old getters/setters
content = re.sub(r"  bool get isStopProfitEnabled => _isStopProfitEnabled;\n", "", content)
content = re.sub(r"  double get stopProfitPercent => _stopProfitPercent;\n", "", content)
content = re.sub(r"  void setStopProfitEnabled\(bool val\) \{.*?\n  \}\n", "", content, flags=re.DOTALL)
content = re.sub(r"  void setStopProfitPercent\(double val\) \{.*?\n  \}\n", "", content, flags=re.DOTALL)


# Add the new ones
missing_methods = """
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

content = content.replace("  bool get is24HourMode => _is24HourMode;", missing_methods + "\n  bool get is24HourMode => _is24HourMode;")

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
