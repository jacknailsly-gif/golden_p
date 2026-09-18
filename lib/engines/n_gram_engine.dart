import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 🧠 Smart N-Gram Prediction Engine
/// Learns patterns (A-B-C, A-A-B, etc.) and predicts future outcomes based on historical frequency.
class NGramEngine {
  final List<String> _candidates = ['A', 'B', 'C'];
  final int _maxN = 5; // Maximum context depth (5-Gram)

  // Storage: Context -> {NextChar: Count}
  // Example: "AB" -> {'C': 5, 'A': 1}
  Map<String, Map<String, int>> _memory = {};
  
  static const String _prefsKey = 'ngram_engine_memory';

  /// Load persistent memory from local storage (Cross-session knowledge)
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _memory = decoded.map((key, value) {
          return MapEntry(key, Map<String, int>.from(value as Map));
        });
        debugPrint('🧠 [NGramEngine] Loaded persistent memory: ${_memory.length} patterns.');
      }
    } catch (e) {
      debugPrint('⚠️ [NGramEngine] Failed to load memory: $e');
    }
  }

  /// Save current memory to local storage
  Future<void> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonStr = jsonEncode(_memory);
      await prefs.setString(_prefsKey, jsonStr);
      debugPrint('💾 [NGramEngine] Saved memory to disk.');
    } catch (e) {
      debugPrint('⚠️ [NGramEngine] Failed to save memory: $e');
    }
  }

  /// Learn from the latest history update
  void learn(List<String> history) {
    if (history.length < 2) return;

    // Learn from the most recent sequence at various depths
    // We only need to update patterns ending at the *last* item
    // Sequence: ... [A, B, C] -> Target is C, Context is AB (for N=3)

    String target = history.last;

    // Iterate depths from N=2 to MaxN
    for (int n = 2; n <= _maxN; n++) {
      if (history.length < n) break;

      // Extract context (previous n-1 characters)
      int contextStart = history.length - n;
      List<String> contextList = history.sublist(
        contextStart,
        history.length - 1,
      );
      String contextKey = contextList.join('');

      _updateMemory(contextKey, target);
    }
  }

  void _updateMemory(String context, String nextChar) {
    if (!_memory.containsKey(context)) {
      _memory[context] = {};
    }
    _memory[context]![nextChar] = (_memory[context]![nextChar] ?? 0) + 1;
  }

  /// Predict the next single value based on history
  String predict(List<String> history, {String? avoid}) {
    Map<String, double> scores = _calculateProbabilities(history);

    // Sort by probability descending
    var sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isEmpty) {
      // Fallback: Random or based on single frequency
      return _candidates[Random().nextInt(_candidates.length)];
    }

    // Apply "Avoid" constraint (Lose-Switch logic)
    if (avoid != null) {
      for (var entry in sorted) {
        if (entry.key != avoid) {
          return entry.key;
        }
      }
    }

    return sorted.first.key;
  }

  /// Calculate probability for each candidate based on current context
  Map<String, double> _calculateProbabilities(List<String> history) {
    Map<String, double> totalScores = {'A': 0.0, 'B': 0.0, 'C': 0.0};

    // Weight longer contexts higher (more specific patterns)
    // N=5 (Wt 4), N=4 (Wt 3), N=3 (Wt 2), N=2 (Wt 1)

    for (int n = 2; n <= _maxN; n++) {
      if (history.length < n - 1) break;

      int contextLen = n - 1;
      int start = history.length - contextLen;
      String context = history.sublist(start).join('');

      if (_memory.containsKey(context)) {
        var counts = _memory[context]!;
        int total = counts.values.fold(0, (sum, c) => sum + c);

        if (total > 0) {
          double weight = (n - 1).toDouble(); // Longer context = Higher weight
          counts.forEach((char, count) {
            double prob = count / total;
            totalScores[char] = (totalScores[char] ?? 0) + (prob * weight);
          });
        }
      }
    }

    return totalScores;
  }

  /// Recursively forecast future steps
  List<String> forecast(List<String> history, int steps) {
    List<String> future = [];
    List<String> virtualHistory = List.from(history);

    for (int i = 0; i < steps; i++) {
      // Predict next step
      String next = predict(virtualHistory);
      future.add(next);

      // Append to virtual history for next recursion
      virtualHistory.add(next);
    }

    return future;
  }

  Map<String, dynamic> getDebugInfo(List<String> history) {
    Map<String, double> probs = _calculateProbabilities(history);
    return {'probabilities': probs, 'memory_size': _memory.length};
  }
}
