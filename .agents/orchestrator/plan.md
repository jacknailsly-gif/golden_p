# Plan - AI Simulator and Prediction Engine Upgrade

## Objective
Upgrade the Towers game bot prediction and recovery mechanisms to algorithmically eliminate consecutive losses, prevent bankroll wipeouts, and maximize overall win rate using Python-based simulations and then porting the findings back to the Dart app.

## Requirements Checklist
- **R1: Python Simulator**: Successfully run 1,000,000 rounds without crashing, model "Trap Seed" logic (forces loss on predictable heavy betting).
- **R2: Loss & Bankruptcy Prevention**: cap consecutive losses, prevent bankroll from draining to zero, implement stop-loss/targeted recovery.
- **R3: Port to Dart**: Integrate optimized prediction/recovery logic into SequenceAnalyzerViewModel and OverlayButtonsViewModel, compile cleanly.

## Execution Tracks

### Track A: Python Simulation & Algorithm Training
1. **Develop Simulator**: Model the Towers game (rows/levels, probabilities) including the Casino "Trap Seed" (detects predictable patterns with high stakes and overrides outcome to loss).
2. **Implement Baseline & Upgraded Algorithms**:
   - Baseline: Current bot logic.
   - Upgraded prediction: Q-learning, pattern matching, or trap inversion.
   - Risk management: Dynamic stop-loss, targeted recovery, and size capping.
3. **Simulation Verification**: Run 1,000,000 rounds, log metrics (Win Rate, Max Drawdown, Max Consecutive Losses, Ending Balance). Confirm zero bankruptcy rate across multiple simulation runs.

### Track B: Dart Integration & Verification
1. **Port to Dart**: Translate the optimized prediction/recovery algorithm into:
   - `lib/viewmodels/sequence_analyzer_viewmodel.dart`
   - `lib/viewmodels/overlay_buttons_viewmodel.dart`
2. **E2E & Compilation Check**: Ensure `flutter build apk` or compilation commands succeed. Run unit tests to confirm application behavior.
3. **Forensic Integrity Verification**: Run Forensic Auditor to guarantee no hardcoding of test outputs or cheating.

## Schedule & Milestones
- **Milestone 1**: Codebase Exploration (analyze current Dart implementation and any existing python scripts).
- **Milestone 2**: Python Simulator & Strategy Design (develop python script, run simulations).
- **Milestone 3**: Integration and Porting to Dart.
- **Milestone 4**: Final Verification and Audit.
