import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:golden_p/models/prediction_context.dart';
import 'package:golden_p/models/prediction_result.dart';
import 'package:golden_p/engines/algolithone_engine.dart';

class PredictionPipelineService {
  final List<String> buttonValues = ['A', 'B', 'C'];
  final AlgolithoneEngine _algolithoneEngine = AlgolithoneEngine();

  // --- V52.0: 6-Engine Super Ensemble State with Memory Decay ---
  final Map<String, double> _engineScores = {
    'NGram': 0.0,
    'MarkovDodger': 0.0,
    'Heatmap': 0.0,
    'AlternatingSeeker': 0.0,
    'DeepHistoryAnchor': 0.0,
    'QuantumRNG': 0.0,
  };
  final Map<String, String> _lastPredictions = {
    'NGram': 'A',
    'MarkovDodger': 'A',
    'Heatmap': 'A',
    'AlternatingSeeker': 'A',
    'DeepHistoryAnchor': 'A',
    'QuantumRNG': 'A',
  };
  int _lastProcessedRoundCount = 0;

  // V124: Dynamic Parameters
  double memoryDecayRate = 0.90;
  double predictionPenalty = -1.0;
  double predictionReward = 1.0;
  double voteNoiseMax = 0.05;
  int v70InversionStreak = 3;
  int deepHistoryWindow = 12;
  double voteWeightFloor = 0.1;

  // --- V70.0: Ensemble & Inversion State ---
  // No longer using strict ban lists to allow weighted votes.

  /// Call this AFTER the round is actually played (M1/M2/M3 clicked)
  void confirmPick() {
    // No-op for Titanium Consensus Engine, as it relies on real history inputs, not state.
  }

  void rotateAiSeed() {
    // No-op here, seed rotation is handled by SequenceAnalyzerViewModel generating new UUIDs.
  }

  void clearHistory() {
    _lastProcessedRoundCount = 0;
    debugPrint('[V70.0] Engine history cleared.');
  }

