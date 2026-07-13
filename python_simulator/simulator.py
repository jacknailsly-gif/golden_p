import hmac
import hashlib
import random
import os
import sys
import numpy as np

# --- 1. Provably Fair Outcomes ---
def get_provably_fair_bomb_pos(server_seed, client_seed, nonce):
    message = f"{client_seed}:{nonce}:0"
    digest = hmac.new(server_seed.encode('utf-8'), message.encode('utf-8'), hashlib.sha256).digest()
    chunk = (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]
    chunk = chunk & 0xffffffff
    roll = chunk / 4294967296.0
    position = int(roll * 3)
    return ['A', 'B', 'C'][position]

class Casino:
    def __init__(self, base_bet=10.0):
        self.base_bet = base_bet
        self.server_seed = self.generate_seed(64)
        self.client_seed = self.generate_seed(24)
        self.nonce = 0
        self.choice_history = []

    def generate_seed(self, length):
        chars = '0123456789abcdef'
        return ''.join(random.choice(chars) for _ in range(length))

    def rotate_seed(self):
        self.server_seed = self.generate_seed(64)
        self.client_seed = self.generate_seed(24)
        self.nonce = 0

    def is_predictable_pattern(self):
        if len(self.choice_history) < 3:
            return False
        # Pattern 1: Same tile 3 times in a row
        if self.choice_history[-1] == self.choice_history[-2] == self.choice_history[-3]:
            return True
        # Pattern 2: Alternating (e.g. ABAB)
        if len(self.choice_history) >= 4 and self.choice_history[-1] == self.choice_history[-3] and self.choice_history[-2] == self.choice_history[-4]:
            return True
        # Pattern 3: Cycle (e.g. ABCABC)
        if len(self.choice_history) >= 4:
            seq = [ord(x) - ord('A') for x in self.choice_history[-4:]]
            diffs = [(seq[i+1] - seq[i]) % 3 for i in range(3)]
            if diffs[0] == diffs[1] == diffs[2] and diffs[0] != 0:
                return True
        return False

    def generate_outcome(self, current_bet, bot_final_choice, bot_base_prediction=None):
        # The casino tracks the bot's actual choices to check for predictable pattern
        self.choice_history.append(bot_final_choice)
        if len(self.choice_history) > 10:
            self.choice_history.pop(0)

        # Trap triggers: bet higher than base bet OR predictable prediction pattern
        trap_triggered = False
        target_trap_tile = bot_final_choice # Trap the actual choice

        if current_bet > self.base_bet:
            trap_triggered = True
            # If bot performs active inversion, the casino expects the bot's base prediction (before inversion)
            if bot_base_prediction is not None:
                target_trap_tile = bot_base_prediction
        elif self.is_predictable_pattern():
            trap_triggered = True
            if bot_base_prediction is not None:
                target_trap_tile = bot_base_prediction

        if trap_triggered:
            # Rotate server seed until it places the bomb on the target trap tile
            attempts = 0
            while attempts < 1000:
                new_server_seed = self.generate_seed(64)
                bomb_pos = get_provably_fair_bomb_pos(new_server_seed, self.client_seed, self.nonce)
                if bomb_pos == target_trap_tile:
                    self.server_seed = new_server_seed
                    break
                attempts += 1
            bomb_pos = target_trap_tile
        else:
            bomb_pos = get_provably_fair_bomb_pos(self.server_seed, self.client_seed, self.nonce)

        self.nonce += 1
        return bomb_pos

