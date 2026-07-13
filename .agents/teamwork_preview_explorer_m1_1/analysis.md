# Towers Game Bot Codebase Analysis and Python Simulator Design

## 1. Executive Summary
This report provides a comprehensive read-only architectural analysis of the Towers game bot codebase. The bot uses a Flutter/Dart frontend and a Flask/Python backend to automate betting and predict safe tiles in a 3-choice Towers game (Towers of 3 columns: A, B, C, containing 2 gems and 1 bomb per row). 

Key findings include:
- **Prediction Architecture**: An advanced hybrid setup combining a local 6-engine ensemble (NGram, MarkovDodger, Heatmap, AlternatingSeeker, DeepHistoryAnchor, QuantumRNG) with real-time feedback retraining of an LSTM neural network model on a Python server.
- **Bet Recovery System**: An AI-governed fractional recovery system utilizing "Ghost Bets" (minimum bets) to reveal seeds and "Ghost Sniper" win requirements to mitigate risk before firing large recovery bets.
- **Test Suite Flaw**: The test suite is currently failing due to a setup bug in the tests where `_isSmartMode` is not set to `true`, causing the bot to run in custom sequence mode (doing nothing) and fail active behavior assertions.
- **Bankruptcy Vulnerabilities**: Martingale-style recovery bet escalation still exhibits exponential debt growth on consecutive recovery failures. Under heavy drawdowns, the 10% balance cap restricts recovery potential, turning a sudden crash into a slow bleed to bankruptcy. Furthermore, if the casino uses a dynamic "Trap Seed" based on player history or seed tracking, it can easily snipe the bot's predictable HMAC predictions.

---

## 2. Detailed Code Review

### 2.1 Viewmodels (`sequence_analyzer_viewmodel.dart` & `overlay_buttons_viewmodel.dart`)
- **`SequenceAnalyzerViewModel`**:
  - Manages the UI state, balance tracking, and the integration of the TFLite model.
  - Implements **Anti-Streak Architecture (Cognitive 5.0)**: tracks pattern predictability (entropy) and blacklists failing hypotheses.
  - Implements **Deep Scan V3.0 (Predator Protocol)**: monitors bomb migration patterns and Saturation Points (SP) where a gem has appeared consecutively at a position. In "Trap Mode" (detected when incorrect streak >= 2 and predictability > 0.6), it inverts safety probabilities.
  - Implements a **Feedback Loop**: sends context (last 3 inputs), predicted position, and actual outcomes to `/feedback` on the Python server after each round.
- **`OverlayButtonsViewModel`**:
  - Handles the autoplay loop (`_executeSmartFlow` and `_executeSequence`) and visual outcome detection.
  - Controls bet sizes using two recovery modes (Rhythm vs. Profit Boost).
  - Implements the **V96.1 Balance Reconciliation Guard (Self-Healing)**: adjusts `_totalAccumulatedLoss` based on real-time balance deviations from the peak balance, preventing the bot from over-betting or running out of sync.
  - Implements **Bot Detection Avoidance**: humanized reaction delays (jitter), strategic random noise rounds (Ghost Rounds), and mandatory session breaks (8-16 mins break after 60 mins of play).

### 2.2 Prediction Engines & Pipeline (`prediction_pipeline_service.dart` & `provably_fair_engine.dart`)
- **`PredictionPipelineService`**:
  - Runs a **6-Engine Ensemble**:
    1. *NGram*: Looks at the last 2-bomb sequence and predicts the least frequent bomb that followed it.
    2. *MarkovDodger*: Avoids the most frequent bomb in the last 5 rounds.
    3. *Heatmap*: Bets on the box that just bombed, assuming it is safe.
    4. *AlternatingSeeker*: Assumes the bomb moves in a cycle (A -> B -> C -> A) and predicts the next safe box.
    5. *DeepHistoryAnchor*: Bets on the safest box (fewest bombs) in the last 50 rounds.
    6. *QuantumRNG*: Generates random picks.
  - **Ensemble Voting (Wisdom of the Crowds)**: Computes weighted votes using engine performance scores. It adds non-deterministic noise ($\pm 0.05$ to $0.15$) to voting scores to prevent pattern detection by the casino.
  - **V73 Bomb Avoidance**: Refuses to predict the exact box that just bombed.
  - **V70 Inversion Logic**: If `incorrectStreak == 2`, the bot inverts its prediction to evade casino counter-strategies.
- **`ProvablyFairEngine`**:
  - A local singleton that generates pseudo-random predictions using HMAC-SHA256 of `_clientSeed:$_nonce:0` with `_serverSeed` as the key.
  - *Note*: This is purely client-side simulation; it does not synchronize with the casino's actual seeds.

