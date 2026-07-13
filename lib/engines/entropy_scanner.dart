import 'dart:math';

// --- V7.0 Legacy Enum (Backward Compatible) ---
enum GameRegime { trend, oscillation, chaos, trap }

// --- V14.5 Phase-Aware Intelligence ---
enum GamePhase { trend, chaos, trap, recovery }

/// 🔍 Entropy Scanner & Phase Detector V14.5
/// Measures randomness, classifies game phase, and computes StreakRisk
/// to drive adaptive decision-making across the entire intelligence system.
class EntropyScanner {
  static const int _windowSize = 20;
  static const int _shortWindow = 10;

  // --- V14.5 State ---
  double _lastEntropy = 0.0;
  double _entropyDelta = 0.0; // Spike detection
  final List<double> _entropyHistory = []; // Track entropy over time
  static const int _maxEntropyHistory = 30;

  // Getters
  double get lastEntropy => _lastEntropy;
  double get entropyDelta => _entropyDelta;

  /// Calculate Shannon Entropy of the last window (raw: 0.0 ~ log2(3) ≈ 1.58)
  double calculateEntropy(List<String> history) {
    if (history.isEmpty) return 0.0;

    List<String> window = history.sublist(max(0, history.length - _windowSize));
    Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};

    for (var char in window) {
      if (counts.containsKey(char)) counts[char] = counts[char]! + 1;
    }

    double entropy = 0.0;
    int n = window.length;

    for (int count in counts.values) {
      if (count > 0) {
        double p = count / n;
        entropy -= p * (log(p) / ln2);
      }
    }

    // Track entropy delta for spike detection
    _entropyDelta = entropy - _lastEntropy;
    _lastEntropy = entropy;

    // Store history
    _entropyHistory.add(entropy);
    if (_entropyHistory.length > _maxEntropyHistory) {
      _entropyHistory.removeAt(0);
    }

