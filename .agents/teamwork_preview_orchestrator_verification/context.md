# Verification Context

## Target Files
- `lib/viewmodels/overlay_buttons_viewmodel.dart`
- `test/losing_streak_test.dart` (and other test files in `test/`)

## Requirements Map
- **R1: Pattern Toggle Logic**: Verify toggle between `BCBC` and `ACAC` on every loss.
- **R2: Recovery Strategy Toggle**: Verify swap between Strategy 1 (Stall) and Strategy 2 (Wait for Win) on recovery loss.
- **R3: General Code Review**: Examine `_executeSmartFlow`, loss/win branches for loops, state corruption, and crashes.

## Environment Details
- OS: Windows
- Flutter SDK: ^3.8.1
- Network Mode: CODE_ONLY
