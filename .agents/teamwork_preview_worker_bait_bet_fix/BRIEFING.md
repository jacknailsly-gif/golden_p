# BRIEFING — 2026-06-14T12:02:50+07:00

## Mission
Fix the bait bet size scaling bug in `lib/viewmodels/overlay_buttons_viewmodel.dart` and update tests to align with dynamic minimum bet scaling.

## 🔒 My Identity
- Archetype: Codebase Worker
- Roles: implementer, qa, specialist
- Working directory: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_bait_bet_fix
- Original parent: 7143f613-bd3c-4317-be85-945728a1bf25
- Milestone: Bait Bet Fix

## 🔒 Key Constraints
- CODE_ONLY network mode.
- DO NOT CHEAT. All implementations must be genuine.
- Write handoff.md in the working directory.
- Notify the parent orchestrator when complete.

## Current Parent
- Conversation ID: 248b4b23-970f-4e92-be89-39072abe68fa
- Updated: not yet

## Task Summary
- **What to build**: Modify bait bet size assignment in `lib/viewmodels/overlay_buttons_viewmodel.dart` (and any nested duplicate) from hardcoded `1.0` to `math.min(1.0, _lowestObservedBet ?? 1.0)`. Update tests asserting bait bet is `1.0` in `test/anti_tracking_test.dart` and `test/losing_streak_test.dart`.
- **Success criteria**: Tests in `test/anti_tracking_test.dart` and `test/losing_streak_test.dart` pass, minimum bet scales dynamically on crypto accounts.
- **Interface contracts**: PROJECT.md / SCOPE.md
- **Code layout**: PROJECT.md

## Key Decisions Made
- Used `math.min(1.0, _lowestObservedBet ?? 1.0)` to safely scale the bait bet size on cryptocurrency accounts without risking large random bets.
- Added `import 'dart:math' as math;` prefixed import to avoid breaking other un-prefixed occurrences of `Random()` in the viewmodel files.

## Artifact Index
- `.agents/teamwork_preview_worker_bait_bet_fix/handoff.md` — Handoff report summarizing the findings and verification.

## Change Tracker
- **Files modified**:
  - `lib/viewmodels/overlay_buttons_viewmodel.dart` — imported `dart:math` as `math` and scaled bait bet size.
  - `golden_p/lib/viewmodels/overlay_buttons_viewmodel.dart` — updated nested duplicate viewmodel file consistently.
- **Build status**: Pass
- **Pending issues**: None

## Quality Status
- **Build/test result**: Pass (all tests passed)
- **Lint status**: Clean (no warnings or info diagnostics in the modified files)
- **Tests added/modified**: Checked all test files for assertions on bait bet sizes, none found.

## Loaded Skills
- None
