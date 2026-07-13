# Handoff Report - R2 Codebase Explorer (Strict 3-Loss Hard Limit)

## 1. Observation
During the read-only codebase investigation, the following files, variables, and logic chains were analyzed:

### A. Consecutive Loss Tracking & State Storage
* **Global Loss Tracking**: Located in `lib/viewmodels/overlay_buttons_viewmodel.dart`:
  * State variables: 
    * `int _consecutiveLossesStreak = 0;` (line 286) tracks the total consecutive losses across all phases since the last successful cashout.
    * `int _consecutiveRecoveryLosses = 0;` (line 287) tracks consecutive losses occurring during a recovery phase.
    * `int _consecutiveSacrificeLosses = 0;` (line 288) tracks consecutive losses in sacrifice rounds.
  * Reset mechanism: `_resetLossStreaks()` (lines 290-294) resets all counters to `0` upon winning or taking hard stop-loss pauses.
  * Streak increment: Inside `_executeSmartFlow` under the `m0Status == 'bet'` (loss outcome) branch:
    * `_consecutiveLossesStreak++;` (line 1117)
* **Prediction Engine Loss Tracking**: Located in `lib/engines/v13_engine.dart`:
  * State variable: `int _consecutiveLosses = 0;` (line 74) tracks the loss streak to adjust prediction phases (Normal, Recovery, Defense, Counter).

### B. Prediction Flow & Auto-Play Control Loop
* **Main Loop**: The loop resides in `OverlayButtonsViewModel._executeSmartFlow(int runToken)` (lines 595-1215). It executes a `while (!_shouldAbort(runToken) && _isSmartMode)` sequence.
* **Control Chain**:
  1. Starts a round by clicking marker `M0` (Bet/Start): `await _performButtonAction('M0', strict: false);` (line 694).
  2. Resolves target board coordinates (`M1`, `M2`, `M3` mapping to 'A', 'B', 'C') using either randomized/dumb patterns or `_sequenceAnalyzerViewModel.getAbsolutePrediction()`.
  3. Clicks target tile: `await _performButtonAction(targetMarker, strict: false);` (line 829).
  4. Scans for outcome: `String m0Status = await _detectVisualOutcomeWithVerification('M0');` (line 857).
  5. **Win Path (`m0Status == 'cashout'`)**: Clicks `M0` to claim, calls `_resetLossStreaks()`, deduces gem positions, and performs debt adjustments (lines 860-1043).
  6. **Loss Path (`m0Status == 'bet'`)**: Records input, increments loss streaks, chunks debt, and checks for soft stop-losses or trap breakers (lines 1044-1215).

### C. Testing Verification
* Test file `test/losing_streak_test.dart` contains unit tests for prediction inversion, transition states, and stop-loss behaviors.
* Running `flutter test test/losing_streak_test.dart` completed successfully with all tests passing:
  ```
  00:00 +1: Losing Streak and Recovery Tests predictionMode copy_user vs ai_model
  00:00 +2: Losing Streak and Recovery Tests Hard Stop-Loss: triggers under default conditions (recoveryMode == 1) after 5 consecutive recovery losses
  00:00 +3: Losing Streak and Recovery Tests Trap Breaker Lockdown: loss during Trap Breaker does NOT unlock recovery or escalate bet size
  00:01 +4: Losing Streak and Recovery Tests predictionMode transition state machine: win stays in copy_user, 2 consecutive AI losses reset to copy_user
  00:01 +5: All tests passed!
  ```

---

## 2. Logic Chain
The implementation of R2 (Strict 3-Loss Hard Limit / Circuit Breaker) requires a programmatic guarantee that the bot cannot execute a 4th bet. The logic is as follows:

1. **Detection**: Directly after the loss outcome is processed and `_consecutiveLossesStreak` is incremented (line 1117), check if `_consecutiveLossesStreak >= 3`.
2. **Halt Execution**: By calling `stopSequence()`, the bot invalidates the execution token (`_sequenceRunToken++`) and sets `_isRunning = false`. Since `_shouldAbort(runToken)` is checked periodically (and at the start of each iteration), the loop will terminate. Adding an immediate `break;` ensures that the code execution exits the `_executeSmartFlow` loop immediately.
3. **Frontend Reset**: Invoking `_webViewController?.reload()` forces the WebView page to refresh. This physically resets the board UI and cleanses any active frontend session.
4. **User Communication**: Updating `_stopReason` and `_sequenceAnalyzerViewModel.advice` provides visual notification to the user in the UI, ensuring they are aware that the circuit breaker tripped.
5. **Conclusion**: Since the loop is terminated and no further clicks are sent to `M0`, the 4th consecutive bet is programmatically prevented.

---

## 3. Caveats
* **Forfeited Bets**: Refreshing the WebView via `_webViewController?.reload()` may result in forfeiting an active bet if the page is reloaded prior to the server completing the game round (though the loop halt guarantees no subsequent bets).
* **Read-Only Scoping**: No modifications have been written to the actual codebase. A patch file `proposed_r2_circuit_breaker.patch` has been written to the agent directory for implementation.
* **Loss Tracking Reliance**: The implementation relies on the accuracy of visual outcome scans. If the WebView visual scan fails or encounters latency, `_consecutiveLossesStreak` might update late. However, the double-scan checksum in `_detectVisualOutcomeWithVerification` mitigates this.

---

## 4. Conclusion
R2 (Strict 3-Loss Hard Limit) can be successfully implemented by inserting a circuit breaker check in `OverlayButtonsViewModel._executeSmartFlow` right after `_consecutiveLossesStreak++` (line 1117).
By calling `stopSequence()`, forcing a `break`, and triggering `_webViewController?.reload()`, the bot guarantees that the auto-play loop halts immediately, making a 4th consecutive loss impossible without manual reset and resumption by the user.

---

## 5. Verification Method
* **Independent Execution Test**: Run `flutter test test/losing_streak_test.dart` to verify existing tests.
* **Inspect Proposed Patch**: Review the changes defined in `.agents/teamwork_preview_explorer_m1_2/proposed_r2_circuit_breaker.patch`.
* **Behavior Verification**: When the patch is applied, running the bot and simulating 3 consecutive losses must result in:
  1. The bot UI halting.
  2. The WebView reloading.
  3. The stop reason message appearing as: `'🛑 CIRCUIT BREAKER: Strict 3-Loss Limit Reached. Auto-play halted.'`.
