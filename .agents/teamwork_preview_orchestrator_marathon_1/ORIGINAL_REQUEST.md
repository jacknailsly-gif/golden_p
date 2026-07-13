# Original User Request

## 2026-06-14T14:08:39Z

Implement a "Marathon Session with Target-Based Auto-Stop" feature for the `golden_p` prediction bot. The bot must run continuously (long play) and only stop automatically when the user's pre-configured profit target (set in the analytics/settings page) is reached. When the target is hit, the bot must fully stop and wait for the user to manually restart.

Working directory: `c:/Users/Admin N/Desktop/golden_p`
Integrity mode: development

## Context
The app already has a Circuit Breaker that halts auto-play after 3 consecutive losses (reloads WebView and stops). The user has an existing analytics page where they can set their own profit target. The new feature must integrate with these existing systems.

## Requirements

### R1. Target-Based Auto-Stop (Take Profit)
When the bot detects that the user's current session profit has reached or exceeded their pre-configured target amount, the bot must automatically stop the auto-play loop, display a clear success message, and wait for the user to manually press Start to begin a new session.

### R2. Marathon Resilience (Auto-Resume after Circuit Breaker)
Currently, the Circuit Breaker stops the bot after 3 consecutive losses. For marathon mode, after the Circuit Breaker fires and the WebView reloads, the bot should automatically resume play after a short cooldown period (e.g., 10-30 seconds) instead of requiring manual restart — UNLESS the profit target has already been reached (R1).

### R3. Session Tracking
Track and display the current session's profit/loss in real-time so the user can see progress toward their target at all times.

## Acceptance Criteria

### Testing & Verification
- [ ] A dart test file (`test/marathon_session_test.dart`) is created and passes via `flutter test`.
- [ ] The test asserts that when simulated balance reaches or exceeds the target, the bot's stop flag is set to true.
- [ ] The test asserts that after a Circuit Breaker event, the bot auto-resumes if the target has NOT been met.
- [ ] The test asserts that after a Circuit Breaker event, the bot does NOT resume if the target HAS been met.
- [ ] Code modifications do not introduce any Dart/Flutter compilation errors.
- [ ] The team produces a final Markdown report (`audit_report.md`) describing the implementation.
