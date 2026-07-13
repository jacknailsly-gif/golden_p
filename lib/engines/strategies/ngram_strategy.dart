import '../../engines/n_gram_engine.dart';
import 'prediction_strategy.dart';

class NGramStrategy implements PredictionStrategy {
  final NGramEngine _engine = NGramEngine();
  double _weight = 0.5;
  int _usageCount = 0;
  int _successCount = 0;

  @override
  String get id => "ngram_v1";

  @override
  String get name => "N-Gram Strategy";

  @override
  double get weight => _weight;

  @override
  double get ucbScore {
    if (_usageCount == 0) return 100.0; // Exploration bonus for unused
    return (_successCount / _usageCount) + (1.0 / (_usageCount + 1));
  }

  @override
  String? predict(List<String> history, int contextLength) {
    if (history.isEmpty) return null;
    return _engine.predict(history);
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

    _engine.learn(history); // Continuous learning

    // --- Incremental Weight Update (Delta Rule) ---
    // Delta = LearningRate * (Outcome - Confidence)
    double confidence = getConfidence(history, 3) / 100.0;
    double outcome = wasCorrect ? 1.0 : 0.0;
    double delta = learningRate * (outcome - confidence);

    _weight = (_weight + delta).clamp(0.01, 1.0);
  }

  @override
  double getConfidence(List<String> history, int contextLength) {
    // Determine confidence based on N-Gram depth/frequency match?
    // For now, return weight scaled to 100
    return _weight * 100.0;
  }

  @override
  void reset() {
    _weight = 0.5;
    _usageCount = 0;
    _successCount = 0;
    // _engine.reset(); // If supported
  }
}
