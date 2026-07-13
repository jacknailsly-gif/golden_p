import 'prediction_strategy.dart';

class BayesianStrategy implements PredictionStrategy {
  // Context -> {NextChar -> WeightedCount}
  final Map<String, Map<String, double>> _probabilities = {};
  double _weight = 0.5;
  int _usageCount = 0;
  int _successCount = 0;

  static const double _forgettingFactor = 0.95; // Decay rate per update

  @override
  String get id => "bayesian_forget";

  @override
  String get name => "Bayesian (Adaptive)";

  @override
  double get weight => _weight;

  @override
  double get ucbScore {
    if (_usageCount == 0) return 90.0;
    return (_successCount / _usageCount) + (0.5 / (_usageCount + 1));
  }

  @override
  String? predict(List<String> history, int contextLength) {
    if (history.length < contextLength) return null;
    String ctx = history.sublist(history.length - contextLength).join();

    if (_probabilities.containsKey(ctx)) {
      var nextMap = _probabilities[ctx]!;
      // Find max probability
      String? bestChar;
      double maxProb = -1.0;

      nextMap.forEach((char, score) {
        if (score > maxProb) {
          maxProb = score;
          bestChar = char;
        }
      });
      return bestChar;
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
    if (wasCorrect) _successCount++;

    // Standard Bayesian Logic: Flexible context learning
    int ctxLen = 3;
    if (history.length < ctxLen + 1) return;

    List<String> prevHistory = history.sublist(0, history.length - 1);
    String ctx = prevHistory.sublist(prevHistory.length - ctxLen).join();

    if (!_probabilities.containsKey(ctx)) {
      _probabilities[ctx] = {'A': 0.1, 'B': 0.1, 'C': 0.1};
    }

    _probabilities[ctx]!.updateAll((key, val) => val * _forgettingFactor);
    _probabilities[ctx]![actual] = (_probabilities[ctx]![actual] ?? 0) + 1.0;

    // --- Incremental Weight Update (Delta Rule) ---
    double confidence = getConfidence(history, 3) / 100.0;
    double outcome = wasCorrect ? 1.0 : 0.0;
    double delta = learningRate * (outcome - confidence);

    _weight = (_weight + delta).clamp(0.01, 1.0);
  }

  @override
  double getConfidence(List<String> history, int contextLength) {
    if (history.length < contextLength) return 0.0;
    String ctx = history.sublist(history.length - contextLength).join();

    if (_probabilities.containsKey(ctx)) {
      var nextMap = _probabilities[ctx]!;
      double total = nextMap.values.fold(0, (sum, v) => sum + v);
      if (total == 0) return 0.0;

      double maxScore = nextMap.values.fold(0, (max, v) => v > max ? v : max);
      return (maxScore / total) * 100.0;
    }
    return 0.0;
  }

  @override
  void reset() {
    _probabilities.clear();
    _weight = 0.5;
    _usageCount = 0;
    _successCount = 0;
  }
}
