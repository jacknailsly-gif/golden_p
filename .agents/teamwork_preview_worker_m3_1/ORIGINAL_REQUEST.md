## 2026-07-13T10:49:03Z
Please integrate the upgraded prediction and risk recovery mechanisms into the Dart application and fix the test setup bugs.
Your working directory is: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_m3_1

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Detailed Instructions:

1. Modify `lib/viewmodels/overlay_buttons_viewmodel.dart`:
   - Declare state variables under "Smart Bot State" or recovery state section (e.g. around line 305):
     ```dart
     int _consecutiveRecoveryLosses = 0;
     final int _maxRecoveryLossesLimit = 2; // Halt and reset after 2 consecutive recovery losses
     ```
     Expose getters if useful.
   - Modify `_executeM5RecoveryEscalation`:
     - Check if `_consecutiveRecoveryLosses >= _maxRecoveryLossesLimit`. If it is met: reset `_totalAccumulatedLoss = 0.0`, `_consecutiveRecoveryLosses = 0`, `_consecutiveLossesStreak = 0`, `_ghostSniperWinCount = 0`, call `ProvablyFairEngine().rotateSeed()`, ensure base bet (via `await _ensureBaseBet(runToken);`), and return.
     - Also, reset `_consecutiveRecoveryLosses = 0;` if `_totalAccumulatedLoss <= 0.0`.
     - In the high debt section (where `_totalAccumulatedLoss > _lockedBaseBet! * 15.0` at the end of the `LossStreak == 0` block), change the required ghost sniper win count check from `>= 3` to `>= 2`.
     - Modify the recovery bet sizing logic where `targetLoss > 0.0`:
       - Instead of `double requiredBet = (targetLoss + _lockedBaseBet!) / 0.42;`, calculate a fractional recovery:
         ```dart
         double recoveryFraction = targetLoss * 0.25 + _lockedBaseBet!;
         if (recoveryFraction > targetLoss) {
           recoveryFraction = targetLoss;
         }
         double requiredBet = (recoveryFraction + _lockedBaseBet!) / 0.42;
         ```
       - Restrict the bet size to prevent exponential runaway:
         ```dart
         double maxAllowedBet = _lockedBaseBet! * 4.0;
         if (requiredBet > maxAllowedBet) {
           requiredBet = maxAllowedBet;
         }
         ```
       - Enforce a 5% balance cap instead of 10%:
         ```dart
         double maxCap = balance * 0.05;
         if (requiredBet > maxCap) {
           debugPrint('[V102 SMART CAP] 🚨 Bet exceeds 5% cap. Reducing from ${requiredBet.toStringAsFixed(2)} to ${maxCap.toStringAsFixed(2)}');
           requiredBet = maxCap;
         }
         ```
   - Modify `_executeSmartFlow`:
     - In the win branch (around line 796): check if `wonRecoveryBet` is true. If it is, reset `_consecutiveRecoveryLosses = 0;`.
     - In the loss branch (around line 939): check if the lost bet was a recovery bet (`winningBet > _lockedBaseBet! + 0.000001` or similar, note: variable name in that block is `currentBetStr`). If it was a recovery bet, increment `_consecutiveRecoveryLosses++;`.

2. Modify `test/anti_tracking_test.dart` (around line 255):
   - Replace `SharedPreferences.setMockInitialValues({});` with `SharedPreferences.setMockInitialValues({'overlay_smart_mode': true});`.

3. Modify `test/losing_streak_test.dart` (around line 46):
   - Replace `SharedPreferences.setMockInitialValues({});` with `SharedPreferences.setMockInitialValues({'overlay_smart_mode': true});`.

4. Run `flutter test` to verify that all tests compile and pass successfully.
5. If there are compilation errors or test failures, analyze the errors and fix them.
6. Write a detailed report in `handoff.md` inside your working directory.
7. Update progress.md and send a handoff message back to me (conversation ID a7318c79-099b-4f11-9102-036ad0ec9192) when complete.