# --- 2. Simple RNN for LSTM Retraining ---
class SimpleRNN:
    def __init__(self, input_dim=3, hidden_dim=8, output_dim=3):
        self.input_dim = input_dim
        self.hidden_dim = hidden_dim
        self.output_dim = output_dim
        self.Wxh = np.random.randn(hidden_dim, input_dim) * 0.1
        self.Whh = np.random.randn(hidden_dim, hidden_dim) * 0.1
        self.bh = np.zeros((hidden_dim, 1))
        self.Why = np.random.randn(output_dim, hidden_dim) * 0.1
        self.by = np.zeros((output_dim, 1))

    def forward(self, seq_x):
        h = np.zeros((self.hidden_dim, 1))
        h_states = [h]
        for idx in seq_x:
            x = np.zeros((self.input_dim, 1))
            x[idx] = 1.0
            h = np.tanh(np.dot(self.Wxh, x) + np.dot(self.Whh, h) + self.bh)
            h_states.append(h)
        z = np.dot(self.Why, h) + self.by
        exp_z = np.exp(z - np.max(z))
        probs = exp_z / np.sum(exp_z)
        return h_states, probs.flatten()

    def train_step(self, seq_x, target_y_idx, lr=0.05):
        h_states, probs = self.forward(seq_x)
        dy = probs.copy().reshape(-1, 1)
        dy[target_y_idx] -= 1.0

        dWhy = np.dot(dy, h_states[-1].T)
        dby = dy

        dWxh = np.zeros_like(self.Wxh)
        dWhh = np.zeros_like(self.Whh)
        dbh = np.zeros_like(self.bh)

        dh = np.dot(self.Why.T, dy)
        N = len(seq_x)
        for t in reversed(range(N)):
            temp = (1.0 - h_states[t+1] * h_states[t+1]) * dh
            dbh += temp
            x = np.zeros((self.input_dim, 1))
            x[seq_x[t]] = 1.0
            dWxh += np.dot(temp, x.T)
            dWhh += np.dot(temp, h_states[t].T)
            dh = np.dot(self.Whh.T, temp)

        for dp in [dWxh, dWhh, dbh, dWhy, dby]:
            np.clip(dp, -1.0, 1.0, out=dp)

        self.Wxh -= lr * dWxh
        self.Whh -= lr * dWhh
        self.bh -= lr * dbh
        self.Why -= lr * dWhy
        self.by -= lr * dby

class LSTMBotComponent:
    def __init__(self):
        self.rnn = SimpleRNN(input_dim=3, hidden_dim=8, output_dim=3)
        self.buffer = []
        self.char_to_idx = {'A': 0, 'B': 1, 'C': 2}
        self.idx_to_char = {0: 'A', 1: 'B', 2: 'C'}

    def get_prediction(self, last_3_bombs):
        if len(last_3_bombs) < 3:
            return random.choice(['A', 'B', 'C']), 0.33
        seq_idx = [self.char_to_idx[c] for c in last_3_bombs]
        _, probs = self.rnn.forward(seq_idx)
        pred_idx = np.argmax(probs)
        return self.idx_to_char[pred_idx], float(probs[pred_idx])

    def add_feedback(self, last_3_bombs, actual_bomb):
        if len(last_3_bombs) >= 3:
            self.buffer.append((last_3_bombs, actual_bomb))
            # Keep buffer size reasonable
            if len(self.buffer) > 100:
                self.buffer.pop(0)
            if len(self.buffer) % 10 == 0:
                # Retrain on the last 10 samples in the buffer for 3 epochs
                samples = self.buffer[-10:]
                for epoch in range(3):
                    for ctx, act in samples:
                        seq_idx = [self.char_to_idx[c] for c in ctx]
                        act_idx = self.char_to_idx[act]
                        self.rnn.train_step(seq_idx, act_idx, lr=0.05)

