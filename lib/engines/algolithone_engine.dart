import 'dart:math';

enum AlgolithoneMode { pattern, antiPattern, neutral, safety }

class AlgolithoneResult {
  final String prediction;
  final double confidence;
  final int riskLevel; // 0-10
  final AlgolithoneMode mode;
  final String insight;

  AlgolithoneResult({
    required this.prediction,
    required this.confidence,
    required this.riskLevel,
    required this.mode,
    required this.insight,
  });
}

class AlgolithoneEngine {
  /// Main Analysis Entry Point
  AlgolithoneResult analyze(List<String> history) {
    if (history.isEmpty) {
      return AlgolithoneResult(
        prediction: '?',
        confidence: 0,
        riskLevel: 0,
        mode: AlgolithoneMode.neutral,
        insight: 'No data available',
      );
    }

    final riskLevel = _calculateRiskLevel(history);
    final mode = _determineMode(history, riskLevel);
    final predictionData = _generatePrediction(history, mode);

    return AlgolithoneResult(
      prediction: predictionData['char'] as String,
      confidence: predictionData['confidence'] as double,
      riskLevel: riskLevel,
      mode: mode,
      insight: _generateInsight(mode, riskLevel),
    );
  }

  /// Calculates risk based on volatility and recent trends
  int _calculateRiskLevel(List<String> history) {
    if (history.length < 5) return 2;

    int risk = 0;

    // 1. Detect rapid shifts (High volatility)
    int shifts = 0;
    for (int i = history.length - 5; i < history.length - 1; i++) {
      if (history[i] != history[i + 1]) shifts++;
    }
    if (shifts >= 4) risk += 4; // Constant switching is high risk

    // 2. Detect sequence repeating (Trap detection)
    if (history.length >= 6) {
      String last3 = history.sublist(history.length - 3).join();
      String prev3 = history
          .sublist(history.length - 6, history.length - 3)
          .join();
      if (last3 == prev3) risk += 3; // Loop detected
    }

    return min(risk + 2, 10);
  }

  /// Determines the adaptive strategy mode
  AlgolithoneMode _determineMode(List<String> history, int riskLevel) {
    if (riskLevel >= 8) return AlgolithoneMode.safety;

    // Check if the sequence is mostly repeating the same char
    int sameCount = 0;
    String last = history.last;
    for (int i = max(0, history.length - 4); i < history.length; i++) {
      if (history[i] == last) sameCount++;
    }

    if (sameCount >= 3) {
      return AlgolithoneMode.antiPattern; // Breaking a fixed streak
    }
    if (sameCount <= 1) {
      return AlgolithoneMode.pattern; // Follow the rhythm
    }

    return AlgolithoneMode.neutral;
  }

  /// Core logic for final decision
  Map<String, dynamic> _generatePrediction(
    List<String> history,
    AlgolithoneMode mode,
  ) {
    String last = history.last;

    switch (mode) {
      case AlgolithoneMode.pattern:
        // Basic pattern follow: A -> B -> A should predict B
        if (history.length >= 2) {
          return {'char': history[history.length - 2], 'confidence': 65.0};
        }
        return {'char': last, 'confidence': 50.0};

      case AlgolithoneMode.antiPattern:
        // Anti-streak: If AAA, predict B or C (the one least frequent recently)
        Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};
        for (var char in history.sublist(max(0, history.length - 10))) {
          if (counts.containsKey(char)) counts[char] = counts[char]! + 1;
        }
        var sorted = counts.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return {'char': sorted.first.key, 'confidence': 70.0};

      case AlgolithoneMode.safety:
        // Safety mode: Pick the most balanced option (entropy maximization)
        return {'char': 'N/A', 'confidence': 0.0};

      case AlgolithoneMode.neutral:
        // Weighted random or most frequent
        return {'char': last, 'confidence': 45.0};
    }
  }

  String _generateInsight(AlgolithoneMode mode, int riskLevel) {
    if (mode == AlgolithoneMode.safety) {
      return "High Volatility: Enter Safety Mode";
    }
    if (mode == AlgolithoneMode.antiPattern) {
      return "Streak Detected: Avoiding Loop Trap";
    }
    if (mode == AlgolithoneMode.pattern) {
      return "Stable Rhythm: Following Local Pattern";
    }
    return "Neutral State: Standard Bias Applied";
  }
}
