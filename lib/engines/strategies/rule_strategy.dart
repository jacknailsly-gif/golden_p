import 'prediction_strategy.dart';

class RuleStrategy implements PredictionStrategy {
  final String conditionContext;
  final String predictedValue;
  double _confidence;
  final String _id;

  RuleStrategy({
    required this.conditionContext,
    required this.predictedValue,
    required double initialConfidence,
  }) : _confidence = initialConfidence,
       _id = "rule_${conditionContext}_$predictedValue";

  @override
  String get id => _id;

  @override
  String get name => "Rule: $conditionContext -> $predictedValue";

  @override
  double get weight => _confidence;

  @override
  double get ucbScore {
    // Rules are specific, so high confidence if context matches
    // Exploration is lower because it's a generated rule
    return _confidence + 0.05;
  }

  @override
  String? predict(List<String> history, int contextLength) {
    if (history.length < conditionContext.length) return null;

    String currentContext = history
        .sublist(history.length - conditionContext.length)
        .join();
    if (currentContext == conditionContext) {
      return predictedValue;
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
    // --- Incremental Weight Update (Delta Rule) ---
    double confidence = getConfidence(history, conditionContext.length) / 100.0;
    double outcome = wasCorrect ? 1.0 : 0.0;
    double delta = learningRate * (outcome - confidence);

    _confidence = (_confidence + delta).clamp(0.01, 1.0);
  }

  @override
  double getConfidence(List<String> history, int contextLength) {
    if (history.length < conditionContext.length) return 0.0;
    String currentContext = history
        .sublist(history.length - conditionContext.length)
        .join();

    if (currentContext == conditionContext) {
      return _confidence * 100.0;
    }
    return 0.0;
  }

  @override
  void reset() {
    // Rules persist? Or reset confidence?
    _confidence = 0.5;
  }
}
