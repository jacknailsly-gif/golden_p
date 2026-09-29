import re

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("getState(mode).stopProfitPercent ?? 5.0;", "_stopProfitPercent;")
content = content.replace("getState(mode).isStopProfitEnabled ?? false;", "_isStopProfitEnabled;")
content = content.replace("getState(mode).isStopProfitEnabled = val;", "_isStopProfitEnabled = val;")
content = content.replace("getState(mode).stopProfitPercent = val;", "_stopProfitPercent = val;")

with open("lib/viewmodels/overlay_buttons_viewmodel.dart", "w", encoding="utf-8") as f:
    f.write(content)
