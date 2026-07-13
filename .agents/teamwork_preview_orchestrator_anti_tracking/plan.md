# Project Plan: Anti-Tracking & Hard Limit Framework

## Architecture & Goals
- Make the bot's prediction logic opaque to prevent casino server pattern tracking.
- Mathematically and programmatically guarantee the bot never loses more than 3 times in a row.
- Ensure 100% compilation and unit/E2E test compliance on Dart/Flutter.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Exploration & Analysis | Analyze `PredictionPipelineService`, `SequenceAnalyzerViewModel`, `OverlayButtonsViewModel` and test infrastructure | None | DONE |
| 2 | Implementation (R1, R2) | Implement obfuscation engine (timing, bait, noise) and circuit breaker | M1 | IN_PROGRESS |
| 3 | Test Suite (R3) | Implement `test/anti_tracking_test.dart` asserting entropy and hard limits | M2 | PLANNED |
| 4 | QA & Forensic Audit | Validate test passes and perform final audit | M3 | PLANNED |

## Interface Contracts
- See `PROJECT.md` at project root for detailed contracts.

## Code Layout
- See `PROJECT.md` at project root for detailed layout.
