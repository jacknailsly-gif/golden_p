# Project: golden_p Anti-Tracking & Hard Limit

## Architecture
The `golden_p` bot uses a prediction pipeline to output guesses ('A', 'B', 'C') for a WebView-based game, overlaying controls using Flutter ViewModels:
- `PredictionPipelineService`: Resolves hybrid model outputs and ensemble voting scores.
- `OverlayButtonsViewModel`: Executes the main `_executeSmartFlow` loop, controlling bets, detecting outcomes, and adjusting loss streaks.
- `SequenceAnalyzerViewModel`: Broadcasts prediction changes, interacts with the model, and communicates UI state / advice.

To avoid pattern tracking by the casino and guarantee stop-loss:
1. **R1 Obfuscation Engine**: Injects randomized timing delays, chaotic 1-baht bait bets at random intervals, and non-deterministic vote noise.
2. **R2 3-Loss Circuit Breaker**: Instantly catches `_consecutiveLossesStreak >= 3`, reloads the WebView, sets UI advice/stop reasons, and halts auto-play.
3. **R3 Automated Test**: A stateful mock simulation that proves the circuit breaker is mathematically foolproof and that prediction output has sufficient entropy.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Exploration & Analysis | Audit codebase for prediction loops and state management | None | DONE |
| 2 | Implementation (R1, R2) | Implement obfuscation engine (timing, bait, noise) and circuit breaker | M1 | PLANNED |
| 3 | Test Suite (R3) | Implement `test/anti_tracking_test.dart` asserting entropy and hard limits | M2 | PLANNED |
| 4 | QA & Forensic Audit | Validate test passes and perform final audit | M3 | PLANNED |

## Interface Contracts
### Obfuscation & Noise Integration
- `PredictionPipelineService.generateHybridResponse(...)` must take an optional `double voteNoiseScale` (or use a configuration-defined noise range) to perturb `voteScores` before determining `bestPick`.
- `OverlayButtonsViewModel._executeSmartFlow` must dynamically inject:
  - Randomized delays using non-linear math (e.g. exponential backoff + jitter or gaussian delay) instead of uniform constants.
  - A bait bet check before betting: if triggered, bet 1-baht (min bet) on a random choice, and skip recovery loss recording.

### Circuit Breaker Integration
- Immediately after `_consecutiveLossesStreak++` is called inside `OverlayButtonsViewModel._executeSmartFlow`, if the value is `>= 3`, trigger `stopSequence()`, reload WebView, set `_stopReason`, and break from the loop.

## Code Layout
- `lib/services/prediction_pipeline_service.dart`: Main ensemble prediction engine logic.
- `lib/viewmodels/overlay_buttons_viewmodel.dart`: Autoplay loop and viewmodel state management.
- `test/anti_tracking_test.dart`: Test suite validating Shannon Entropy and the 3-loss hard limit.
