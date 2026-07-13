import 'prediction_strategy.dart';

class PatternStrategy implements PredictionStrategy {
  // Dictionary: context -> {next_char: frequency}
  final Map<String, Map<String, int>> _patterns = {};
  double _weight = 0.5;
  int _usageCount = 0;

  @override
  String get id => "pattern_lz78";

  @override
  String get name => "Pattern Match (LZ78)";

  @override
  double get weight => _weight;

  @override
  double get ucbScore {
    double exploration = (_usageCount == 0) ? 1.0 : (1.0 / _usageCount);
    return weight + (2.0 * exploration); // Higher exploration factor
  }

  @override
  String? predict(List<String> history, int contextLength) {
    // Try to match longest possible context first (up to length 5)
    for (int len = 5; len >= 3; len--) {
      if (history.length < len) continue;
      String ctx = history.sublist(history.length - len).join();

      if (_patterns.containsKey(ctx)) {
        var nextMap = _patterns[ctx]!;
        // Find most frequent next char
        var sortedKeys = nextMap.keys.toList()
          ..sort((a, b) => nextMap[b]!.compareTo(nextMap[a]!));

        if (sortedKeys.isNotEmpty) {
          return sortedKeys.first;
        }
      }
    }
    return null;
  }

  @override
  void update(
    String actual,
    bool wasCorrect,
    List<String> history,
    double learningRate,
  ) {
    _usageCount++;
    // _successCount is not tracked as weight serves as Q-value

    // Learn patterns of length 3 to 5
    for (int len = 3; len <= 5; len++) {
      if (history.length < len + 1) continue;

      String ctx = history
          .sublist(history.length - 1 - len, history.length - 1)
          .join();

      if (!_patterns.containsKey(ctx)) {
        _patterns[ctx] = {};
      }
      _patterns[ctx]![actual] = (_patterns[ctx]![actual] ?? 0) + 1;
    }

    // --- Incremental Weight Update (Delta Rule) ---
    double confidence = getConfidence(history, 3) / 100.0;
    double outcome = wasCorrect ? 1.0 : 0.0;
    double delta = learningRate * (outcome - confidence);

    _weight = (_weight + delta).clamp(0.01, 1.0);
  }

  @override
  double getConfidence(List<String> history, int contextLength) {
    // Check if we have a match
    for (int len = 5; len >= 3; len--) {
      if (history.length < len) continue;
      String ctx = history.sublist(history.length - len).join();
      if (_patterns.containsKey(ctx)) {
        return 90.0; // High confidence on match
      }
    }
    return 0.0;
  }

  @override
  void reset() {
    _patterns.clear();
    _weight = 0.5;
    _usageCount = 0;
  }
}
