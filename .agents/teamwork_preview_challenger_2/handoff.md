# Mathematical Limit Conditions Test Report

## 1. Observation

### Code Analysis
The following sections in `lib/viewmodels/overlay_buttons_viewmodel.dart` define and implement the 5% cap, 4x base bet max limit, and the circuit breaker safety mechanisms:

#### 1. 4x Base Bet Max Limit (Lines 1921-1924)
```dart
        double maxAllowedBet = _lockedBaseBet! * 4.0;
        if (requiredBet > maxAllowedBet) {
          requiredBet = maxAllowedBet;
        }
```
*Observation*: The required bet is capped at exactly 4 times the base bet amount locked at the start of the sequence session.

#### 2. 5% Cap (Lines 1926-1931)
```dart
        double maxCap = balance * 0.05;

        if (requiredBet > maxCap) {
           debugPrint('[V102 SMART CAP] 🚨 Bet exceeds 5% cap. Reducing from ${requiredBet.toStringAsFixed(2)} to ${maxCap.toStringAsFixed(2)}');
           requiredBet = maxCap;
        }
```
*Observation*: The required bet size is further capped at 5% of the current account balance.

#### 3. Capping Bypass / Optimization Check (Lines 1939-1943)
```dart
        double currentBet = await _getBetAmount();
        if (currentBet < requiredBet) {
           await _setBetAmount(requiredBet);
           debugPrint('[V98.0 AI] 🎯 Executing Recovery Pulse: ${requiredBet.toStringAsFixed(2)}');
        }
```
*Observation*: The code only injects and updates the bet size in the WebView using `_setBetAmount(requiredBet)` if the page's `currentBet` is strictly less than the calculated `requiredBet`.

#### 4. Circuit Breaker (Lines 957-964)
```dart
          if (_consecutiveLossesStreak >= 3) {
            _webViewController?.reload();
            _stopReason = '🚨 [CIRCUIT BREAKER] 3 consecutive losses detected!';
            _sequenceAnalyzerViewModel.advice =
                '🚨 [CIRCUIT BREAKER] WebView reloaded to avoid tracking. Auto-play halted.';
            stopSequence();
            break;
          }
```
*Observation*: The bot immediately triggers a circuit breaker if the consecutive losses streak reaches 3. This reloads the WebView, stops the sequence execution, and halts the autoplay.

#### 5. Unreachable Code / Dead Code (Line 1874)
```dart
    } else if (_consecutiveLossesStreak == 4) {
       // Human Override: Sniper strike at 4 losses
       targetLoss = _totalAccumulatedLoss;
       debugPrint('[V100.0] 🎯 Loss Streak 4: Sniper Recovery Strike!');
    }
```
*Observation*: There is a branch in recovery escalation designed for `_consecutiveLossesStreak == 4`, but the circuit breaker halts autoplay at `_consecutiveLossesStreak >= 3`.

---

### Empirical Test Execution
A new unit test suite was written in `test/limit_conditions_test.dart` to verify these three limits. Running the test suite yields:
```
00:00 +1: OverlayButtonsViewModel Mathematical Limits Verification Verify 4x Base Bet Max Limit and 5% Cap under High Balance
[V98.0 AI] 🎯 Executing Recovery Pulse: 40.00
00:00 +1: OverlayButtonsViewModel Mathematical Limits Verification Verify 5% Cap under Low Balance (Exposing bypass bug)
Current controller bet size: 10.0
[BUG VERIFIED] 5% Cap bypass occurred! The bet remained 10.0 instead of reducing to 5.0.
00:00 +2: OverlayButtonsViewModel Mathematical Limits Verification Verify Circuit Breaker triggers after 3 consecutive losses
00:01 +3: (tearDownAll)
00:01 +3: All tests passed!
```

---

## 2. Logic Chain

### 4x Base Bet Max Limit Verification
1. Given a locked base bet of `10.0` and a balance of `10000.0`.
2. After 1 loss, the required recovery bet is calculated as `(targetLoss + baseBet) / 0.42 = (10 + 10) / 0.42 = 47.62`.
3. The 4x limit caps this bet size to `10.0 * 4 = 40.0`.
4. Since `40.0` is less than 5% of `10000.0` (`500.0`), the 5% cap does not apply.
5. In tests, the page's current bet is correctly updated to `40.0`. This confirms the 4x base bet max limit functions as designed.

### 5% Cap Bypass Bug Detection
1. Given a locked base bet of `10.0` and a low account balance of `100.0`.
2. After 1 loss, the required recovery bet is calculated as `47.62`. Capped by 4x base bet limit to `40.0`.
3. The 5% cap is calculated as `100.0 * 0.05 = 5.0`.
4. The code sets `requiredBet = maxCap = 5.0`.
5. However, before injecting the updated bet to the page, it checks `if (currentBet < requiredBet)`.
6. Since the page's current bet is `10.0` (base bet size) and `10.0` is NOT less than `5.0`, the `if` block evaluates to `false`.
7. The WebView is never updated with the `5.0` bet amount. The bot continues playing with a bet of `10.0` (which is 10% of the balance, bypassing the 5% safety cap).

### Circuit Breaker Verification
1. Under a hostile environment where bets result in consecutive losses, the consecutive loss streak increases to 3.
2. At the 3rd consecutive loss, the circuit breaker triggers: it sets `_isRunning` to false, stops the sequence, reloads the WebView, and breaks the execution loops.
3. Tests confirm that the bot halts exactly at 3 consecutive losses without initiating a 4th bet.

### Unreachable Code Branch Verification
1. Because the circuit breaker halts sequence execution immediately at 3 consecutive losses, `_consecutiveLossesStreak` can never reach 4.
2. Thus, the `else if (_consecutiveLossesStreak == 4)` branch in `_executeM5RecoveryEscalation` is dead code and never executes in smart mode.

---

## 3. Caveats
- No other potential limit bypasses were found under the investigated scenarios.
- The 5% cap bypass occurs specifically when the safety cap enforces a bet size that is strictly smaller than the current bet value present in the UI (e.g. during high-drawdown phases on low-balance accounts).

---

## 4. Conclusion
1. **4x Base Bet Max Limit**: Mathematically sound and functions correctly under high balances.
2. **5% Cap Safety Mechanism**: Has a critical logic flaw. Because the code checks `if (currentBet < requiredBet)` before updating the page bet, it bypasses the safety cap whenever the cap forces the bet to decrease below the current page bet. To fix this, the check should be changed to ensure the bet is updated if `currentBet != requiredBet`.
3. **Circuit Breaker**: Robust and shuts down autoplay instantly at 3 consecutive losses.
4. **Dead Code**: The `_consecutiveLossesStreak == 4` block is completely unreachable due to the 3-loss circuit breaker.

---

## 5. Verification Method

### Test Suite Execution
Execute the following commands from the root directory to verify the test suite:
```powershell
# Run the newly added limit condition tests
flutter test test/limit_conditions_test.dart

# Run all other project tests to verify regression safety
flutter test
```

### Files to Inspect
- `lib/viewmodels/overlay_buttons_viewmodel.dart`
- `test/limit_conditions_test.dart`
