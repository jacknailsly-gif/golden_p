import re
import collections

with open('ai_decisions_overnight.txt', 'r', encoding='utf-16', errors='ignore') as f:
    lines = f.readlines()

total_predictions = 0
conf_buckets = {'<70': {'win': 0, 'loss': 0}, '70-75': {'win': 0, 'loss': 0}, '75-80': {'win': 0, 'loss': 0}, '80-85': {'win': 0, 'loss': 0}, '85+': {'win': 0, 'loss': 0}}
regime_stats = collections.defaultdict(lambda: {'win': 0, 'loss': 0})
edge_buckets = collections.defaultdict(lambda: {'win': 0, 'loss': 0})

current_pred_conf = None
current_pred_regime = None
current_pred_edge = None

for line in lines:
    if '[SYMBIOTIC AI' in line:
        conf_match = re.search(r'Conf: ([\d\.]+)%', line)
        regime_match = re.search(r'Regime: ([A-Z_]+)', line)
        edge_match = re.search(r'Edge: ([\d\.]+)%', line)
        
        if conf_match and regime_match and edge_match:
            current_pred_conf = float(conf_match.group(1))
            current_pred_regime = regime_match.group(1)
            current_pred_edge = float(edge_match.group(1))
            total_predictions += 1
            
    elif 'WIN CONFIRMED' in line and current_pred_conf is not None:
        if current_pred_conf < 70: conf_buckets['<70']['win'] += 1
        elif current_pred_conf < 75: conf_buckets['70-75']['win'] += 1
        elif current_pred_conf < 80: conf_buckets['75-80']['win'] += 1
        elif current_pred_conf < 85: conf_buckets['80-85']['win'] += 1
        else: conf_buckets['85+']['win'] += 1
            
        regime_stats[current_pred_regime]['win'] += 1
        edge_bucket = str(int(current_pred_edge // 10) * 10) + 's'
        edge_buckets[edge_bucket]['win'] += 1
        
        current_pred_conf = None # Reset
        
    elif ('Base Bet ->' in line or 'RECOVERY BET LOST' in line or 'TIMEOUT REAL LOSS' in line) and current_pred_conf is not None:
        if current_pred_conf < 70: conf_buckets['<70']['loss'] += 1
        elif current_pred_conf < 75: conf_buckets['70-75']['loss'] += 1
        elif current_pred_conf < 80: conf_buckets['75-80']['loss'] += 1
        elif current_pred_conf < 85: conf_buckets['80-85']['loss'] += 1
        else: conf_buckets['85+']['loss'] += 1
            
        regime_stats[current_pred_regime]['loss'] += 1
        edge_bucket = str(int(current_pred_edge // 10) * 10) + 's'
        edge_buckets[edge_bucket]['loss'] += 1
        
        current_pred_conf = None # Reset

print(f"Total Predictions Logged: {total_predictions}")
print("\n--- Confidence Accuracy ---")
for bucket, stats in conf_buckets.items():
    total = stats['win'] + stats['loss']
    win_rate = (stats['win'] / total * 100) if total > 0 else 0
    print(f"Conf {bucket}: {stats['win']}W / {stats['loss']}L (Win Rate: {win_rate:.2f}%) - Total: {total}")

print("\n--- Regime Accuracy ---")
for regime, stats in regime_stats.items():
    total = stats['win'] + stats['loss']
    win_rate = (stats['win'] / total * 100) if total > 0 else 0
    print(f"Regime {regime}: {stats['win']}W / {stats['loss']}L (Win Rate: {win_rate:.2f}%) - Total: {total}")

print("\n--- Edge Accuracy ---")
for edge, stats in sorted(edge_buckets.items()):
    total = stats['win'] + stats['loss']
    win_rate = (stats['win'] / total * 100) if total > 0 else 0
    print(f"Edge {edge}%: {stats['win']}W / {stats['loss']}L (Win Rate: {win_rate:.2f}%) - Total: {total}")

