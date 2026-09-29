import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Remove all instances of the missing_methods block
block_pattern = r"  double getStopProfitPercent\(GameMode mode\).*?notifyListeners\(\);\n  \}"
content = re.sub(block_pattern, "", content, flags=re.DOTALL)

# Add it back EXACTLY ONCE
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

content = content.replace("  bool get is24HourMode => _is24HourMode;", missing_methods + "\n  bool get is24HourMode => _is24HourMode;", 1) # Only replace the FIRST occurrence!

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
