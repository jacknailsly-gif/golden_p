import 'package:golden_p/models/history_entry.dart';
import 'dart:math';

class RuleResult {
  final String candidate;
  final String ruleName;

  RuleResult(this.candidate, this.ruleName);
}

class AdvancedRulesEngine {
  final List<String> buttonValues;
  Map<String, double> ruleWeights = {};

  // --- V14.5 Evolutionary Tracking ---
  Map<String, int> ruleWinCounts = {};
  Map<String, int> ruleLossCounts = {};
  Map<String, int> ruleCooldowns = {}; // Remaining cooldown cycles
  Map<String, double> rulePerformanceScores = {};
  Map<String, List<bool>> ruleRecentResults = {}; // Last 10 results per rule
  Map<String, int> ruleWinStreaks = {}; // Consecutive wins per rule

  AdvancedRulesEngine(this.buttonValues) {
    // Initialize weights and tracking for all rules
    for (var name in _allRuleNames) {
      ruleWeights[name] = 1.0;
      ruleWinCounts[name] = 0;
      ruleLossCounts[name] = 0;
      ruleCooldowns[name] = 0;
      rulePerformanceScores[name] = 0.5;
      ruleRecentResults[name] = [];
      ruleWinStreaks[name] = 0;
    }
  }

  static const List<String> _allRuleNames = [
    'Mirror Pattern',
    'Cycle Detection',
    'Alternating Pairs',
    'Fibonacci Sequence',
    'Gap Fill',
    'Dominant Suppression',
    'Triple Avoidance',
    'Symmetry Break',
    'Probability Inversion',
    'Hot-Cold Switching',
    'Variance Threshold',
    'Moving Average',
    'Entropy Maximization',
    'Regression to Mean',
    'Time-Decay Weighting',
    'Streak Breaker',
    'Oscillation Detection',
    'Recency Bias Correction',
    'Window Sliding',
    'Temporal Clustering',
    'Error Pattern Learning',
    'Confidence Calibration',
    'Multi-Context',
    'Adaptive Threshold',
    'Ensemble Disagreement',
    'Deep Pattern Search',
  ];

  /// V7.0 Legacy method (backward compatible)
  void updateRuleWeights(String winnerRuleName, bool isCorrect) {
    updateRulePerformance(winnerRuleName, isCorrect);
  }

  /// V14.5 Evolutionary Rule Performance Tracking
  /// Tracks win/loss, applies cooldown on poor performance, boosts winners
  void updateRulePerformance(String ruleName, bool wasCorrect) {
    // 1. Update basic counts
    if (wasCorrect) {
      ruleWinCounts[ruleName] = (ruleWinCounts[ruleName] ?? 0) + 1;
      ruleWinStreaks[ruleName] = (ruleWinStreaks[ruleName] ?? 0) + 1;
    } else {
      ruleLossCounts[ruleName] = (ruleLossCounts[ruleName] ?? 0) + 1;
      ruleWinStreaks[ruleName] = 0;
    }

    // 2. Track recent results (last 10)
    ruleRecentResults.putIfAbsent(ruleName, () => []);
    ruleRecentResults[ruleName]!.add(wasCorrect);
    if (ruleRecentResults[ruleName]!.length > 10) {
      ruleRecentResults[ruleName]!.removeAt(0);
    }

    // 3. Calculate performance score (EMA)
    double current = rulePerformanceScores[ruleName] ?? 0.5;
    rulePerformanceScores[ruleName] = (current * 0.7) + (wasCorrect ? 0.3 : 0.0);

    // 4. COOLDOWN CHECK: If Loss > 3 within last 10 uses → Disable for 20 cycles
    List<bool> recent = ruleRecentResults[ruleName] ?? [];
    if (recent.length >= 5) {
      int recentLosses = recent.where((r) => !r).length;
      if (recentLosses > 3) {
        ruleCooldowns[ruleName] = 20;
        ruleWeights[ruleName] = 0.1; // Minimize weight during cooldown
        return; // Skip further weight adjustments
      }
    }

    // 5. WIN STREAK BOOST: If Win Streak ≥ 4 → Boost weight +25%
    if ((ruleWinStreaks[ruleName] ?? 0) >= 4) {
      ruleWeights[ruleName] = ((ruleWeights[ruleName] ?? 1.0) * 1.25).clamp(0.1, 5.0);
      ruleWinStreaks[ruleName] = 0; // Reset streak after boost
      return;
    }

    // 6. Standard weight update
    if (wasCorrect) {
      ruleWeights[ruleName] = ((ruleWeights[ruleName] ?? 1.0) + 0.15).clamp(0.1, 5.0);
    } else {
      ruleWeights[ruleName] = ((ruleWeights[ruleName] ?? 1.0) - 0.08).clamp(0.1, 5.0);
    }
  }