    return entropy; // Max for 3 states is log2(3) ≈ 1.58
  }

  /// V14.5: Normalized Entropy (0.0 → 1.0)
  /// 0.0 = perfectly predictable, 1.0 = maximum chaos
  double calculateNormalizedEntropy(List<String> history) {
    double raw = calculateEntropy(history);
    double maxEntropy = log(3) / ln2; // log2(3) ≈ 1.585
    return (raw / maxEntropy).clamp(0.0, 1.0);
  }

  /// V14.5: Pattern Stability Score (0.0 = unstable, 1.0 = very stable)
  /// Measures how consistent the transition patterns are over recent history
  double calculatePatternStability(List<String> history) {
    if (history.length < 6) return 0.5; // Neutral when insufficient data

    List<String> recent = history.sublist(max(0, history.length - _shortWindow));

    // Count unique 2-gram transitions
    Map<String, int> transitions = {};
    for (int i = 0; i < recent.length - 1; i++) {
      String t = '${recent[i]}${recent[i + 1]}';
      transitions[t] = (transitions[t] ?? 0) + 1;
    }

    if (transitions.isEmpty) return 0.5;

    // Calculate concentration: if few transitions dominate → stable
    int totalTransitions = transitions.values.fold(0, (a, b) => a + b);
    double maxFreq = transitions.values.reduce(max).toDouble();
    double concentration = maxFreq / totalTransitions;

    // Also consider how many unique transitions exist (fewer = more stable)
    double uniqueRatio = transitions.length / 9.0; // Max possible 2-grams = 9 (3×3)
    double diversityPenalty = 1.0 - uniqueRatio;

    return ((concentration * 0.6) + (diversityPenalty * 0.4)).clamp(0.0, 1.0);
  }

  /// V14.5: StreakRisk Score (0.0 → 1.0)
  /// Combines Loss Density, Pattern Instability, Entropy Spike, and Failure Rate
  double calculateStreakRisk({
    required List<String> history,
    required int incorrectStreak,
    required int totalPredictions,
    required int correctPredictions,
    required double normalizedEntropy,
  }) {
    if (history.length < 5) return 0.0;

    // 1. Loss Density: How many losses in last 10?
    double lossDensity = 0.0;
    if (totalPredictions > 0) {
      // Use recent accuracy to estimate loss density
      double recentAccuracy = totalPredictions > 0
          ? correctPredictions / totalPredictions
          : 0.5;
      lossDensity = (1.0 - recentAccuracy).clamp(0.0, 1.0);
    }

    // 2. Pattern Instability (inverse of stability)
    double instability = 1.0 - calculatePatternStability(history);

    // 3. Entropy Spike: Sudden jump in entropy
    double spikeFactor = 0.0;
    if (_entropyDelta.abs() > 0.3) {
      spikeFactor = (_entropyDelta.abs() / 1.0).clamp(0.0, 1.0);
    }

    // 4. Prediction Failure Rate (weighted toward recent)
    double failureRate = 0.0;
    if (incorrectStreak >= 1) {
      failureRate = (incorrectStreak / 5.0).clamp(0.0, 1.0);
    }

    // Weighted combination
    double streakRisk = (lossDensity * 0.25) +
        (instability * 0.25) +
        (spikeFactor * 0.25) +
        (failureRate * 0.25);

    // Boost risk if entropy is very high AND losing
    if (normalizedEntropy > 0.7 && incorrectStreak >= 2) {
      streakRisk = (streakRisk * 1.3).clamp(0.0, 1.0);
    }

    return streakRisk.clamp(0.0, 1.0);
  }

  /// V14.5: Detect current Game Phase
  /// Uses Entropy, Stability, Win/Loss, and Streak data
  GamePhase detectPhase({
    required List<String> history,
    required double normalizedEntropy,
    required int incorrectStreak,
    required int correctStreak,
    required double streakRisk,
  }) {
    if (history.length < 5) return GamePhase.chaos;

    // --- RECOVERY: After a losing streak, entering cautious mode ---
    if (incorrectStreak >= 2 && streakRisk > 0.5) {
      return GamePhase.recovery;
    }

    // --- TRAP: Suspicious repeating patterns + high entropy spike ---
    List<String> recent = history.sublist(max(0, history.length - _shortWindow));

    // Check for trap patterns (AAB AAB repeating)
    if (recent.length >= 6) {
      String p1 = recent.sublist(recent.length - 3).join();
      String p2 = recent.sublist(recent.length - 6, recent.length - 3).join();
      if (p1 == p2) return GamePhase.trap;
    }

    // Entropy spike + losses = trap
    if (_entropyDelta.abs() > 0.4 && incorrectStreak >= 1) {
      return GamePhase.trap;
    }

    // High StreakRisk = trap
    if (streakRisk > 0.65) {
      return GamePhase.trap;
    }

    // --- CHAOS: High entropy, unstable patterns ---
    if (normalizedEntropy > 0.7) {
      return GamePhase.chaos;
    }

    // --- TREND: Low entropy, stable patterns, winning ---
    if (normalizedEntropy < 0.4 && correctStreak >= 1) {
      return GamePhase.trend;
    }

    // Default: Check stability
    double stability = calculatePatternStability(history);
    if (stability > 0.6) return GamePhase.trend;
    if (stability < 0.3) return GamePhase.chaos;

    return GamePhase.trend; // Default to trend if moderately stable
  }

  // --- V7.0 Legacy Method (Backward Compatible) ---
  /// Detect the current game regime (V7.0 compatibility)
  GameRegime detectRegime(List<String> history, double entropy) {
    if (history.length < 5) return GameRegime.chaos;

    List<String> recent = history.sublist(max(0, history.length - 10));

    // 1. Trap Detection (AAB AAB)
    if (recent.length >= 6) {
      String p1 = recent.sublist(recent.length - 3).join();
      String p2 = recent.sublist(recent.length - 6, recent.length - 3).join();
      if (p1 == p2) return GameRegime.trap;
    }

    // 2. Trend Detection (AAAA)
    int sameCount = 1;
    for (int i = recent.length - 2; i >= 0; i--) {
      if (recent[i] == recent.last) {
        sameCount++;
      } else {
        break;
      }
    }
    if (sameCount >= 3) return GameRegime.trend;

    // 3. Oscillation Detection (ABAB)
    if (recent.length >= 4) {
      if (recent[recent.length - 1] == recent[recent.length - 3] &&
          recent[recent.length - 2] == recent[recent.length - 4] &&
          recent[recent.length - 1] != recent[recent.length - 2]) {
        return GameRegime.oscillation;
      }
    }

    // 4. Chaos Mode based on Entropy
    if (entropy > 1.3) return GameRegime.chaos;

    return GameRegime.trend; // Default to trend if stable
  }

  /// Check if there was a recent entropy spike (for Predator v4.0)
  bool hasEntropySpiked() {
    return _entropyDelta.abs() > 0.3;
  }

  /// Get entropy trend direction (-1 = decreasing, 0 = stable, 1 = increasing)
  int getEntropyTrend() {
    if (_entropyHistory.length < 3) return 0;
    double recent = _entropyHistory.sublist(_entropyHistory.length - 3)
        .reduce((a, b) => a + b) / 3;
    double older = _entropyHistory.length >= 6
        ? _entropyHistory.sublist(_entropyHistory.length - 6, _entropyHistory.length - 3)
            .reduce((a, b) => a + b) / 3
        : recent;

    double diff = recent - older;
    if (diff > 0.1) return 1;
    if (diff < -0.1) return -1;
    return 0;
  }
}
