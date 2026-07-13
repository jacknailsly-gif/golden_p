/// Interface for all prediction strategies in the Meta-Learning System.
abstract class PredictionStrategy {
  /// The unique identifier for this strategy (e.g., "ngram_v1", "rule_abc_1").
  String get id;

  /// The human-readable name of the strategy (e.g., "N-Gram Strategy").
  String get name;

  /// Current weight/confidence of this strategy (0.0 - 1.0).
  double get weight;

  /// Exploration score (UCB) for Strategy Selector.
  double get ucbScore;

  /// Predicts the next value based on history and context.
  /// Returns 'A', 'B', 'C', or null if no prediction can be made.
  String? predict(List<String> history, int contextLength);

  /// Updates the strategy's internal state based on the actual result.
  void update(
    String actual,
    bool wasCorrect,
    List<String> history,
    double learningRate,
  );

  /// Returns the confidence score for the current context (0.0 - 100.0).
  double getConfidence(List<String> history, int contextLength);

  /// Resets the strategy state.
  void reset();
}
