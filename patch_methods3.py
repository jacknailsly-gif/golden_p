import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Remove the duplicates I just added!
content = re.sub(r"  double getStopProfitPercent.*?notifyListeners\(\);\n  \}", "", content, flags=re.DOTALL)

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