### 2.3 Python Utilities (`model.py` & `server.py`)
- **`model.py`**:
  - Prepares training data by converting letters (A, B, C) to integers.
  - Builds and trains a basic LSTM neural network model (LSTM with 50 units, Dense output layer with softmax).
  - Converts the trained model to TensorFlow Lite (`model.tflite`) with custom ops enabled.
- **`server.py`**:
  - Runs a Flask server on port 5000.
  - Receives live game outcomes at `/feedback`, appends them to a training buffer, and saves them to `training_data.json`.
  - Automatically retrains the LSTM model (15 epochs, batch size 4) every 10 new samples, converts it to TFLite, and signals the Dart app that `model_updated: true`.
  - Serves the updated model via `/model`, which the Dart app downloads and loads into memory dynamically.

### 2.4 Existing Tests Review (`anti_tracking_test.dart` & `losing_streak_test.dart`)
- **State Machine Verification**: Tests successfully verify that prediction mode transitions from `copy_user` to `ai_model` on a loss, and panic-resets to `copy_user` after 2 consecutive AI losses.
- **Test Setup Bug**:
  - The tests `Verify bot outputs contain enough entropy to evade tracking`, `Strict 3-Loss circuit breaker verification with Hostile/Sniping mode`, and `R2: Strict 3-Loss Hard Limit / Circuit Breaker reload and halt` fail.
  - This is because `SharedPreferences` mock values are empty, initializing `_isSmartMode` to `false`. The tests call `startSequence()` but never set `_isSmartMode = true`.
  - As a result, the bot runs `_executeSequence()`, which loops indefinitely doing nothing because `_sequenceSteps` is empty. The tests either time out or assertions fail due to `rounds = 0` and `consecutiveLossesStreak = 0`.
  - If smart mode were enabled, the circuit breaker would trigger a WebView reload and stop auto-play upon reaching exactly 3 consecutive losses.

---

## 3. Bot Rules & Mechanics

### 3.1 Prediction Mode Transition
The bot switches prediction modes dynamically to adapt to losing streaks:
1. Starts in **`copy_user`** mode: outputs the last clicked position or actual result.
2. If the `copy_user` prediction fails, it immediately transitions to **`ai_model`** mode to query the hybrid ensemble pipeline.
3. In `ai_model` mode:
   - A correct prediction resets the `incorrectStreak` to 0 and keeps the bot in `ai_model` mode.
   - If the bot loses 2 consecutive rounds in `ai_model` mode, it triggers a **panic switch** back to `copy_user` mode.

### 3.2 Bet Adjustment & Recovery Formulas
Towers game payout on a correct guess is $1.42\times$ the bet size, meaning net profit per correct guess is $0.42 \times \text{Bet}$.
- **Base Bet**: Desired profit unit ($B$), locked at session start from WebView.
- **Debt Tracking**: Accumulated net loss ($L$), calculated dynamically.
- **Recovery Bet Formula**:
  $$\text{Required Bet} = \frac{L + B}{0.42}$$
- **Bet Caps**:
  - **10% Balance Cap**: $\text{Bet} = \min(\text{Required Bet}, \text{Current Balance} \times 0.10)$
  - **Casino Absolute Cap**: $\text{Bet} = \min(\text{Bet}, 3000.0)$

### 3.3 Ghost Betting and Ghost Sniper win requirements
To prevent large bet drawdowns, the bot uses **Ghost Betting** (betting the minimum unit $B$ instead of the escalated recovery amount) to probe the game seed safely:
- **Loss Streak 1**: Place recovery bet ($L = \text{Debt}$).
- **Loss Streak 2**: Ghost Bet (stay at base bet to observe).
- **Loss Streak 3**: Ghost Bet.
- **Loss Streak 4**: Recovery bet (Sniper Strike).
- **Loss Streak $\ge$ 5**: Ghost Bet.
- **Pending Debt ($L > 0$) on Loss Streak 0** (following a win):
  The bot must confirm a streak of **Ghost Wins** (wins at base bet) before it is allowed to strike again:
  - *Low Debt* ($L \le 2B$): Requires **1 Ghost Win**.
  - *Medium Debt* ($L \le 15B$): Requires **2 Ghost Wins**.
  - *High Debt* ($L > 15B$): Requires **3 Ghost Wins**.
  Once the required Ghost Wins are achieved, the bot escalates the bet to the recovery amount.

---

## 4. Vulnerabilities & Bankruptcy Risks

