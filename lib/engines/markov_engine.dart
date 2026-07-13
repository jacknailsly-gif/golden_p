/// 📈 Markov Chain Prediction Engine
class MarkovEngine {
  
  // Transition Matrix: State -> {NextState: Count}
  final Map<String, Map<String, int>> _matrix = {
    'A': {'A': 0, 'B': 0, 'C': 0},
    'B': {'A': 0, 'B': 0, 'C': 0},
    'C': {'A': 0, 'B': 0, 'C': 0},
  };

  /// Update matrix with the latest transition
  void update(List<String> history) {
    if (history.length < 2) return;
    
    String prev = history[history.length - 2];
    String curr = history.last;
    
    if (_matrix.containsKey(prev) && _matrix[prev]!.containsKey(curr)) {
      _matrix[prev]![curr] = _matrix[prev]![curr]! + 1;
    }
  }

  /// Get probabilities for the next state based on current state
  Map<String, double> getProbabilities(String? currentState) {
    Map<String, double> probs = {'A': 0.33, 'B': 0.33, 'C': 0.33};
    
    if (currentState == null || !_matrix.containsKey(currentState)) {
      return probs;
    }

    var transitions = _matrix[currentState]!;
    int total = transitions.values.fold(0, (sum, count) => sum + count);
    
    if (total > 0) {
      probs['A'] = transitions['A']! / total;
      probs['B'] = transitions['B']! / total;
      probs['C'] = transitions['C']! / total;
    }
    
    return probs;
  }

  /// Predict next based on highest transition probability
  String? predict(String? currentState) {
    var probs = getProbabilities(currentState);
    var sorted = probs.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    if (sorted.first.value <= 0.34) return null; // Too uncertain
    return sorted.first.key;
  }

  void reset() {
    for (var row in _matrix.values) {
      row['A'] = 0;
      row['B'] = 0;
      row['C'] = 0;
    }
  }
}
