# BRIEFING — 2026-06-14T11:57:00Z

## Mission
Write a robust test suite in `test/anti_tracking_test.dart` to verify the bot's anti-tracking entropy and strict 3-loss circuit breaker behavior.

## 🔒 My Identity
- Archetype: Codebase Worker (R3 Test Suite)
- Roles: implementer, qa, specialist
- Working directory: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_anti_tracking_m3
- Original parent: 7143f613-bd3c-4317-be85-945728a1bf25
- Milestone: Anti-tracking Test Suite

## 🔒 Key Constraints
- Test suite must compile and run cleanly using `flutter test test/anti_tracking_test.dart`.
- Mock controller must extend Fake and implement InAppWebViewController, intercepting evaluateJavascript to mock balance, outcome, choices, and hostile sniping.
- Verify Shannon Entropy > 1.2 and transition probabilities < 0.35 over 50-100 rounds.
- Verify strict 3-loss circuit breaker: halts autoplay, reloads WebView, caps losses at 3.
- No hardcoded results, fake/facade implementations, or cheating.

## Current Parent
- Conversation ID: 7143f613-bd3c-4317-be85-945728a1bf25
- Updated: 2026-06-14T11:57:00Z

## Task Summary
- **What to build**: A unit and integration test suite verifying the anti-tracking features and circuit breaker in the bot.
- **Success criteria**: All tests pass under real execution, showing correct math and state transitions.
- **Interface contracts**: PROJECT.md

## Key Decisions Made
- Used stateful `HostileCasinoWebViewController` simulating the web interface, mapping unique button coordinates to distinguish markers in JS evaluation.
- Added `clearHistory()` to `MacroRiskManager` to reset the singleton state and avoid pollution between test cases.
- Implemented `MyHttpOverrides` in the test file to mock/bypass all package:http network requests instantly, preventing stalls.
- Scaled unscaled delays in `overlay_buttons_viewmodel.dart` by `_speedMultiplier`.

## Artifact Index
- `test/anti_tracking_test.dart` — The main test suite verifying entropy and circuit breaker logic.