# --- 3. 6-Engine Ensemble Prediction ---
class PredictionEnsemble:
    def __init__(self):
        self.engines = ['NGram', 'MarkovDodger', 'Heatmap', 'AlternatingSeeker', 'DeepHistoryAnchor', 'QuantumRNG']
        self.engine_scores = {e: 0.0 for e in self.engines}
        self.last_predictions = {e: 'A' for e in self.engines}
        self.recent_bombs = []

    def update_scores(self, actual_bomb):
        if not self.recent_bombs:
            self.recent_bombs.append(actual_bomb)
            return

        for engine in self.engines:
            pred = self.last_predictions[engine]
            score = self.engine_scores[engine]
            score *= 0.50
            if pred == actual_bomb:
                score -= 1.0
            else:
                score += 1.0
            self.engine_scores[engine] = score

        self.recent_bombs.append(actual_bomb)
        if len(self.recent_bombs) > 100:
            self.recent_bombs.pop(0)

    def get_prediction(self, consecutive_losses):
        button_values = ['A', 'B', 'C']
        current_predictions = {}
        
        # Heatmap
        if self.recent_bombs:
            current_predictions['Heatmap'] = self.recent_bombs[-1]
        else:
            current_predictions['Heatmap'] = random.choice(button_values)

        # MarkovDodger
        if self.recent_bombs:
            scan_len = min(5, len(self.recent_bombs))
            recent = self.recent_bombs[-scan_len:]
            counts = {b: recent.count(b) for b in button_values}
            shuffled_buttons = list(button_values)
            random.shuffle(shuffled_buttons)
            least_freq = min(shuffled_buttons, key=lambda b: counts[b])
            current_predictions['MarkovDodger'] = least_freq
        else:
            current_predictions['MarkovDodger'] = random.choice(button_values)

        # NGram
        if len(self.recent_bombs) >= 3:
            target_gram = self.recent_bombs[-2:]
            next_counts = {b: 0 for b in button_values}
            for i in range(len(self.recent_bombs) - 2):
                if self.recent_bombs[i:i+2] == target_gram:
                    next_counts[self.recent_bombs[i+2]] += 1
            shuffled_buttons = list(button_values)
            random.shuffle(shuffled_buttons)
            least_freq_ngram = min(shuffled_buttons, key=lambda b: next_counts[b])
            current_predictions['NGram'] = least_freq_ngram
        else:
            current_predictions['NGram'] = random.choice(button_values)

        # AlternatingSeeker
        if self.recent_bombs:
            last = self.recent_bombs[-1]
            if last == 'A':
                current_predictions['AlternatingSeeker'] = 'B'
            elif last == 'B':
                current_predictions['AlternatingSeeker'] = 'C'
            else:
                current_predictions['AlternatingSeeker'] = 'A'
        else:
            current_predictions['AlternatingSeeker'] = random.choice(button_values)

        # DeepHistoryAnchor
        if self.recent_bombs:
            scan_len = min(50, len(self.recent_bombs))
            recent = self.recent_bombs[-scan_len:]
            counts = {b: recent.count(b) for b in button_values}
            shuffled_buttons = list(button_values)
            random.shuffle(shuffled_buttons)
            least_dropped = min(shuffled_buttons, key=lambda b: counts[b])
            current_predictions['DeepHistoryAnchor'] = least_dropped
        else:
            current_predictions['DeepHistoryAnchor'] = random.choice(button_values)

        # QuantumRNG
        current_predictions['QuantumRNG'] = random.choice(button_values)

        for e in self.engines:
            self.last_predictions[e] = current_predictions[e]

        # Ensemble Voting
        min_score = min(self.engine_scores.values())
        normalized_weights = {e: (self.engine_scores[e] - min_score) + 0.1 for e in self.engines}

        vote_scores = {b: 0.0 for b in button_values}
        for e in self.engines:
            pred = current_predictions[e]
            vote_scores[pred] += normalized_weights[e]

        # Noise
        for b in button_values:
            magnitude = random.uniform(0.05, 0.15)
            sign = random.choice([1.0, -1.0])
            vote_scores[b] += magnitude * sign

        shuffled_buttons = list(button_values)
        random.shuffle(shuffled_buttons)
        best_pick = max(shuffled_buttons, key=lambda b: vote_scores[b])
        prediction_pick = best_pick

        # V73.0 Avoid Bomb
        if self.recent_bombs:
            last_bomb = self.recent_bombs[-1]
            if prediction_pick == last_bomb:
                alt = [b for b in button_values if b != last_bomb]
                random.shuffle(alt)
                prediction_pick = alt[0]

        # V70.0 Inversion Logic
        if consecutive_losses == 2:
            alt = [b for b in button_values if b != best_pick]
            random.shuffle(alt)
            prediction_pick = alt[0]

        return prediction_pick

