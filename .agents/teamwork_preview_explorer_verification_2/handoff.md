# Handoff Report: Audit of Requirement R2 (Recovery Strategy Toggle Logic)

## 1. Observation
I investigated the codebase to analyze the recovery strategy toggle logic under Requirement R2, specifically within the file `lib/viewmodels/overlay_buttons_viewmodel.dart`.

### A. Location of Strategy Toggle
The strategy immediately toggles when a recovery bet loses. This is implemented in the loss branch of the visual outcome detection within `_executeSmartFlow`:
- **File**: `lib/viewmodels/overlay_buttons_viewmodel.dart`
- **Lines 1108–1114**:
```dart
          if (_isRecoveryUnlocked) {
              _consecutiveRecoveryLosses++;
              debugPrint('[V68.0 HARD STOP] ⚠️ Lost a recovery bet. Consecutive Recovery Losses: $_consecutiveRecoveryLosses / 3');
              
              // V69.0: Switch recovery strategy immediately on recovery loss!
              _currentRecoveryStrategy = (_currentRecoveryStrategy == 1) ? 2 : 1;
              debugPrint('[V69.0 STRATEGY] 🔄 Recovery lost! Switched strategy to: ${_currentRecoveryStrategy == 1 ? "1 (Stall 3-5)" : "2 (Wait Win)"}.');
```

### B. Unused Time-based Toggling State Variables
The following variables are declared but never referenced in any logic (representing dead code):
- **File**: `lib/viewmodels/overlay_buttons_viewmodel.dart`
- **Lines 317–319**:
```dart
  int _currentRecoveryStrategy = 1; // 1 = Stall 3-5, 2 = Wait for Win
  DateTime? _lastStrategyToggleTime;
  int _minutesUntilNextToggle = 10;
```

### C. Timer Instances in overlay_buttons_viewmodel.dart
Only two timers exist in the class `OverlayButtonsViewModel`:
1. `_slCheckTimer`:
- **Lines 41**: `Timer? _slCheckTimer; // High-frequency monitor for TP`
- **Lines 507–508**:
```dart
      _slCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
```
2. `_breakTimer`:
- **Line 59**: `Timer? _breakTimer;`
- **Line 1223**: `_breakTimer = Timer.periodic(const Duration(minutes: 1), (timer) {`

No other timers are instantiated or used.

---

## 2. Logic Chain
1. **Observation 1.A** shows that the strategy toggling logic (`_currentRecoveryStrategy = (_currentRecoveryStrategy == 1) ? 2 : 1;`) is executed immediately in the loss handler (`m0Status == 'bet'`) when a recovery bet fails (`_isRecoveryUnlocked == true`).
2. **Observation 1.B** shows that the datetime/timer variables (`_lastStrategyToggleTime` and `_minutesUntilNextToggle`) from the old time-based strategy toggle design are dead code and not integrated into any logic.
3. **Observation 1.C** shows that all `Timer` instances in `OverlayButtonsViewModel` are dedicated to P&L (take-profit/stop-loss) checks and session break controls, meaning no timers are used to switch between recovery strategies.
4. Therefore, I conclude that recovery strategy toggling is immediate, event-driven (occurs directly upon a recovery bet loss), and is completely independent of time-based timers.

---

## 3. Caveats
- I did not test the app using a live casino environment or real WebView, but evaluated the logic through source analysis and the project's mock test suite (`flutter test test/losing_streak_test.dart`).
- The test suite contains a failing test `R2: Strict 3-Loss Hard Limit / Circuit Breaker reload and halt` because the test expects a circuit breaker reloader that was removed or restructured in the current codebase layout.

---

## 4. Conclusion
The codebase correctly implements the Requirement R2 recovery strategy toggle logic:
- Switching between Strategy 1 (Stall) and Strategy 2 (Wait for Win) occurs immediately upon the loss of a recovery bet.
- No time-based timers or clocks govern the toggle; it is strictly event-driven.
- Several edge cases and dead-code blocks were identified (see below).

### Identified Edge Cases & Findings:
1. **Edge Case 1: Strategy Toggling Immediately Diverts the Loss Handling Branch**
   - The strategy toggling at line 1113 happens before the stall/wait state initialization at lines 1129–1141. When a recovery bet loses under Strategy 1, it immediately toggles to Strategy 2, so the loss initialization executes Strategy 2 logic (`_waitingForWinToRecover = true`). When it loses under Strategy 2, it toggles to Strategy 1 and immediately executes Strategy 1 logic (`_stallRoundsRemaining = 3 + Random().nextInt(3)`). This execution order is crucial for the correct behavior of the transition.
2. **Edge Case 2: Strategy 1 "Base Bet Loop" after Partial Win**
   - If a recovery bet under Strategy 1 is a partial win (meaning debt is reduced but still $>0$):
     - In the next round, `_stallRoundsRemaining` is 0 and `_readyToRecover` is false. The code falls into the `else` block (line 750), setting `_isRecoveryUnlocked = false`.
     - The bot will place base bets indefinitely until either a base bet loses (triggering the loss branch and setting a new `_stallRoundsRemaining`) or the debt is wiped by cumulative base wins.
     - In contrast, Strategy 2 immediately places consecutive recovery bets in the next rounds as long as it continues to win.
3. **Edge Case 3: Unreachable stop-loss break condition (`_consecutiveRecoveryLosses >= 5`)**
   - In `_executeSmartFlow` (line 703), the condition `_consecutiveRecoveryLosses >= 5` is unreachable because at line 1116, the 3-Loss Hard Stop is triggered, which resets `_consecutiveRecoveryLosses` to 0.
4. **Edge Case 4: No State Reset on Sequence Start**
   - The state variables `_stallRoundsRemaining`, `_readyToRecover`, and `_waitingForWinToRecover` are not reset in `startSequence()`. Starting the bot after stopping it preserves the strategy state.
5. **Edge Case 5: Preservation of Strategy State after Hard Stop-Loss**
   - The `_currentRecoveryStrategy` is not reset to a default value when the Hard Stop is triggered or when the sequence starts, preserving whichever strategy was active.

---

## 5. Verification Method
To verify these findings:
1. **Inspect Code Files**:
   - Verify strategy switching on line 1113 of `lib/viewmodels/overlay_buttons_viewmodel.dart`.
   - Verify the list of timers in `lib/viewmodels/overlay_buttons_viewmodel.dart` by searching for `Timer` class instances.
2. **Run Tests**:
   - Execute the test command: `flutter test test/losing_streak_test.dart`
   - Observe that other tests pass, confirming the logic compiles and behaves as described in the mock WebView environment.
