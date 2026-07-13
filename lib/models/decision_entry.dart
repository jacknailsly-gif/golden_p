class DecisionEntry {
  final DateTime timestamp;
  final String selectedAction;
  final double confidence;
  final String decisionReason;

  DecisionEntry({
    required this.timestamp,
    required this.selectedAction,
    required this.confidence,
    required this.decisionReason,
  });

  @override
  String toString() {
    return '[${timestamp.toIso8601String()}] ->$selectedAction '
        '(conf: ${confidence.toStringAsFixed(1)}%, reason: $decisionReason)';
  }
}