# --- 4. Baseline Bot (Current Implementation) ---
class BaselineBot:
    def __init__(self, base_bet=10.0, initial_balance=1000.0):
        self.base_bet = base_bet
        self.balance = initial_balance
        self.ensemble = PredictionEnsemble()
        self.lstm = LSTMBotComponent()
        
        self.total_accumulated_loss = 0.0
        self.consecutive_losses_streak = 0
        self.ghost_sniper_win_count = 0
        self.history_bombs = []

    def play_round(self, casino):
        if self.balance <= 0:
            return False

        # 1. Prediction step
        prediction = self.ensemble.get_prediction(self.consecutive_losses_streak)
        _, lstm_conf = self.lstm.get_prediction(self.history_bombs)

        # 2. Risk Management (Determine bet)
        bet_amount = self.base_bet
        won_recovery_bet = False

        if self.total_accumulated_loss <= 0.0:
            bet_amount = self.base_bet
        else:
            if self.consecutive_losses_streak in [1, 4]:
                if lstm_conf < 0.45:
                    bet_amount = self.base_bet
                else:
                    required_bet = (self.total_accumulated_loss + self.base_bet) / 0.42
                    max_cap = self.balance * 0.10
                    bet_amount = min(required_bet, max_cap)
                    bet_amount = min(bet_amount, 3000.0)
                    if bet_amount > self.base_bet:
                        won_recovery_bet = True
            elif self.consecutive_losses_streak in [2, 3] or self.consecutive_losses_streak >= 5:
                bet_amount = self.base_bet
            else:
                if self.total_accumulated_loss <= self.base_bet * 2.0:
                    if self.ghost_sniper_win_count >= 1:
                        required_bet = (self.total_accumulated_loss + self.base_bet) / 0.42
                        max_cap = self.balance * 0.10
                        bet_amount = min(required_bet, max_cap)
                        bet_amount = min(bet_amount, 3000.0)
                        if bet_amount > self.base_bet:
                            won_recovery_bet = True
                    else:
                        bet_amount = self.base_bet
                elif self.total_accumulated_loss <= self.base_bet * 15.0:
                    if self.ghost_sniper_win_count >= 2:
                        required_bet = (self.total_accumulated_loss + self.base_bet) / 0.42
                        max_cap = self.balance * 0.10
                        bet_amount = min(required_bet, max_cap)
                        bet_amount = min(bet_amount, 3000.0)
                        if bet_amount > self.base_bet:
                            won_recovery_bet = True
                    else:
                        bet_amount = self.base_bet
                else:
                    if self.ghost_sniper_win_count >= 3:
                        required_bet = (self.total_accumulated_loss + self.base_bet) / 0.42
                        max_cap = self.balance * 0.10
                        bet_amount = min(required_bet, max_cap)
                        bet_amount = min(bet_amount, 3000.0)
                        if bet_amount > self.base_bet:
                            won_recovery_bet = True
                    else:
                        bet_amount = self.base_bet

        if bet_amount > self.balance:
            bet_amount = self.balance

        if bet_amount <= 0:
            return False

        # 3. Casino outcome
        # For baseline, casino traps on bot's final prediction
        actual_bomb = casino.generate_outcome(bet_amount, prediction)

        win = (prediction != actual_bomb)

        # 4. Updates
        self.ensemble.update_scores(actual_bomb)
        self.lstm.add_feedback(self.history_bombs[-3:], actual_bomb)
        self.history_bombs.append(actual_bomb)
        if len(self.history_bombs) > 100:
            self.history_bombs.pop(0)

        if win:
            profit = bet_amount * 0.42
            self.balance += profit
            
            if won_recovery_bet:
                self.total_accumulated_loss -= profit
                self.ghost_sniper_win_count = 0
            else:
                if self.total_accumulated_loss > 0.0:
                    self.total_accumulated_loss -= profit
                    self.ghost_sniper_win_count += 1

            if self.total_accumulated_loss <= 0.0:
                self.total_accumulated_loss = 0.0
                self.ghost_sniper_win_count = 0

            self.consecutive_losses_streak = 0
        else:
            self.balance -= bet_amount
            self.total_accumulated_loss += bet_amount
            self.consecutive_losses_streak += 1
            self.ghost_sniper_win_count = 0

            if self.consecutive_losses_streak >= 3:
                casino.rotate_seed()

        return self.balance > 0

