## 2026-07-13T17:40:37+07:00
Please implement the Python Simulator and design the upgraded prediction/recovery algorithms to eliminate consecutive losses and bankruptcy.
Your working directory is: c:\Users\Admin N\Desktop\golden_p\.agents\teamwork_preview_worker_m2_1

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Instructions:
1. Create a Python simulation script in c:\Users\Admin N\Desktop\golden_p\python_simulator\simulator.py.
2. In the simulator:
   - Model the Towers game (3 columns: A, B, C; 2 gems, 1 bomb; payout 1.42x).
   - Implement HMAC-SHA256 seed-based random outcomes (client seed, server seed, nonce) to simulate provably fair games.
   - Implement Casino Trap Seed logic: if the bot places a bet higher than base bet or exhibits a predictable prediction pattern, the casino rotates its seed to place a bomb on the bot's predicted tile.
   - Model the current bot's 6-engine ensemble (NGram, MarkovDodger, Heatmap, AlternatingSeeker, DeepHistoryAnchor, QuantumRNG), weights, V70 inversion, LSTM feedback retraining, and recovery state machine (Ghost betting, Ghost Sniper win counts, and the 10% balance cap).
   - Run a baseline run to demonstrate how the current bot goes bankrupt under Casino Trap Seed conditions.
3. Design and implement the upgraded bot strategy:
   - Upgrade the prediction algorithm (e.g. Q-learning, or pattern tracking and active Trap Inversion to counter seed rotations).
   - Upgrade the risk management framework (e.g. a strict stop-loss / circuit breaker that halts after N consecutive recovery losses and resets the debt, or resets seeds).
4. Run the simulation for 1,000,000 rounds with the upgraded bot.
5. Log output metrics demonstrating the upgraded bot's performance (Win Rate, Max Drawdown, Max Consecutive Losses, and showing that bankruptcy is avoided and balance stays positive).
6. Verify by running the Python simulator script itself and confirming it completes successfully.
7. Send a handoff message back to me (conversation ID a7318c79-099b-4f11-9102-036ad0ec9192) when complete, detailing the paths to the simulator script, logs, and your findings. Update progress.md in your folder after each major step.