  /// V14.5: Check if a rule is currently in cooldown
  bool isRuleCoolingDown(String ruleName) {
    return (ruleCooldowns[ruleName] ?? 0) > 0;
  }

  /// V14.5: Tick all cooldown counters (call once per decision cycle)
  void tickCooldowns() {
    for (var name in _allRuleNames) {
      if ((ruleCooldowns[name] ?? 0) > 0) {
        ruleCooldowns[name] = ruleCooldowns[name]! - 1;
        // Restore weight when cooldown expires
        if (ruleCooldowns[name] == 0) {
          ruleWeights[name] = 0.5; // Reset to moderate weight
          ruleRecentResults[name]?.clear(); // Fresh start
        }
      }
    }
  }

  /// V14.5: Get rule health summary for debugging
  Map<String, dynamic> getRuleHealth(String ruleName) {
    return {
      'weight': ruleWeights[ruleName] ?? 1.0,
      'wins': ruleWinCounts[ruleName] ?? 0,
      'losses': ruleLossCounts[ruleName] ?? 0,
      'performance': rulePerformanceScores[ruleName] ?? 0.5,
      'cooldown': ruleCooldowns[ruleName] ?? 0,
      'winStreak': ruleWinStreaks[ruleName] ?? 0,
    };
  }

  // ========================================
  // HELPER METHODS
  // ========================================

  Map<String, double> _calculateFrequencies(List<String> history, int window) {
    if (history.isEmpty) return {};
    var subset = history.length > window
        ? history.sublist(history.length - window)
        : history;
    Map<String, double> freq = {'A': 0, 'B': 0, 'C': 0};
    for (var char in subset) {
      freq[char] = (freq[char] ?? 0) + 1;
    }
    int total = subset.length;
    if (total > 0) {
      freq.updateAll((key, val) => val / total);
    }
    return freq;
  }

  double _calculateVariance(List<String> history) {
    if (history.length < 2) return 0.0;
    var freq = _calculateFrequencies(history, history.length);
    double mean = freq.values.reduce((a, b) => a + b) / freq.length;
    double variance =
        freq.values
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        freq.length;
    return variance;
  }

  double _calculateEntropy(Map<String, double> frequencies) {
    double entropy = 0.0;
    for (var prob in frequencies.values) {
      if (prob > 0) {
        entropy -=
            prob *
            (prob > 0 ? (prob * 1.4426950408889634) : 0); // log2 approximation
      }
    }
    return entropy;
  }

  Map<String, double> _getLearningScoresForContext(
    List<HistoryEntry> inputs,
    Map<String, Map<String, int>> learningMemory,
    int contextLength,
  ) {
    if (inputs.length < contextLength) return {};
    List<String> history = inputs.map((e) => e.value).toList();
    String context = history.sublist(history.length - contextLength).join();

    Map<String, double> scores = {};
    if (learningMemory.containsKey(context)) {
      int total = learningMemory[context]!.values.fold(0, (sum, c) => sum + c);
      if (total > 0) {
        learningMemory[context]!.forEach((key, count) {
          scores[key] = count / total;
        });
      }
    }
    return scores;
  }