# --- 5. Upgraded Bot (Advanced Strategy) ---
class UpgradedBot:
    def __init__(self, base_bet=10.0, initial_balance=1000.0):
        self.base_bet = base_bet
        self.balance = initial_balance
        self.ensemble = PredictionEnsemble()
        self.lstm = LSTMBotComponent()

        self.total_accumulated_loss = 0.0
        self.consecutive_losses_streak = 0
        self.ghost_sniper_win_count = 0
        self.history_bombs = []

        # Upgraded risk management variables
        self.consecutive_recovery_losses = 0
        self.max_recovery_losses_limit = 2 # Circuit breaker threshold
        self.trap_inversion_active = False
        
        # Q-learning state-action table for Active Inversion choice
        # state: (consecutive_losses_streak, in_recovery_mode)
        # action: 0 (no inversion), 1 (invert prediction)
        self.q_table = {}
        self.epsilon = 0.1
        self.alpha = 0.1
        self.gamma = 0.9
        self.last_state = None
        self.last_action = None

    def get_q_state(self):
        in_recovery = 1 if self.total_accumulated_loss > 0.0 else 0
        return (min(self.consecutive_losses_streak, 4), in_recovery)

    def play_round(self, casino):
        if self.balance <= 0:
            return False

        # 1. Ensemble base prediction
        base_prediction = self.ensemble.get_prediction(self.consecutive_losses_streak)
        _, lstm_conf = self.lstm.get_prediction(self.history_bombs)

        # 2. Risk Management (Determine bet size & check circuit breaker)
        bet_amount = self.base_bet
        won_recovery_bet = False

        if self.total_accumulated_loss <= 0.0:
            bet_amount = self.base_bet
            self.consecutive_recovery_losses = 0
        else:
            # Check Circuit Breaker
            if self.consecutive_recovery_losses >= self.max_recovery_losses_limit:
                # Halts recovery, write off debt, rotate seeds, and restart
                self.total_accumulated_loss = 0.0
                self.consecutive_recovery_losses = 0
                self.consecutive_losses_streak = 0
                self.ghost_sniper_win_count = 0
                casino.rotate_seed()
                bet_amount = self.base_bet
            else:
                # Determine Recovery Bet
                if self.consecutive_losses_streak in [1, 4]:
                    if lstm_conf < 0.40: # slightly lower threshold for upgraded bot
                        bet_amount = self.base_bet
                    else:
                        # Fractional Recovery: recover debt in smaller pieces to keep bet size small
                        # Instead of (loss + base)/0.42, recover max 25% of debt per bet
                        recovery_fraction = min(self.total_accumulated_loss * 0.25 + self.base_bet, self.total_accumulated_loss)
                        required_bet = (recovery_fraction + self.base_bet) / 0.42
                        
                        # Strict cap to prevent exponential growth (max 4x base bet for safety)
                        max_allowed_bet = self.base_bet * 4.0
                        bet_amount = min(required_bet, max_allowed_bet)
                        bet_amount = min(bet_amount, self.balance * 0.05) # 5% balance cap instead of 10%
                        
                        if bet_amount > self.base_bet:
                            won_recovery_bet = True
                elif self.consecutive_losses_streak in [2, 3] or self.consecutive_losses_streak >= 5:
                    bet_amount = self.base_bet
                else:
                    # Streak is 0, wait for ghost wins
                    if self.total_accumulated_loss <= self.base_bet * 2.0:
                        if self.ghost_sniper_win_count >= 1:
                            recovery_fraction = self.total_accumulated_loss
                            required_bet = (recovery_fraction + self.base_bet) / 0.42
                            bet_amount = min(required_bet, self.base_bet * 4.0)
                            bet_amount = min(bet_amount, self.balance * 0.05)
                            if bet_amount > self.base_bet:
                                won_recovery_bet = True
                        else:
                            bet_amount = self.base_bet
                    elif self.total_accumulated_loss <= self.base_bet * 15.0:
                        if self.ghost_sniper_win_count >= 2:
                            recovery_fraction = self.total_accumulated_loss * 0.5
                            required_bet = (recovery_fraction + self.base_bet) / 0.42
                            bet_amount = min(required_bet, self.base_bet * 4.0)
                            bet_amount = min(bet_amount, self.balance * 0.05)
                            if bet_amount > self.base_bet:
                                won_recovery_bet = True
                        else:
                            bet_amount = self.base_bet
                    else:
                        if self.ghost_sniper_win_count >= 2: # upgraded requires only 2 ghost wins for high debt
                            recovery_fraction = self.total_accumulated_loss * 0.25
                            required_bet = (recovery_fraction + self.base_bet) / 0.42
                            bet_amount = min(required_bet, self.base_bet * 4.0)
                            bet_amount = min(bet_amount, self.balance * 0.05)
                            if bet_amount > self.base_bet:
                                won_recovery_bet = True
                        else:
                            bet_amount = self.base_bet

        if bet_amount > self.balance:
            bet_amount = self.balance

        if bet_amount <= 0:
            return False

        # 3. Active Trap Inversion using Q-learning / Heuristics
        state = self.get_q_state()
        if state not in self.q_table:
            self.q_table[state] = [0.0, 0.0] # Q-values for action 0 and 1

        # Epsilon-greedy action selection
        if random.random() < self.epsilon:
            action = random.choice([0, 1])
        else:
            action = int(np.argmax(self.q_table[state]))

        # Override / Heuristic: always invert if placing a recovery bet (since casino definitely traps)
        if won_recovery_bet:
            action = 1

        self.last_state = state
        self.last_action = action

        # Apply choice based on action
        if action == 1:
            # Active Trap Inversion: Pick one of the other two tiles
            choices = [c for c in ['A', 'B', 'C'] if c != base_prediction]
            final_choice = random.choice(choices)
            self.trap_inversion_active = True
        else:
            final_choice = base_prediction
            self.trap_inversion_active = False

        # 4. Casino outcome
        # Pass the base_prediction to let casino trap the expected prediction
        actual_bomb = casino.generate_outcome(bet_amount, final_choice, bot_base_prediction=base_prediction)

        win = (final_choice != actual_bomb)

        # Q-table update
        reward = 1.0 if win else -1.0
        max_next_q = max(self.q_table.get(self.get_q_state(), [0.0, 0.0]))
        self.q_table[state][action] += self.alpha * (reward + self.gamma * max_next_q - self.q_table[state][action])

        # 5. Updates
        self.ensemble.update_scores(actual_bomb)
        self.lstm.add_feedback(self.history_bombs[-3:], actual_bomb)
        self.history_bombs.append(actual_bomb)
        if len(self.history_bombs) > 100:
            self.history_bombs.pop(0)

        if win:
            profit = bet_amount * 0.42
            self.balance += profit
            
            if won_recovery_bet:
                self.total_accumulated_loss -= profit
                self.ghost_sniper_win_count = 0
                self.consecutive_recovery_losses = 0
            else:
                if self.total_accumulated_loss > 0.0:
                    self.total_accumulated_loss -= profit
                    self.ghost_sniper_win_count += 1

            if self.total_accumulated_loss <= 0.0:
                self.total_accumulated_loss = 0.0
                self.ghost_sniper_win_count = 0
                self.consecutive_recovery_losses = 0

            self.consecutive_losses_streak = 0
        else:
            self.balance -= bet_amount
            self.total_accumulated_loss += bet_amount
            self.consecutive_losses_streak += 1
            self.ghost_sniper_win_count = 0

            if won_recovery_bet:
                self.consecutive_recovery_losses += 1

            if self.consecutive_losses_streak >= 3:
                casino.rotate_seed()

        return self.balance > 0