  PredictionResult generateHybridResponse(
    PredictionContext context,
    Map<String, double> baseRateScores,
    Map<String, double> recentSuccessScores,
    Map<String, double> patternAvoidanceScores,
    Map<String, Map<String, String>> counterMoveMemory,
    List<String> decisionSequence,
  ) {
    // 1. Hard Cooldown via Algolithone Safety Mode (Optional/Disabled)
    List<String> historyStrings = context.inputs.map((e) => e.value).toList();
    AlgolithoneResult algoResult = _algolithoneEngine.analyze(historyStrings);

    Map<String, double> consensusScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    
    // Engine 1: Base Machine Learning + Crypto RNG
    for (String key in buttonValues) {
      if (baseRateScores.containsKey(key)) {
        consensusScores[key] = (consensusScores[key] ?? 0.0) + baseRateScores[key]!;
      }
    }

    List<String> recentBombs = [];
    for (var input in context.inputs) {
      if (input.actualBombPos != null) {
        recentBombs.add(input.actualBombPos!);
      }
    }

    // --- 1. Evaluate Last Round and Update Engine Scores ---
    if (recentBombs.length > _lastProcessedRoundCount) {
      String lastActualBomb = recentBombs.last;
      
      _lastPredictions.forEach((engineName, predictedSafeBox) {
        double currentScore = _engineScores[engineName] ?? 0.0;
        
        // V70.0: High Reactivity Memory Decay (Reduce old score by 50% to adapt instantly)
        currentScore *= memoryDecayRate;
        
        if (predictedSafeBox == lastActualBomb) {
          // Engine predicted a bomb! (Loss)
          currentScore += predictionPenalty;
        } else {
          // Engine predicted a safe box. (Win)
          currentScore += predictionReward;
        }
        _engineScores[engineName] = currentScore;
      });
      _lastProcessedRoundCount = recentBombs.length;
    }

    // --- 2. Generate Predictions for All 6 Engines ---
    String defaultFallback = (List.from(buttonValues)..shuffle()).first;
    Map<String, String> currentPredictions = {
      'NGram': defaultFallback,
      'MarkovDodger': defaultFallback,
      'Heatmap': defaultFallback,
      'AlternatingSeeker': defaultFallback,
      'DeepHistoryAnchor': defaultFallback,
      'QuantumRNG': (List.from(buttonValues)..shuffle()).first,
    };

    // Engine A: Heatmap (Pick the one that just bombed, assuming it's safe now)
    if (recentBombs.isNotEmpty) {
      currentPredictions['Heatmap'] = recentBombs.last;
    }

    // Engine B: Markov Dodger (Avoid the most frequent bomb in the last 5 rounds)
    if (recentBombs.isNotEmpty) {
      Map<String, int> recentCounts = {'A': 0, 'B': 0, 'C': 0};
      int scanLength = min(deepHistoryWindow, recentBombs.length);
      for (int i = recentBombs.length - scanLength; i < recentBombs.length; i++) {
        recentCounts[recentBombs[i]] = (recentCounts[recentBombs[i]] ?? 0) + 1;
      }
      
      List<String> keysMost = List.from(buttonValues)..shuffle();
      String mostFrequent = keysMost.first;
      int maxCount = -1;
      for (String key in keysMost) {
        int count = recentCounts[key] ?? 0;
        if (count > maxCount) { maxCount = count; mostFrequent = key; }
      }
      
      // We want to avoid `mostFrequent`, so pick one of the others randomly or pick the least frequent
      List<String> keysLeast = List.from(buttonValues)..shuffle();
      String leastFrequent = keysLeast.first;
      int minCount = 999;
      for (String key in keysLeast) {
        int count = recentCounts[key] ?? 0;
        if (count < minCount) { minCount = count; leastFrequent = key; }
      }
      currentPredictions['MarkovDodger'] = leastFrequent;
    }

    // Engine C: N-Gram (Look at history for exact sequence)
    if (recentBombs.length >= 3) {
      String targetGram = recentBombs.sublist(recentBombs.length - 2).join();
      Map<String, int> nextBombFreq = {'A': 0, 'B': 0, 'C': 0};
      
      for (int i = 0; i < recentBombs.length - 2; i++) {
        if (recentBombs.sublist(i, i + 2).join() == targetGram) {
          nextBombFreq[recentBombs[i + 2]] = (nextBombFreq[recentBombs[i + 2]] ?? 0) + 1;
        }
      }
      
      List<String> keysGram = List.from(buttonValues)..shuffle();
      String leastFrequentGramBomb = keysGram.first;
      int minGramCount = 999;
      for (String key in keysGram) {
        int count = nextBombFreq[key] ?? 0;
        if (count < minGramCount) { minGramCount = count; leastFrequentGramBomb = key; }
      }
      currentPredictions['NGram'] = leastFrequentGramBomb;
    }

    // Engine D: Alternating Seeker (Pick next in cycle A->B->C->A to counter alternating bots)
    if (recentBombs.isNotEmpty) {
      String last = recentBombs.last;
      if (last == 'A') currentPredictions['AlternatingSeeker'] = 'B';
      else if (last == 'B') currentPredictions['AlternatingSeeker'] = 'C';
      else currentPredictions['AlternatingSeeker'] = 'A';
    }

    // Engine E: Deep History Anchor (Avoid the least dropped bomb in the last 50 rounds)
    if (recentBombs.isNotEmpty) {
      Map<String, int> deepCounts = {'A': 0, 'B': 0, 'C': 0};
      int scanLen = min(50, recentBombs.length);
      for (int i = recentBombs.length - scanLen; i < recentBombs.length; i++) {
        deepCounts[recentBombs[i]] = (deepCounts[recentBombs[i]] ?? 0) + 1;
      }
      
      List<String> keysDeep = List.from(buttonValues)..shuffle();
      String leastDropped = keysDeep.first;
      int minDrop = 9999;
      for (String key in keysDeep) {
        int count = deepCounts[key] ?? 0;
        if (count < minDrop) { minDrop = count; leastDropped = key; }
      }
      // We assume the casino is artificially suppressing a box, so we pick it, assuming it will pop soon.
      // Or we avoid it? Deep History Anchor should bet on the safest box. The one with least bombs.
      currentPredictions['DeepHistoryAnchor'] = leastDropped;
    }

    // Store for next evaluation
    _lastPredictions['Heatmap'] = currentPredictions['Heatmap']!;
    _lastPredictions['MarkovDodger'] = currentPredictions['MarkovDodger']!;
    _lastPredictions['NGram'] = currentPredictions['NGram']!;
    _lastPredictions['AlternatingSeeker'] = currentPredictions['AlternatingSeeker']!;
    _lastPredictions['DeepHistoryAnchor'] = currentPredictions['DeepHistoryAnchor']!;
    _lastPredictions['QuantumRNG'] = currentPredictions['QuantumRNG']!;

    // --- 3. V70.0: Ensemble Voting (Wisdom of the Crowds) ---
    Map<String, double> voteScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    
    // Normalize engine scores so they can be used as weights
    double minScore = _engineScores.values.reduce(min);
    Map<String, double> normalizedWeights = {};
    _engineScores.forEach((engine, score) {
       // Shift scores so the lowest is at least 0.1 to give everyone a tiny vote
       normalizedWeights[engine] = (score - minScore) + voteWeightFloor; 
    });

    // Cast votes
    _engineScores.keys.forEach((engine) {
       String predictedBox = currentPredictions[engine] ?? 'A';
       double weight = normalizedWeights[engine] ?? 0.1;
       voteScores[predictedBox] = (voteScores[predictedBox] ?? 0.0) + weight;
    });

    // Integrate Machine Learning Pattern Consensus + Titanium Crypto RNG into the vote
    consensusScores.forEach((box, cScore) {
       if (cScore > 0.0) {
         voteScores[box] = (voteScores[box] ?? 0.0) + (cScore * 0.15);
       }
    });

    // R1: Non-deterministic voting noise (±0.05 to 0.15 to each entry in voteScores)
    final Random random = Random();
    voteScores.forEach((key, val) {
      final double noise = (random.nextDouble() * voteNoiseMax) - (voteNoiseMax / 2);
      voteScores[key] = val + noise;
    });

    // Find the winner from votes
    List<String> shuffledBoxes = voteScores.keys.toList()..shuffle();
    String bestPick = shuffledBoxes.first;
    double highestVote = -999.0;
    for (String box in shuffledBoxes) {
      if ((voteScores[box] ?? 0.0) > highestVote) {
        highestVote = voteScores[box]!;
        bestPick = box;
      }
    }

    String decisionSource = 'V70 Ensemble ($bestPick)';
    String predictionPick = bestPick;

    // V73.0: Never predict the exact same box that just bombed (User Request)
    if (recentBombs.isNotEmpty) {
      String lastBomb = recentBombs.last;
      if (predictionPick == lastBomb) {
        List<String> alt = ['A', 'B', 'C'].where((box) => box != lastBomb).toList();
        alt.shuffle();
        predictionPick = alt.first;
        decisionSource = 'V73 Avoid Bomb (Was $bestPick, Now $predictionPick)';
        debugPrint('🛡️ [V73.0 AVOID] Refusing to pick $lastBomb because it just bombed! Switched to $predictionPick');
      }
    }

    // ═══════════════════════════════════════════════════════
    // V70.0: Mirror Match (Inversion Logic) Anti-Counter Strategy
    // ═══════════════════════════════════════════════════════
    // If the casino wins 2 or more times in a row, they have likely tracked our Ensemble's preference.
    // So we do the exact opposite of what the Ensemble thinks is best.
    if (context.incorrectStreak >= 2) {
       String? lastBomb = recentBombs.isNotEmpty ? recentBombs.last : null;
       List<String> alternatives = ['A', 'B', 'C']
           .where((box) => box != bestPick && (lastBomb == null || box != lastBomb))
           .toList();
       if (alternatives.isEmpty) {
         alternatives = ['A', 'B', 'C'].where((box) => box != bestPick).toList();
       }
       // 🎯 Deterministic Anti-Bomb Selection (คำสั่งผู้ใช้: อัปเกรดเพื่อป้องกันการแพ้ > 3 ตาติด):
       // ไม่สุ่ม shuffle! จัดเรียงตามความถี่ระเบิดย้อนหลัง และเลือกช่องที่ระเบิดออกน้อยที่สุด
       if (alternatives.length > 1 && recentBombs.isNotEmpty) {
         final Map<String, int> altCounts = {};
         for (final b in recentBombs) {
           altCounts[b] = (altCounts[b] ?? 0) + 1;
         }
         alternatives.sort((a, b) => (altCounts[a] ?? 0).compareTo(altCounts[b] ?? 0));
       }
       predictionPick = alternatives.first;
       decisionSource = 'V70 Inversion (Was $bestPick, Now $predictionPick)';
       debugPrint('🛡️ [V70.0 INVERSION] Casino counter detected! Deterministically selected $predictionPick (Streak: ${context.incorrectStreak})');
    }

    // Formatting the scores map for easier reading in logs
    String scoresStr = _engineScores.entries.map((e) => '${e.key}: ${e.value.toStringAsFixed(1)}').join(', ');
    String votesStr = voteScores.entries.map((e) => '${e.key}: ${e.value.toStringAsFixed(1)}').join(', ');
    debugPrint("[V70 ADAPTIVE] Scores: {$scoresStr} | Votes: {$votesStr} | Picked: $predictionPick");

    return PredictionResult(
      primaryPrediction: predictionPick,
      decisionSource: decisionSource,
      scores: voteScores,
    );
  }
}
