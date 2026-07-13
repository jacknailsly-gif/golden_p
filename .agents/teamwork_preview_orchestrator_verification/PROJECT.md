# Project: Towers Game Bot Logic Verification

## Architecture
The Towers game bot manages autoplay through Flutter ViewModels and services:
- `OverlayButtonsViewModel`: Implements `_executeSmartFlow`, toggling pattern, and recovery strategy on wins/losses.
- `SequenceAnalyzerViewModel`: Analyzes state and coordinates with the pipeline.

This verification task focuses on:
1. Fixed pattern toggling (R1) correctness.
2. Recovery strategy toggling (R2) correctness and immediate transition.
3. Code review (R3) for safety, liveness, and edge cases.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Exploration & Audit | Run code review on overlay buttons viewmodel and identify potential issues | None | DONE |
| 2 | Testing & Fixing | Implement missing unit tests for toggles, correct any logical errors found | M1 | IN_PROGRESS (Iteration 2 - Remediation) |
| 3 | Final Review & Sign-off | Run reviewers, challengers, and forensic auditor to verify changes | M2 | PLANNED |

## Interface Contracts
- Pattern toggle: Switches `_currentFixedPattern` between `'BCBC'` and `'ACAC'` on every loss.
- Recovery toggle: Switches `_currentRecoveryStrategy` immediately between 1 and 2 when recovery bet loses.
- No time-based timers or delays in toggle logic.
