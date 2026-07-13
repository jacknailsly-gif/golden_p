# Original User Request

## Initial Request — 2026-06-22T05:15:55Z

Verify the recent logic changes (V68.0 and V69.0) in the Towers game bot to ensure there are no logical errors, edge cases, or runtime crashes.

Working directory: c:\Users\Admin N\Desktop\golden_p
Integrity mode: development

## Requirements

### R1. Verify Pattern Toggle Logic
Review the codebase to confirm that the fixed pattern correctly switches between `BCBC` and `ACAC` on EVERY single loss. Ensure the toggle logic is robust and doesn't get stuck.

### R2. Verify Recovery Strategy Toggle Logic
Review the implementation of the dual recovery strategy. Confirm that when a recovery bet loses, the strategy immediately switches between Strategy 1 (Stall 3-5 rounds) and Strategy 2 (Wait for Win) without relying on time-based timers.

### R3. General Code Review & Error Checking
Perform a comprehensive code review of `_executeSmartFlow` and the loss/win branches in `lib/viewmodels/overlay_buttons_viewmodel.dart`. Identify any potential edge cases, infinite loops, variable state corruption, or logical conflicts introduced by the recent changes.

## Acceptance Criteria

### Verification & Review
- [ ] The agent team must provide a detailed report of the code review.
- [ ] If any logical errors or edge cases are found, the team must propose and implement the fixes.
- [ ] The codebase must compile successfully without warnings related to the new logic.

## Follow-up — 2026-07-13T10:36:22Z

An AI Simulator and Prediction Engine Upgrade for the Towers game bot. The goal is to mathematically and algorithmically eliminate consecutive losses, prevent bankroll wipeouts (bankruptcy), and maximize the overall win rate using Python-based simulations to train the AI before applying the logic back to the Dart app.

Working directory: c:\Users\Admin N\Desktop\golden_p
Integrity mode: demo

## Requirements

### R1. Develop an advanced Python Simulator
Create a Python simulation script that models the Towers game using random probabilities infused with the Casino's "Trap Seed" logic (where the casino forces a loss if the bot bets heavily on a predictable pattern). The simulator must test various prediction algorithms and recovery strategies over millions of rounds.

### R2. Eliminate Consecutive Losses and Bankruptcy
Analyze the simulation results to identify the root causes of consecutive losses. Implement a new prediction algorithm (e.g., Q-Learning, pattern matching, or trap inversion) and a strict risk management framework (stop-loss, targeted recovery) that mathematically prevents the balance from draining to zero.

### R3. Maximize Win Rate
Optimize the prediction engine to achieve the highest possible win rate against the casino's algorithm. The resulting logic must be ported back into the Dart application (`lib/viewmodels/sequence_analyzer_viewmodel.dart` and `lib/viewmodels/overlay_buttons_viewmodel.dart`).

## Acceptance Criteria

### Simulation & Analysis
- [ ] A Python simulator script successfully runs 1,000,000 rounds without crashing.
- [ ] The simulation logs output metrics demonstrating the new algorithm's performance (Win Rate, Max Drawdown, Consecutive Losses).
- [ ] The simulation proves that consecutive losses are capped and bankruptcy is avoided.

### Application Integration
- [ ] The optimized prediction logic is successfully integrated into the Dart application.
- [ ] The Dart codebase compiles without errors after integration (`flutter build apk` succeeds).
