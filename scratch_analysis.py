import re
import collections

with open('ai_decisions_1h.txt', 'r', encoding='utf-16', errors='ignore') as f:
    lines = f.readlines()

total_predictions = 0
agreement_stats = collections.defaultdict(lambda: {'win': 0, 'loss': 0})

current_pred_agreement = None

for line in lines:
    if '[SITUATIONAL AWARENESS' in line or '[AI BRAIN PREDICTION' in line:
        pass # Not using these for agreement if not present easily
        
    # Find Agreement in the lines. Wait, Agreement is not printed in SYMBIOTIC AI line.
    # Where is Agreement printed?
    # 09-28 21:32:49.722 I flutter : [SITUATIONAL AWARENESS 🛡️] [Towers] HoldFire Activated! Regime: HIGH_CHAOS, Chaos: 0.99, Agreement: 3/4, Conf: 79.5%
    # It is printed in SITUATIONAL AWARENESS, but only when HoldFire is activated.
    pass

# We will skip agreement for now. Let's just output the summary to an artifact.
