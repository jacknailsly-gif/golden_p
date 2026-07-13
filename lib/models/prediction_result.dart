class PredictionResult {
  final String primaryPrediction;
  final String decisionSource;
  final Map<String, double> scores;

  PredictionResult({
    required this.primaryPrediction,
    required this.decisionSource,
    required this.scores,
  });
}
