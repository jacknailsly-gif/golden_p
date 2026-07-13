## 2026-06-14T04:43:54Z
Your working directory is: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_anti_tracking_m3
Your identity: Codebase Worker (R3 Test Suite).
Your task:
Write a robust test suite in `test/anti_tracking_test.dart` to verify (A) the bot's outputs contain enough entropy to evade tracking, and (B) under no simulated circumstance does the bot register 4 consecutive losses.

Specifically, implement:
1. A stateful mock controller `HostileCasinoWebViewController` that extends `Fake` and implements `InAppWebViewController`. It must intercept `evaluateJavascript` to return balances, simulate button states for `'M0'`, and handle clicks to update simulated outcomes ('bomb' vs 'diamond'). The mock must support a "hostile/sniping" mode where it detects the bot's choices and deliberately places bombs to cheat/induce losses, simulating an adversarial server.
2. A test case that executes the autoplay prediction loop (e.g. `OverlayButtonsViewModel._executeSmartFlow`) for at least 50-100 rounds with speed multiplier set high (e.g. 1000.0) to avoid real delays.
3. Shannon Entropy verification: calculate the Shannon Entropy of the bot's box choices over the run and assert that it exceeds 1.2 (where log2(3) ≈ 1.58 is maximum entropy). Also verify that transition probabilities do not show a repetitive pattern (e.g. transition prob of any specific box sequence is < 0.35).
4. Strict 3-Loss circuit breaker verification: simulate the bot playing against the hostile sniping server that forces losses. Assert that after the 3rd consecutive loss:
   - The bot reloads the WebView (reload count increments in the mock).
   - The bot halts auto-play (the loop terminates, `_isRunning` becomes false, `_stopReason` is updated).
   - Recovery losses are capped (never reach 4, and the bot never sends a 4th click to start a bet).
5. Ensure the test file compiles and runs cleanly using `flutter test test/anti_tracking_test.dart`.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Write your handoff report to handoff.md in your working directory and notify the parent orchestrator when complete.
