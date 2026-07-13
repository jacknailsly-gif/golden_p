# Handoff Report - Bait Bet Scaling Fix

## 1. Observation
- **Hardcoded Bet Size**: Located at line 711 in `lib/viewmodels/overlay_buttons_viewmodel.dart` and nested duplicate `golden_p/lib/viewmodels/overlay_buttons_viewmodel.dart`.
  Verbatim code before modification:
  ```dart
  if (_isBaitRound) {
    await _setBetAmount(1.0);
    if (_shouldAbort(runToken)) break;
  }
  ```
- **Test Assertions**: Searched the `test/` directory for references to `"bait"`. No references found. No assertions specifically verified the hardcoded `1.0` bait bet value.
- **Test Runs**:
  - `flutter test test/anti_tracking_test.dart` completed successfully with:
    `All tests passed!`
  - `flutter test test/losing_streak_test.dart` completed successfully with:
    `All tests passed!`

## 2. Logic Chain
1. To implement dynamic bait bet size scaling, the hardcoded `1.0` value needed replacement with a dynamically resolved minimum.
2. The viewmodel contains `_lowestObservedBet` (Session-wide memory of lowest bet seen), which starts as `null` and is updated whenever a positive bet is observed.
3. Using `math.min(1.0, _lowestObservedBet ?? 1.0)` allows bait bets to scale down to the observed minimum on cryptocurrency accounts (e.g. `0.000009` or `0.01`) but stay capped at the standard `1.0` on fiat accounts or during initial runs before a lower bet is observed.
4. Because the codebase maintains a nested copy of the project under `golden_p/`, the exact same dynamic scaling change was applied to `golden_p/lib/viewmodels/overlay_buttons_viewmodel.dart` to maintain consistency.
5. Running `flutter test test/anti_tracking_test.dart` and `flutter test test/losing_streak_test.dart` confirms that the changes compile and do not break any existing test assertions.

## 3. Caveats
- No caveats. The fix is minimal and targeted.

## 4. Conclusion
- The bait bet size scaling bug was resolved by updating both `lib/viewmodels/overlay_buttons_viewmodel.dart` and its nested counterpart to use `math.min(1.0, _lowestObservedBet ?? 1.0)` instead of `1.0`.

## 5. Verification Method
- **Inspection Files**:
  - `lib/viewmodels/overlay_buttons_viewmodel.dart` around line 712.
  - `golden_p/lib/viewmodels/overlay_buttons_viewmodel.dart` around line 712.
- **Verification Commands**:
  - `flutter test test/anti_tracking_test.dart`
  - `flutter test test/losing_streak_test.dart`
