import os
import glob
import json
import random
import copy
import sys

DATA_DIR = "./training_data/golden_p_training_data"
OUTPUT_FILE = "optimized_params.json"
STATE_FILE = "ai_state.json"

def analyze_data():
    csv_files = glob.glob(os.path.join(DATA_DIR, "*.csv"))
    
    total_rounds = 0
    total_wins = 0
    max_loss_streak = 0
    current_loss_streak = 0
    start_balance = None
    end_balance = None
    
    # Process CSV files
    for f in sorted(csv_files):
        with open(f, 'r', encoding='utf-8') as file:
            lines = file.readlines()
            if len(lines) > 1:
                total_rounds += (len(lines) - 1)
                for line in lines[1:]:
                    parts = line.strip().split(',')
                    if len(parts) >= 21:
                        # was_correct is index 20
                        # balance is index 13
                        was_correct = parts[20] == '1'
                        balance = float(parts[13])
                        
                        if start_balance is None:
                            start_balance = balance
                        end_balance = balance
                        
                        if was_correct:
                            total_wins += 1
                            current_loss_streak = 0
                        else:
                            current_loss_streak += 1
                            if current_loss_streak > max_loss_streak:
                                max_loss_streak = current_loss_streak
                                
    accuracy = (total_wins / total_rounds) * 100 if total_rounds > 0 else 0
    balance_growth = (end_balance - start_balance) if (start_balance and end_balance) else 0

    print(f"[ML AI] Analyzed {total_rounds} rounds.")
    print(f"[ML AI] Win Rate: {accuracy:.2f}% | Max Loss Streak: {max_loss_streak} | Balance Diff: {balance_growth:.8f}")

    # Load State
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            state = json.load(f)
    else:
        # Default starting state
        state = {
            "best_fitness": -999999,
            "best_params": {
                "memory_decay_rate": 0.50,
                "prediction_reward": 1.0,
                "prediction_penalty": -1.0,
                "vote_noise_max": 0.05,
                "hmac_threshold": 0.15,
                "bomb_history_window": 12,
                "loss_history_window": 5,
                "v70_inversion_streak": 3,
                "deep_history_window": 50,
                "vote_weight_floor": 0.10
            },
            "current_params": None,
            "generation": 0,
            "reports": []
        }
        state["current_params"] = copy.deepcopy(state["best_params"])

    # Calculate Fitness of current run
    # Fitness criteria: 
    # 1. High penalty if max_loss_streak > 3
    # 2. Reward for balance growth
    # 3. Reward for accuracy
    
    fitness = balance_growth * 1000  # Prioritize profit
    fitness += (accuracy * 2) # Secondary is accuracy
    
    # Severe penalty for high risk
    if max_loss_streak > 3:
        fitness -= ((max_loss_streak - 3) * 50)
        
    print(f"[ML AI] Generation {state['generation']} Fitness: {fitness:.2f}")
    
    # Update Best Params
    if fitness >= state["best_fitness"] and total_rounds > 10:
        print("[ML AI] New Best Parameters Found!")
        state["best_fitness"] = fitness
        state["best_params"] = copy.deepcopy(state["current_params"])
    elif total_rounds > 10:
        print("[ML AI] Performance dropped. Reverting to best parameters.")
        state["current_params"] = copy.deepcopy(state["best_params"])

    # Mutate
    print("[ML AI] Mutating parameters for next generation...")
    new_params = copy.deepcopy(state["current_params"])
    
    # Mutate 2 random parameters
    keys = list(new_params.keys())
    for _ in range(2):
        key = random.choice(keys)
        if isinstance(new_params[key], float):
            mutation_amt = new_params[key] * random.uniform(-0.1, 0.1) # +/- 10%
            new_params[key] = round(new_params[key] + mutation_amt, 2)
        elif isinstance(new_params[key], int):
            mutation_amt = random.choice([-1, 0, 1])
            new_params[key] += mutation_amt
            
    # Bounds check
    new_params["memory_decay_rate"] = max(0.1, min(0.9, new_params["memory_decay_rate"]))
    new_params["vote_noise_max"] = max(0.01, min(0.2, new_params["vote_noise_max"]))
    new_params["v70_inversion_streak"] = max(2, min(5, new_params["v70_inversion_streak"]))
    new_params["deep_history_window"] = max(10, min(100, new_params["deep_history_window"]))
    
    state["current_params"] = new_params
    state["generation"] += 1
    
    # Log report for external monitoring
    state["reports"].append({
        "generation": state["generation"] - 1,
        "rounds": total_rounds,
        "win_rate": round(accuracy, 2),
        "max_loss_streak": max_loss_streak,
        "balance_diff": balance_growth,
        "current_balance": end_balance,
        "fitness": round(fitness, 2)
    })
    
    # Keep last 10 reports
    state["reports"] = state["reports"][-10:]
    
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=4)
        
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(new_params, f, indent=4)
        
    print(f"[ML AI] Generated optimized parameters -> {OUTPUT_FILE}")

if __name__ == "__main__":
    analyze_data()
