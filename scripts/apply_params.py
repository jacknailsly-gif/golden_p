import os
import json
import re
import shutil
import datetime

OUTPUT_FILE = "optimized_params.json"
DART_DIR = "./lib"

def update_file(filepath, patterns):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Backup
    backup_name = f"{filepath}.backup_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}"
    shutil.copy(filepath, backup_name)

    modified_content = content
    for pattern, replacement in patterns:
        modified_content = re.sub(pattern, replacement, modified_content)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(modified_content)
        
    print(f"[Injector] Updated {filepath}")

def apply_params():
    if not os.path.exists(OUTPUT_FILE):
        print(f"[Injector] File not found: {OUTPUT_FILE}")
        return

    with open(OUTPUT_FILE, 'r') as f:
        params = json.load(f)

    # 1. Update provably_fair_engine.dart
    pf_path = os.path.join(DART_DIR, "engines", "provably_fair_engine.dart")
    pf_patterns = [
        (r'(int _maxBombHistory = )\d+;', f'\\g<1>{params["bomb_history_window"]};'),
        (r'(int _maxLossHistory = )\d+;', f'\\g<1>{params["loss_history_window"]};'),
        (r'(dangerDifference < )0\.\d+', f'\\g<1>{params["hmac_threshold"]}')
    ]
    if os.path.exists(pf_path):
        update_file(pf_path, pf_patterns)
        
    # 2. Update prediction_pipeline_service.dart
    pps_path = os.path.join(DART_DIR, "services", "prediction_pipeline_service.dart")
    pps_patterns = [
        (r'(currentScore \*= )0\.\d+;', f'\\g<1>{params["memory_decay_rate"]};'),
        (r'(currentScore -= )1\.0;', f'\\g<1>{params["prediction_penalty"] * -1.0};'), # Since it's negative in JSON
        (r'(currentScore \+= )1\.0;', f'\\g<1>{params["prediction_reward"]};'),
        (r'(random\.nextDouble\(\) \* )0\.\d+', f'\\g<1>{params["vote_noise_max"]}'),
        (r'(context\.incorrectStreak == )\d+', f'\\g<1>{params["v70_inversion_streak"]}'),
        (r'(min\()\d+(, recentBombs\.length\); // DeepHistory)', f'\\g<1>{params["deep_history_window"]}\\g<2>'),
        (r'(\(score - minScore\) \+ )0\.\d+', f'\\g<1>{params["vote_weight_floor"]}')
    ]
    if os.path.exists(pps_path):
        update_file(pps_path, pps_patterns)
        
    print("[Injector] All parameters applied successfully.")

if __name__ == "__main__":
    apply_params()
