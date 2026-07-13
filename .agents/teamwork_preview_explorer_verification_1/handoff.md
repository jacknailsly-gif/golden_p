# Audit and Verification Report — Requirement R1 (Pattern Toggle Logic)

## 1. Observation
In `lib/viewmodels/overlay_buttons_viewmodel.dart`:
- **State Initialization** (Lines 313-314):
  ```dart
  String _currentFixedPattern = 'BCBC';
  bool _fixedPatternToggle = true;
  ```
- **Prediction Generation** (Lines 792-807):
  ```dart
      // V66.0: Brainless Fixed Pattern Logic (Requested by user)
      // Completely bypasses Ghost Rounds, Trap Breakers, and AI logic.
      String prediction = 'A';
      
      if (_currentFixedPattern == 'BCBC') {
         prediction = _fixedPatternToggle ? 'B' : 'C';
      } else {
         // ACAC pattern
         prediction = _fixedPatternToggle ? 'A' : 'C';
      }
      
      _fixedPatternToggle = !_fixedPatternToggle; // Toggle for next round
      
      String targetId = prediction == 'A' ? 'M1' : (prediction == 'B' ? 'M2' : 'M3');
      debugPrint('[V66.0 FIXED PATTERN] 🤖 Using Pattern: $_currentFixedPattern -> Selected $prediction');
  ```
- **Loss Handlers** (Lines 1095-1098):
  ```dart
          // V69.0: Pattern Loss Toggle (Switch on EVERY loss)
          _currentFixedPattern = (_currentFixedPattern == 'BCBC') ? 'ACAC' : 'BCBC';
          _fixedPatternToggle = true; // Start fresh
          debugPrint('[V69.0 FIXED PATTERN] 🔄 Loss occurred! Toggling pattern to: $_currentFixedPattern');
  ```

During the execution of the test command (`flutter test`), the command failed (exit code 1) with 3 failing tests:
1. `losing_streak_test.dart`: `R2: Strict 3-Loss Hard Limit / Circuit Breaker reload and halt`
2. `anti_tracking_test.dart`: `Verify bot outputs contain enough entropy to evade tracking`
3. `anti_tracking_test.dart`: `Strict 3-Loss circuit breaker verification with Hostile/Sniping mode`

The debug output logs showed:
- **For Shannon Entropy failure**:
  ```
  Verify bot outputs contain enough entropy to evade tracking [E]
    Expected: a value greater than <1.2>
      Actual: <1.0>
  ```
- **For Circuit Breaker failures**:
  ```
  Strict 3-Loss circuit breaker verification with Hostile/Sniping mode [E]
    Expected: false
      Actual: <true>
    Loop should stop running
  ```
- **Live fixed pattern switching logs**:
  ```
  [V66.0 FIXED PATTERN] 🤖 Using Pattern: BCBC -> Selected B
  ...
  [V69.0 FIXED PATTERN] 🔄 Loss occurred! Toggling pattern to: ACAC
  ...
  [V66.0 FIXED PATTERN] 🤖 Using Pattern: ACAC -> Selected A
  ```

## 2. Logic Chain
- **Step 1**: The active fixed pattern state is tracked via two variables: `_currentFixedPattern` (which holds either `'BCBC'` or `'ACAC'`) and `_fixedPatternToggle` (a boolean indicating if the current round should bet on the first tile of the pattern vs the second tile).
- **Step 2**: When a prediction is generated at the start of a round (lines 796-801):
  - For `BCBC`, `_fixedPatternToggle == true` resolves to `'B'` and `_fixedPatternToggle == false` resolves to `'C'`.
  - For `ACAC`, `_fixedPatternToggle == true` resolves to `'A'` and `_fixedPatternToggle == false` resolves to `'C'`.
- **Step 3**: `_fixedPatternToggle` is then immediately inverted (`_fixedPatternToggle = !_fixedPatternToggle;` at line 803) to prepare for the subsequent round.
- **Step 4**: If the round results in a win (success branch at lines 882+), `_currentFixedPattern` and `_fixedPatternToggle` are left untouched, so the next round correctly continues the alternating sequence (e.g. `'B'` -> `'C'` -> `'B'` -> `'C'`).
- **Step 5**: If the round results in a loss (failure branch at lines 1020+), `_currentFixedPattern` toggles between `'BCBC'` and `'ACAC'` via line 1096.
- **Step 6**: Simultaneously on a loss, `_fixedPatternToggle` is reset to `true` (line 1097). This guarantees that the newly toggled pattern starts fresh on its first element (e.g., `'A'` for `ACAC` or `'B'` for `BCBC`).
- **Step 7**: A comprehensive codebase search (via `grep_search`) confirmed no other code alters these state variables. Thus, the state transitions are deterministic and cannot enter invalid configurations.
- **Step 8**: The failing test `Verify bot outputs contain enough entropy to evade tracking` is caused by the low entropy (1.0) of the fixed pattern. Because R1 requires the bot to follow a strict brainless sequence, it bypasses the random/AI engine, reducing Shannon Entropy to 1.0 (which is lower than the 1.2 threshold mandated by the test).
- **Step 9**: The failing tests for `Circuit Breaker` (Requirement R2) are caused by the lack of R2's implementation inside `overlay_buttons_viewmodel.dart`. Although a patch file (`proposed_r2_circuit_breaker.patch`) exists in `.agents/teamwork_preview_explorer_m1_2/`, it has not yet been applied to the codebase, leading the tests to fail because autoplay does not halt after exactly 3 consecutive losses.

## 3. Caveats
- **Persistent State**: The variables `_currentFixedPattern` and `_fixedPatternToggle` are not reset inside `startSequence()`. When the bot is stopped and restarted, it resumes from the exact pattern state it was in at the time of stoppage rather than resetting to `'BCBC'` and `true`. This preserves long-term continuity but may be unexpected if a clean reset is desired on every sequence start.
- **Low Shannon Entropy**: The R1 brainless fixed pattern logic is incompatible with the existing anti-tracking Shannon Entropy verification test. As long as R1 is enabled and active, the entropy test will fail.

## 4. Conclusion
The pattern toggle logic for Requirement R1 is fully correct, robust, and correctly switches between `BCBC` and `ACAC` on every loss. There are no edge cases that would cause the logic to get stuck or fail to toggle. The test suite failures are expected due to the nature of the R1 requirement (which lowers prediction entropy) and the unimplemented state of the R2 Circuit Breaker (for which a patch exists but has not been applied).

## 5. Verification Method
- **Command to Execute**: `flutter test`
- **Inspect**: Look at the terminal output logs for the `anti_tracking_test` suite, searching for the `[V69.0 FIXED PATTERN]` and `[V66.0 FIXED PATTERN]` debug prints.
- **Invalidation Condition**: If `_currentFixedPattern` fails to alternate after a loss, or if `_fixedPatternToggle` is not reset to `true` on loss, the logic would be invalid (this is proven false by the test logs showing perfect transitions).
