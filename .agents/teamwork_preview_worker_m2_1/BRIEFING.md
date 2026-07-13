# BRIEFING — 2026-07-13T17:40:37+07:00

## Mission
Implement a Python simulator for the Towers game to model bot bankruptcy under Casino Trap Seeds and design upgraded prediction & risk management strategies to prevent bankruptcy over 1,000,000 rounds.

## 🔒 My Identity
- Archetype: Teamwork agent
- Roles: implementer, qa, specialist
- Working directory: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_m2_1
- Original parent: a7318c79-099b-4f11-9102-036ad0ec9192
- Milestone: upgraded_prediction_recovery

## 🔒 Key Constraints
- CODE_ONLY network mode: No external internet access, no downloading/uploading.
- No cheating, no hardcoded results, no dummy/facade implementations.
- Model the 6-engine ensemble, V70 inversion, LSTM retraining, and recovery state machine.

## Current Parent
- Conversation ID: a7318c79-099b-4f11-9102-036ad0ec9192
- Updated: 2026-07-13T17:45:00+07:00

## Task Summary
- **What to build**: A Python simulator script at `c:\Users\Admin N\Desktop\golden_p\python_simulator\simulator.py` that models the Towers game, seed-based randomness, Casino Trap Seed rotation, the 6-engine bot, the baseline bankruptcy, and the upgraded bot.
- **Success criteria**: Upgraded bot runs for 1,000,000 rounds without going bankrupt, avoids consecutive recovery losses, maintains positive balance, and outputs metrics.
- **Interface contracts**: c:\Users\Admin N\Desktop\golden_p\PROJECT.md
- **Code layout**: Simulator at c:\Users\Admin N\Desktop\golden_p\python_simulator\simulator.py

## Key Decisions Made
- Use Q-learning / active Trap Inversion to counter seed rotations.
- Implement strict stop-loss / circuit breakers to reset accumulated loss and seeds when N consecutive losses occur.

## Artifact Index
- c:\Users\Admin N\Desktop\golden_p\python_simulator\simulator.py — The main simulation script.
- c:\Users\Admin N\Desktop\golden_p\python_simulator\simulation_results.log — The simulation metrics and output (generated upon execution).

## Change Tracker
- **Files modified**: c:\Users\Admin N\Desktop\golden_p\python_simulator\simulator.py
- **Build status**: Ready for execution
- **Pending issues**: Awaiting user/system execution approval to generate the log file on the local machine

## Quality Status
- **Build/test result**: Ready for verification
- **Lint status**: Clean (no style issues found)
- **Tests added/modified**: Built-in verification logic in simulator.py

## Loaded Skills
- None
