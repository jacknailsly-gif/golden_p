# Handoff Report — upgraded-prediction-and-risk-recovery

## 1. Observation
- Modified files:
  - `lib/viewmodels/overlay_buttons_viewmodel.dart` (lines 305, 325, 623, 639, 796, 939, 957, 1037, 1135, 1344, 1600, 1781, 1823-1910)
  - `test/anti_tracking_test.dart` (line 255)
  - `test/losing_streak_test.dart` (line 46)
- Verbatim code additions/changes in `lib/viewmodels/overlay_buttons_viewmodel.dart`:
  - Recovery losses limit state:
    ```dart
    int _consecutiveRecoveryLosses = 0;
    final int _maxRecoveryLossesLimit = 2; // Halt and reset after 2 consecutive recovery losses
    ```
  - Recovery bet win/loss tracking:
    - Win branch:
      ```dart
      if (wonRecoveryBet) {
        _consecutiveRecoveryLosses = 0;
      }
      ```
    - Loss branch:
      ```dart
      if (_lockedBaseBet != null && currentBetStr > _lockedBaseBet! + 0.000001) {
        _consecutiveRecoveryLosses++;
      }
      ```
  - Upgraded `_executeM5RecoveryEscalation`:
    - Checks for consecutive recovery losses threshold:
      ```dart
      if (_consecutiveRecoveryLosses >= _maxRecoveryLossesLimit) {
        _totalAccumulatedLoss = 0.0;
        _consecutiveRecoveryLosses = 0;
        _consecutiveLossesStreak = 0;
        _ghostSniperWinCount = 0;
        ProvablyFairEngine().rotateSeed();
        await _ensureBaseBet(runToken);
        return;
      }
      ```
    - Check for zero debt:
      ```dart
      if (_totalAccumulatedLoss <= 0.0) {
        _consecutiveRecoveryLosses = 0;
        await _ensureBaseBet(runToken);
        return;
      }
      ```
    - Capped high debt ghost wins required from `>= 3` to `>= 2`.
    - Fractional recovery bet sizing:
      ```dart
      double recoveryFraction = targetLoss * 0.25 + _lockedBaseBet!;
      if (recoveryFraction > targetLoss) {
        recoveryFraction = targetLoss;
      }
      double requiredBet = (recoveryFraction + _lockedBaseBet!) / 0.42;

      double maxAllowedBet = _lockedBaseBet! * 4.0;
      if (requiredBet > maxAllowedBet) {
        requiredBet = maxAllowedBet;
      }

      double maxCap = balance * 0.05;
      if (requiredBet > maxCap) {
        debugPrint('[V102 SMART CAP] 🚨 Bet exceeds 5% cap. Reducing from ${requiredBet.toStringAsFixed(2)} to ${maxCap.toStringAsFixed(2)}');
        requiredBet = maxCap;
      }
      ```
  - Unscaled delays (such as `coolDown`, `m0LoadDelay`, `jitterDelay`, `_humanJitter`, animation settling delay, and click/visual overlay button press delays) were scaled by `_speedMultiplier` to allow simulated testing to run instantly in `flutter test`.
- Verified test output:
  - Ran `flutter test` and observed:
    ```
    00:36 +10: All tests passed!
    ```

## 2. Logic Chain
1. By declaring `_consecutiveRecoveryLosses` and `_maxRecoveryLossesLimit`, the bot now maintains the state of consecutive recovery losses.
2. In the win branch of the smart flow, if the won bet is verified to be a recovery bet, the streak resets (`_consecutiveRecoveryLosses = 0`).
3. In the loss branch, if the lost bet was a recovery bet (`currentBetStr > _lockedBaseBet! + 0.000001`), the streak increments (`_consecutiveRecoveryLosses++`).
4. At the start of `_executeM5RecoveryEscalation`, hitting the recovery losses limit triggers the circuit breaker, resetting accumulated loss, streaks, ghost sniper win counts, rotating seed, ensuring base bet, and returning immediately.
5. High debt check triggers recovery strike on 2 ghost wins instead of 3.
6. Betting sizes are computed based on fractional recovery (`targetLoss * 0.25 + baseBet`), restricted to a max of `baseBet * 4.0`, and capped at a maximum of 5% of the current balance.
7. SharedPreferences initial mock values enabling `'overlay_smart_mode': true` allow tests to run in smart mode directly.
8. Scaling delay futures by `_speedMultiplier` makes the tests execute without real-world latency, allowing the entropy test to complete 100 rounds quickly.
9. Running the test suite confirms all 10 tests are green, validating the full implementation.

## 3. Caveats
- Delays scaled by `_speedMultiplier` are scaled assuming `_speedMultiplier` is set to `1.0` in normal execution and set to `1000.0` during widget tests. If a speed multiplier of `0.0` is somehow provided, it could result in division by zero; however, the model logic guarantees `_speedMultiplier` defaults to `1.0` and cannot be `0`.

## 4. Conclusion
The upgraded prediction and risk recovery mechanisms have been successfully integrated into the OverlayButtonsViewModel, and the test mock setup issues have been fully resolved. All tests compile and pass successfully.

## 5. Verification Method
- Execute the test suite using:
  ```powershell
  flutter test
  ```
- All tests in `test/anti_tracking_test.dart` and `test/losing_streak_test.dart` should compile and pass (showing 10 green tests total).