  // ========================================
  // 26 ADVANCED PREDICTION RULES
  // ========================================

  RuleResult? _ruleDeepPatternSearch(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;
    List<String> history = inputs.map((e) => e.value).toList();

    // Try to find the longest suffix that has appeared before
    for (int len = min(history.length - 1, 15); len >= 3; len--) {
      List<String> suffix = history.sublist(history.length - len);

      // Search backwards in history for this pattern
      for (int i = history.length - len - 1; i >= 0; i--) {
        if (i + len >= history.length) continue;

        bool match = true;
        for (int j = 0; j < len; j++) {
          if (history[i + j] != suffix[j]) {
            match = false;
            break;
          }
        }

        if (match && i + len < history.length) {
          String next = history[i + len];
          if (!forbidden.contains(next)) {
            return RuleResult(next, 'Deep Pattern Search');
          }
        }
      }
    }
    return null;
  }

  // PATTERN-BASED RULES (1-8)

  RuleResult? _ruleMirrorPattern(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 3) return null;
    var last3 = inputs
        .toList()
        .sublist(inputs.length - 3)
        .map((e) => e.value)
        .toList();
    if (last3[0] == last3[2] && last3[0] != last3[1]) {
      if (!forbidden.contains(last3[1])) {
        return RuleResult(last3[1], 'Mirror Pattern');
      }
    }
    return null;
  }

  RuleResult? _ruleCycleDetection(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 6) return null;
    var history = inputs.map((e) => e.value).toList();

    // Check for 3-char cycle (ABC-ABC)
    if (history.length >= 6) {
      bool isCycle = true;
      for (int i = 0; i < 3; i++) {
        if (history[history.length - 6 + i] !=
            history[history.length - 3 + i]) {
          isCycle = false;
          break;
        }
      }
      if (isCycle) {
        String next = history[history.length - 6];
        if (!forbidden.contains(next)) {
          return RuleResult(next, 'Cycle Detection');
        }
      }
    }
    return null;
  }

  RuleResult? _ruleAlternatingPairs(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 4) return null;
    var last4 = inputs
        .toList()
        .sublist(inputs.length - 4)
        .map((e) => e.value)
        .toList();
    if (last4[0] == last4[1] && last4[2] == last4[3] && last4[0] != last4[2]) {
      String next = last4[0];
      if (!forbidden.contains(next)) {
        return RuleResult(next, 'Alternating Pairs');
      }
    }
    return null;
  }

  RuleResult? _ruleFibonacciSequence(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 3) return null;
    var history = inputs.map((e) => e.value).toList();
    Map<String, int> charMap = {'A': 1, 'B': 2, 'C': 3};
    var last3 = history
        .sublist(history.length - 3)
        .map((c) => charMap[c] ?? 0)
        .toList();

    if (last3[2] == last3[0] + last3[1] ||
        last3[2] == (last3[0] + last3[1]) % 4) {
      int nextNum = (last3[1] + last3[2]) % 4;
      if (nextNum == 0) nextNum = 3;
      String next = charMap.entries
          .firstWhere((e) => e.value == nextNum, orElse: () => MapEntry('A', 1))
          .key;
      if (!forbidden.contains(next)) {
        return RuleResult(next, 'Fibonacci Sequence');
      }
    }
    return null;
  }

  RuleResult? _ruleGapFill(List<HistoryEntry> inputs, Set<String> forbidden) {
    if (inputs.length < 10) return null;
    var last10 = inputs
        .toList()
        .sublist(inputs.length - 10)
        .map((e) => e.value)
        .toList();
    var freq = _calculateFrequencies(last10, 10);

    var sorted = freq.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Gap Fill');
      }
    }
    return null;
  }

  RuleResult? _ruleDominantSuppression(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 15) return null;
    var last15 = inputs
        .toList()
        .sublist(inputs.length - 15)
        .map((e) => e.value)
        .toList();
    var freq = _calculateFrequencies(last15, 15);

    var dominant = freq.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    for (var char in buttonValues) {
      if (char != dominant && !forbidden.contains(char)) {
        return RuleResult(char, 'Dominant Suppression');
      }
    }
    return null;
  }

  RuleResult? _ruleTripleAvoidance(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 5) return null;
    var last5 = inputs
        .toList()
        .sublist(inputs.length - 5)
        .map((e) => e.value)
        .toList();

    Set<String> avoid = {};
    for (var char in buttonValues) {
      if (last5.where((c) => c == char).length >= 3) {
        avoid.add(char);
      }
    }

    for (var char in buttonValues) {
      if (!forbidden.contains(char) && !avoid.contains(char)) {
        return RuleResult(char, 'Triple Avoidance');
      }
    }
    return null;
  }

  RuleResult? _ruleSymmetryBreak(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 6) return null;
    var last6 = inputs
        .toList()
        .sublist(inputs.length - 6)
        .map((e) => e.value)
        .toList();

    bool isSymmetric = true;
    for (int i = 0; i < 3; i++) {
      if (last6[i] != last6[5 - i]) {
        isSymmetric = false;
        break;
      }
    }

    if (isSymmetric) {
      for (var char in buttonValues) {
        if (char != last6[0] && !forbidden.contains(char)) {
          return RuleResult(char, 'Symmetry Break');
        }
      }
    }
    return null;
  }

  // STATISTICAL RULES (9-14)

  RuleResult? _ruleProbabilityInversion(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.isEmpty) return null;
    var freq = _calculateFrequencies(
      inputs.map((e) => e.value).toList(),
      inputs.length,
    );
    var sorted = freq.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Probability Inversion');
      }
    }
    return null;
  }

  RuleResult? _ruleHotColdSwitching(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;
    var recent = _calculateFrequencies(
      inputs.toList().sublist(inputs.length - 10).map((e) => e.value).toList(),
      10,
    );

    var sorted = recent.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Hot-Cold Switching');
      }
    }
    return null;
  }

  RuleResult? _ruleVarianceThreshold(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;
    var last10 = inputs
        .toList()
        .sublist(inputs.length - 10)
        .map((e) => e.value)
        .toList();
    double variance = _calculateVariance(last10);

    if (variance > 0.15) {
      var freq = _calculateFrequencies(last10, 10);
      var sorted = freq.entries.toList()
        ..sort(
          (a, b) => (a.value - 0.33).abs().compareTo((b.value - 0.33).abs()),
        );
      for (var entry in sorted) {
        if (!forbidden.contains(entry.key)) {
          return RuleResult(entry.key, 'Variance Threshold');
        }
      }
    }
    return null;
  }

  RuleResult? _ruleMovingAverage(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;
    var history = inputs.map((e) => e.value).toList();
    var recent5 = _calculateFrequencies(history.sublist(history.length - 5), 5);
    var previous5 = _calculateFrequencies(
      history.sublist(history.length - 10, history.length - 5),
      5,
    );

    Map<String, double> trends = {};
    for (var char in buttonValues) {
      trends[char] = (recent5[char] ?? 0) - (previous5[char] ?? 0);
    }

    var sorted = trends.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Moving Average');
      }
    }
    return null;
  }

  RuleResult? _ruleEntropyMaximization(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;
    var last10 = inputs
        .toList()
        .sublist(inputs.length - 10)
        .map((e) => e.value)
        .toList();
    var freq = _calculateFrequencies(last10, 10);

    Map<String, double> entropyScores = {};
    for (var char in buttonValues) {
      if (forbidden.contains(char)) continue;
      var testFreq = Map<String, double>.from(freq);
      testFreq[char] = (testFreq[char] ?? 0) + 0.1;
      entropyScores[char] = _calculateEntropy(testFreq);
    }

    if (entropyScores.isNotEmpty) {
      var best = entropyScores.entries.reduce(
        (a, b) => a.value > b.value ? a : b,
      );
      return RuleResult(best.key, 'Entropy Maximization');
    }
    return null;
  }

  RuleResult? _ruleRegressionToMean(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.isEmpty) return null;
    var freq = _calculateFrequencies(
      inputs.map((e) => e.value).toList(),
      inputs.length,
    );

    var sorted = freq.entries.toList()
      ..sort(
        (a, b) => (a.value - 0.333).abs().compareTo((b.value - 0.333).abs()),
      );
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Regression to Mean');
      }
    }
    return null;
  }

  // TEMPORAL RULES (15-20)

  RuleResult? _ruleTimeDecayWeighting(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;
    var history = inputs.map((e) => e.value).toList();
    Map<String, double> weighted = {'A': 0, 'B': 0, 'C': 0};

    for (int i = 0; i < history.length && i < 10; i++) {
      int pos = history.length - 1 - i;
      double weight = i < 3 ? 3.0 : (i < 6 ? 2.0 : 1.0);
      weighted[history[pos]] = (weighted[history[pos]] ?? 0) + weight;
    }

    var sorted = weighted.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Time-Decay Weighting');
      }
    }
    return null;
  }

  RuleResult? _ruleStreakBreaker(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 3) return null;
    var last3 = inputs
        .toList()
        .sublist(inputs.length - 3)
        .map((e) => e.value)
        .toList();

    if (last3[0] == last3[1] && last3[1] == last3[2]) {
      String streakChar = last3[0];
      for (var char in buttonValues) {
        if (char != streakChar && !forbidden.contains(char)) {
          return RuleResult(char, 'Streak Breaker');
        }
      }
    }
    return null;
  }

  RuleResult? _ruleOscillationDetection(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 4) return null;
    var last4 = inputs
        .toList()
        .sublist(inputs.length - 4)
        .map((e) => e.value)
        .toList();

    if (last4[0] == last4[2] && last4[1] == last4[3] && last4[0] != last4[1]) {
      String next = last4[0];
      if (!forbidden.contains(next)) {
        return RuleResult(next, 'Oscillation Detection');
      }
    }
    return null;
  }

  RuleResult? _ruleRecencyBiasCorrection(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 8) return null;
    var history = inputs.map((e) => e.value).toList();
    var window = history.sublist(history.length - 8, history.length - 2);
    var freq = _calculateFrequencies(window, 6);

    var sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Recency Bias Correction');
      }
    }
    return null;
  }

  RuleResult? _ruleWindowSliding(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 8) return null;
    var history = inputs.map((e) => e.value).toList();

    Map<String, int> bestMatch = {};
    for (int start = history.length - 8; start < history.length - 4; start++) {
      var window = history.sublist(start, start + 4);
      for (var char in window) {
        bestMatch[char] = (bestMatch[char] ?? 0) + 1;
      }
    }

    var sorted = bestMatch.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Window Sliding');
      }
    }
    return null;
  }

  RuleResult? _ruleTemporalClustering(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 20) return null;
    var history = inputs.map((e) => e.value).toList();
    var recent = _calculateFrequencies(
      history.sublist(history.length - 10),
      10,
    );
    var older = _calculateFrequencies(
      history.sublist(history.length - 20, history.length - 10),
      10,
    );

    Map<String, double> shift = {};
    for (var char in buttonValues) {
      shift[char] = (recent[char] ?? 0) - (older[char] ?? 0);
    }

    var sorted = shift.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Temporal Clustering');
      }
    }
    return null;
  }

  // META-LEARNING RULES (21-25)

  RuleResult? _ruleErrorPatternLearning(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
    Map<String, int> errorCounts,
  ) {
    var sorted = errorCounts.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (var entry in sorted) {
      if (!forbidden.contains(entry.key)) {
        return RuleResult(entry.key, 'Error Pattern Learning');
      }
    }
    return null;
  }

  RuleResult? _ruleConfidenceCalibration(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
    double confidence,
    int incorrectStreak,
    String? lastPredictedChar,
  ) {
    if (confidence > 80.0 && incorrectStreak > 0) {
      // Predict opposite of high-confidence wrong prediction
      for (var char in buttonValues) {
        if (char != lastPredictedChar && !forbidden.contains(char)) {
          return RuleResult(char, 'Confidence Calibration');
        }
      }
    }
    return null;
  }

  RuleResult? _ruleMultiContext(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
    Map<String, Map<String, int>> learningMemory,
  ) {
    if (inputs.length < 6) return null;

    Map<String, int> votes = {};

    var ctx2 = _getLearningScoresForContext(inputs, learningMemory, 2);
    if (ctx2.isNotEmpty) {
      var best = ctx2.entries.reduce((a, b) => a.value > b.value ? a : b);
      votes[best.key] = (votes[best.key] ?? 0) + 1;
    }

    var ctx4 = _getLearningScoresForContext(inputs, learningMemory, 4);
    if (ctx4.isNotEmpty) {
      var best = ctx4.entries.reduce((a, b) => a.value > b.value ? a : b);
      votes[best.key] = (votes[best.key] ?? 0) + 1;
    }

    var ctx6 = _getLearningScoresForContext(inputs, learningMemory, 6);
    if (ctx6.isNotEmpty) {
      var best = ctx6.entries.reduce((a, b) => a.value > b.value ? a : b);
      votes[best.key] = (votes[best.key] ?? 0) + 1;
    }

    if (votes.isNotEmpty) {
      var sorted = votes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var entry in sorted) {
        if (!forbidden.contains(entry.key)) {
          return RuleResult(entry.key, 'Multi-Context');
        }
      }
    }
    return null;
  }

  RuleResult? _ruleAdaptiveThreshold(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
    int totalPredictions,
    int correctPredictions,
  ) {
    if (inputs.length < 5) return null;
    double accuracy = totalPredictions > 0
        ? correctPredictions / totalPredictions
        : 0.5;

    int lookback = accuracy > 0.6 ? 3 : (accuracy > 0.4 ? 5 : 8);
    if (inputs.length >= lookback) {
      var window = inputs
          .toList()
          .sublist(inputs.length - lookback)
          .map((e) => e.value)
          .toList();
      var freq = _calculateFrequencies(window, lookback);
      var sorted = freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var entry in sorted) {
        if (!forbidden.contains(entry.key)) {
          return RuleResult(entry.key, 'Adaptive Threshold');
        }
      }
    }
    return null;
  }

  RuleResult? _ruleEnsembleDisagreement(
    List<HistoryEntry> inputs,
    Set<String> forbidden,
  ) {
    if (inputs.length < 10) return null;

    Map<String, int> votes = {};

    // Strategy 1: Pattern (Mirror)
    var pattern = _ruleMirrorPattern(inputs, forbidden);
    if (pattern != null) {
      votes[pattern.candidate] = (votes[pattern.candidate] ?? 0) + 1;
    }

    // Strategy 2: Statistical (Probability Inversion)
    var statistical = _ruleProbabilityInversion(inputs, forbidden);
    if (statistical != null) {
      votes[statistical.candidate] = (votes[statistical.candidate] ?? 0) + 1;
    }

    // Strategy 3: Temporal (Time Decay)
    var temporal = _ruleTimeDecayWeighting(inputs, forbidden);
    if (temporal != null) {
      votes[temporal.candidate] = (votes[temporal.candidate] ?? 0) + 1;
    }

    if (votes.isNotEmpty) {
      var sorted = votes.entries.toList()
        ..sort((a, b) => a.value.compareTo(a.value));
      // Pick minority (contrarian)
      for (var entry in sorted) {
        if (!forbidden.contains(entry.key)) {
          return RuleResult(entry.key, 'Ensemble Disagreement');
        }
      }
    }
    return null;
  }

  // ========================================
  // RULE ENGINE - EVALUATES ALL 25 RULES
  // ========================================

  RuleResult? evaluate({
    required List<HistoryEntry> inputs,
    required int incorrectStreak,
    required Set<String> forbidden,
    required double confidence,
    required String? lastPredictedChar,
    required Map<String, int> errorCounts,
    required Map<String, Map<String, int>> learningMemory,
    required int totalPredictions,
    required int correctPredictions,
  }) {
    // V8.0: Tick cooldown counters at start of each evaluation cycle
    tickCooldowns();

    Map<String, int> ruleVotes = {};
    Map<String, List<String>> candidateReasons = {};

    // V8.0: Cooldown-aware vote registration
    void addVote(RuleResult? result) {
      if (result != null) {
        // Skip rules that are in cooldown
        if (isRuleCoolingDown(result.ruleName)) return;
        ruleVotes[result.candidate] = (ruleVotes[result.candidate] ?? 0) + 1;
        if (!candidateReasons.containsKey(result.candidate)) {
          candidateReasons[result.candidate] = [];
        }
        candidateReasons[result.candidate]!.add(result.ruleName);
      }
    }

    // Evaluate all 26 rules (V8.0: skips rules in cooldown)
    addVote(_ruleMirrorPattern(inputs, forbidden));
    addVote(_ruleCycleDetection(inputs, forbidden));
    addVote(_ruleAlternatingPairs(inputs, forbidden));
    addVote(_ruleFibonacciSequence(inputs, forbidden));
    addVote(_ruleGapFill(inputs, forbidden));
    addVote(_ruleDominantSuppression(inputs, forbidden));
    addVote(_ruleTripleAvoidance(inputs, forbidden));
    addVote(_ruleSymmetryBreak(inputs, forbidden));
    addVote(_ruleProbabilityInversion(inputs, forbidden));
    addVote(_ruleHotColdSwitching(inputs, forbidden));
    addVote(_ruleVarianceThreshold(inputs, forbidden));
    addVote(_ruleMovingAverage(inputs, forbidden));
    addVote(_ruleEntropyMaximization(inputs, forbidden));
    addVote(_ruleRegressionToMean(inputs, forbidden));
    addVote(_ruleTimeDecayWeighting(inputs, forbidden));
    addVote(_ruleStreakBreaker(inputs, forbidden));
    addVote(_ruleOscillationDetection(inputs, forbidden));
    addVote(_ruleRecencyBiasCorrection(inputs, forbidden));
    addVote(_ruleWindowSliding(inputs, forbidden));
    addVote(_ruleTemporalClustering(inputs, forbidden));
    addVote(_ruleDeepPatternSearch(inputs, forbidden));

    // Rules with extra dependencies
    addVote(_ruleErrorPatternLearning(inputs, forbidden, errorCounts));
    addVote(
      _ruleConfidenceCalibration(
        inputs,
        forbidden,
        confidence,
        incorrectStreak,
        lastPredictedChar,
      ),
    );
    addVote(_ruleMultiContext(inputs, forbidden, learningMemory));
    addVote(
      _ruleAdaptiveThreshold(
        inputs,
        forbidden,
        totalPredictions,
        correctPredictions,
      ),
    );
    addVote(_ruleEnsembleDisagreement(inputs, forbidden));

    // Return candidate with most weighted votes
    if (ruleVotes.isNotEmpty) {
      Map<String, double> weightedVotes = {};
      ruleVotes.forEach((candidate, count) {
        // Here we sum the weights of all rules that voted for this candidate
        double totalWeight = 0;
        for (var ruleName in candidateReasons[candidate]!) {
          totalWeight += ruleWeights[ruleName] ?? 1.0;
        }
        weightedVotes[candidate] = totalWeight;
      });

      var sorted = weightedVotes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      String winner = sorted.first.key;

      // Find which rule contributed MOST to this winner
      String bestRule = candidateReasons[winner]!.reduce(
        (a, b) => (ruleWeights[a] ?? 1.0) > (ruleWeights[b] ?? 1.0) ? a : b,
      );

      return RuleResult(winner, bestRule);
    }

    return null;
  }
}