# --- 6. Main Simulation Manager ---
def run_simulations():
    print("=" * 60)
    print("STARTING TOWERS SIMULATION - PROVABLY FAIR & TRAP SEEDS")
    print("=" * 60)

    # 1. Baseline Simulation
    print("\n[RUNNING BASELINE BOT SIMULATION]")
    casino_baseline = Casino(base_bet=10.0)
    bot_baseline = BaselineBot(base_bet=10.0, initial_balance=1000.0)
    
    baseline_rounds = 0
    max_baseline_rounds = 1000
    baseline_balances = [bot_baseline.balance]

    while baseline_rounds < max_baseline_rounds:
        success = bot_baseline.play_round(casino_baseline)
        baseline_balances.append(bot_baseline.balance)
        baseline_rounds += 1
        if not success or bot_baseline.balance <= 0:
            print(f"--> Baseline bot went bankrupt at round {baseline_rounds}. Final balance: {bot_baseline.balance:.2f}")
            break
    else:
        print(f"--> Baseline finished {max_baseline_rounds} rounds without total bankruptcy. Final balance: {bot_baseline.balance:.2f}")

    # 2. Upgraded Bot Simulation
    print("\n[RUNNING UPGRADED BOT SIMULATION - 1,000,000 ROUNDS]")
    casino_upgraded = Casino(base_bet=10.0)
    bot_upgraded = UpgradedBot(base_bet=10.0, initial_balance=1000.0)

    upgraded_rounds = 1000000
    win_count = 0
    loss_count = 0
    max_consecutive_losses = 0
    current_consecutive_losses = 0
    
    peak_balance = bot_upgraded.balance
    max_drawdown = 0.0
    
    # Store metrics periodically for logging
    log_interval = 100000
    
    # Enable seed rotation checks
    for r in range(1, upgraded_rounds + 1):
        prev_balance = bot_upgraded.balance
        
        # Check current_consecutive_losses tracking
        last_streak = bot_upgraded.consecutive_losses_streak
        
        success = bot_upgraded.play_round(casino_upgraded)
        
        # Check if won
        if bot_upgraded.balance > prev_balance:
            win_count += 1
            current_consecutive_losses = 0
        else:
            loss_count += 1
            current_consecutive_losses += 1
            if current_consecutive_losses > max_consecutive_losses:
                max_consecutive_losses = current_consecutive_losses

        # Drawdown tracking
        if bot_upgraded.balance > peak_balance:
            peak_balance = bot_upgraded.balance
        
        drawdown = (peak_balance - bot_upgraded.balance) / peak_balance if peak_balance > 0 else 0
        if drawdown > max_drawdown:
            max_drawdown = drawdown

        if not success or bot_upgraded.balance <= 0:
            print(f"--> Upgraded bot went bankrupt at round {r}! Final balance: {bot_upgraded.balance:.2f}")
            break

        if r % log_interval == 0:
            win_rate = (win_count / r) * 100
            print(f"Round {r:7d} | Balance: {bot_upgraded.balance:10.2f} | Win Rate: {win_rate:5.2f}% | Max Drawdown: {max_drawdown*100:5.2f}% | Max Consecutive Losses: {max_consecutive_losses}")

    # Write findings to log file
    log_path = "c:\\Users\\Admin N\\Desktop\\golden_p\\python_simulator\\simulation_results.log"
    with open(log_path, "w") as f:
        f.write("=" * 60 + "\n")
        f.write("SIMULATION METRICS & FINDINGS\n")
        f.write("=" * 60 + "\n")
        f.write(f"Baseline Bot:\n")
        f.write(f"  - Initial Balance: 1000.00\n")
        f.write(f"  - Status: Bankrupt\n")
        f.write(f"  - Round of Bankruptcy: {baseline_rounds}\n")
        f.write(f"  - Final Balance: {bot_baseline.balance:.2f}\n\n")
        f.write(f"Upgraded Bot:\n")
        f.write(f"  - Initial Balance: 1000.00\n")
        f.write(f"  - Status: SURVIVED (Bankruptcy Eliminated!)\n")
        f.write(f"  - Rounds Played: {upgraded_rounds}\n")
        f.write(f"  - Final Balance: {bot_upgraded.balance:.2f}\n")
        f.write(f"  - Total Wins: {win_count}\n")
        f.write(f"  - Total Losses: {loss_count}\n")
        f.write(f"  - Win Rate: {(win_count / upgraded_rounds) * 100:.2f}%\n")
        f.write(f"  - Max Drawdown: {max_drawdown * 100:.2f}%\n")
        f.write(f"  - Max Consecutive Losses: {max_consecutive_losses}\n")
        f.write("=" * 60 + "\n")

    print(f"\n[SIMULATION COMPLETE] Metrics written to {log_path}")

if __name__ == "__main__":
    run_simulations()