1. **Negative Expected Value (EV)**:
   Because the bot does not actually know the casino's server seed, its predictions behave as pseudo-random picks. The mathematical win rate is exactly $2/3$ ($66.67\%$). The EV per round is:
   $$\text{EV} = \left(\frac{2}{3} \times 1.42\right) + \left(\frac{1}{3} \times 0\right) = 0.9467 \implies -5.33\% \text{ House Edge}$$
   In the long run, any martingale or recovery progression on a negative EV game is mathematically guaranteed to result in bankruptcy.
2. **Exponential Recovery Bet Escalation**:
   While Ghost Bets slow down the decay, the debt still grows with each loss. Once the ghost sniper win requirements are met, the recovery bet is placed. If that recovery bet fails, the debt jumps drastically, escalating subsequent recovery bets exponentially until they hit the balance cap.
3. **The Balance Cap Trap**:
   When the recovery bet exceeds 10% of the balance, the cap forces the bet down. A capped bet can no longer recover the entire debt in a single win. The bot is forced to win multiple high-risk capped bets in a row, leading to a slow, irreversible bleed to bankruptcy.
4. **Casino Trap Seeds**:
   Online casinos using provably fair systems can implement "Trap Seeds." When the casino detects a player pattern or a sudden high-bet recovery step, it can dynamically rotate the server seed to a hash that places a bomb on the player's most likely choice (based on HMAC or LSTM prediction models).

---

## 5. Python Simulator Design

To evaluate the bot's profitability, risk threshold, and vulnerability to seed manipulation, we should build a Python simulator.

### 5.1 Game Engine
The game engine must model a single-tier Towers game:
- **Row state**: 3 slots (0, 1, 2) representing A, B, C.
- **Bomb placement**: 1 slot contains a bomb, 2 slots contain gems.
- **Payout**: $1.42\times$ on picking a gem; $0\times$ and round termination on picking a bomb.

### 5.2 Casino Seed & HMAC Simulation
To model provably fair mechanics:
- **Seeds**: Maintain `server_seed` (hex string) and `client_seed` (string).
- **Nonce**: Increments by 1 every round.
- **Bomb Generation**:
  ```python
  import hmac
  import hashlib

  def get_bomb_position(server_seed, client_seed, nonce):
      message = f"{client_seed}:{nonce}:0"
      digest = hmac.new(server_seed.encode(), message.encode(), hashlib.sha256).digest()
      # Convert first 4 bytes to unsigned integer
      val = int.from_bytes(digest[:4], byteorder='big')
      roll = val / 4294967296.0
      # 0 = A, 1 = B, 2 = C is the bomb position
      bomb_pos = int(roll * 3)
      return ['A', 'B', 'C'][bomb_pos]
  ```

### 5.3 Casino Trap Seed Behavior
To simulate hostile casino behavior trying to trap the bot:
1. **Dynamic Sniping**:
   If the simulator's casino detects a bet size above a threshold (e.g. $> 1.5 \times \text{Base Bet}$), it generates a `trap_server_seed` that forces the bomb to appear at the bot's predicted slot.
2. **Pattern Matching**:
   The simulated casino tracks the bot's prediction history and changes the server seed to maximize bomb collisions when the bot's bet is high.

### 5.4 Bot Simulation Components
Model all Dart bot components in Python:
- **LSTM Predictor**: Implement the LSTM model structure from `model.py` and run retraining every 10 rounds using simulated feedback.
- **6-Engine Ensemble**: Recreate `PredictionPipelineService` (NGram, MarkovDodger, Heatmap, AlternatingSeeker, DeepHistoryAnchor, QuantumRNG) and update their scores, weights, and voting.
- **Inversion & Bomb Avoidance**:
  - Apply V70 Inversion (if incorrect streak == 2).
  - Apply V73 Bomb Avoidance (refuse to pick the last bomb).
  - Apply V101 Trap Inverter (shift prediction if bet size is high).
- **Recovery State Machine**:
  - Track `balance`, `debt`, `consecutive_losses`, `ghost_sniper_wins`, and `locked_base_bet`.
  - Calculate bet size using the recovery bet formula, applying the 10% balance cap.
  - Implement the Ghost Sniper logic (waiting for 1, 2, or 3 ghost wins before placing a recovery bet).

### 5.5 Monte Carlo Experiments
Run simulations across 100,000 rounds to track:
- **Bankruptcy Rate**: Percentage of runs reaching zero balance.
- **Drawdown Curve**: Maximum peak-to-trough balance drop.
- **Optimal Cap**: Analyze if capping bets at 5% or 15% is safer than 10%.
- **Trap Evading Efficiency**: Compare win rates under dynamic Trap Seed conditions with and without the V101 Trap Inverter.
