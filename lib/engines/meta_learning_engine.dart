import 'package:flutter/foundation.dart';
import 'strategies/prediction_strategy.dart';
import 'strategies/ngram_strategy.dart';
import 'strategies/pattern_strategy.dart';
import 'strategies/bayesian_strategy.dart';
import 'strategies/rule_strategy.dart';

class MetaLearningEngine {
  // --- Components ---
  final List<PredictionStrategy> _strategyPool = [];
  final Map<String, int> _contextErrorCount = {};
  final Map<String, int> _contextUsageCount = {};

  // --- Configuration ---
  static const int _contextLength = 3;
  static const int _errorThreshold = 3;
  static const double _pruningThreshold = 0.35;
  static const int _metaLearningInterval = 50;

  // --- State ---
  PredictionStrategy? _activeStrategy;
  String? _lastContext;
  int _totalUpdates = 0;

  // --- Getters ---
  PredictionStrategy? get activeStrategy => _activeStrategy;
  List<PredictionStrategy> get strategies => _strategyPool;

  MetaLearningEngine() {
    _initializeStrategies();
  }

  void _initializeStrategies() {
    _strategyPool.add(NGramStrategy());
    _strategyPool.add(PatternStrategy());
    _strategyPool.add(BayesianStrategy());
  }

  /// Main Prediction Method
  String? predict(List<String> history) {
    if (history.length < _contextLength) return null;

    // 1. Get Context
    _lastContext = history.sublist(history.length - _contextLength).join();

    // 2. Select Strategy (UCB1)
    _activeStrategy = _selectStrategy(_lastContext!, history);

    if (_activeStrategy == null) return null;

    // 3. Make Prediction
    return _activeStrategy!.predict(history, _contextLength);
  }

  /// Update Loop (Feedback)
  void update(String actual, bool wasCorrect, List<String> history) {
    _totalUpdates++;

    // Calculate dynamic learning rate based on recent performance
    double learningRate = 0.1; // Base rate
    if (_lastContext != null) {
      int errors = _contextErrorCount[_lastContext!] ?? 0;
      if (errors > 0) {
        learningRate += (errors * 0.05).clamp(0.0, 0.2); // Accelerate on errors
      }
    }

    // Update all strategies (Passive Learning)
    for (var strategy in _strategyPool) {
      strategy.update(actual, wasCorrect, history, learningRate);
    }

    if (_lastContext != null) {
      // 1. Update Context Monitor
      _contextUsageCount[_lastContext!] =
          (_contextUsageCount[_lastContext!] ?? 0) + 1;
      if (!wasCorrect) {
        _contextErrorCount[_lastContext!] =
            (_contextErrorCount[_lastContext!] ?? 0) + 1;
      } else {
        _contextErrorCount[_lastContext!] = 0; // Reset error streak
      }

      // 2. Check for Strategy Generation Trigger
      if ((_contextErrorCount[_lastContext!] ?? 0) >= _errorThreshold) {
        debugPrint(
          "[Meta-Learner] 🚨 Error Threshold Reached for Context: $_lastContext",
        );
        _generateNewStrategy(_lastContext!, history);
        _contextErrorCount[_lastContext!] = 0; // Reset trigger
      }
    }

    // 3. Meta-Learning Cycle (Pruning/Mutation)
    if (_totalUpdates % _metaLearningInterval == 0) {
      _runMetaLearningOptimization();
    }
  }

  /// UCB1 Strategy Selector
  PredictionStrategy? _selectStrategy(String context, List<String> history) {
    if (_strategyPool.isEmpty) return null;

    PredictionStrategy? bestStrategy;
    double bestScore = -double.infinity;

    for (var strategy in _strategyPool) {
      // Exploitation: Strategy Confidence
      double confidence =
          strategy.getConfidence(history, _contextLength) / 100.0;

      // Exploration: Simple Bonus
      // We trust the strategy's UCB score plus context confidence
      double score = strategy.ucbScore + confidence;

      if (score > bestScore) {
        bestScore = score;
        bestStrategy = strategy;
      }
    }

    return bestStrategy;
  }

  /// Strategy Generator (PrefixSpan-lite)
  void _generateNewStrategy(String context, List<String> history) {
    // Search history for this context
    if (history.length < context.length + 1) return;

    Map<String, int> outcomes = {};
    int occurrences = 0;

    // Iterate up to len - 1 to find Next Char
    for (int i = 0; i < history.length - context.length; i++) {
      // Extract window
      String window = history.sublist(i, i + context.length).join();
      if (window == context) {
        // Found context at index i. Next char is at i + len
        if (i + context.length < history.length) {
          String nextChar = history[i + context.length];
          outcomes[nextChar] = (outcomes[nextChar] ?? 0) + 1;
          occurrences++;
        }
      }
    }

    if (outcomes.isEmpty) return;

    // Find most frequent outcome
    var sortedOutcomes = outcomes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var bestOutcome = sortedOutcomes.first;
    double confidence = bestOutcome.value / occurrences;

    // Only create rule if decent confidence
    if (confidence > 0.45) {
      var newRule = RuleStrategy(
        conditionContext: context,
        predictedValue: bestOutcome.key,
        initialConfidence: confidence,
      );

      // Avoid generating duplicate rules
      if (!_strategyPool.any((s) => s.id == newRule.id)) {
        _strategyPool.add(newRule);
        debugPrint(
          "[Meta-Learner] ✨ Created New Rule: ${newRule.name} (Conf: ${confidence.toStringAsFixed(2)})",
        );
      }
    }
  }

  void _runMetaLearningOptimization() {
    debugPrint("[Meta-Learner] 🧬 Running Optimization Cycle...");

    // 1. Pruning
    // Remove RuleStrategies that are performing poorly
    _strategyPool.removeWhere((s) {
      if (s is RuleStrategy && s.weight < _pruningThreshold) {
        debugPrint(
          "[Meta-Learner] ✂️ Pruned Strategy: ${s.name} (Weight: ${s.weight.toStringAsFixed(2)})",
        );
        return true;
      }
      return false;
    });

    // 2. Mutation (Implicit via Updates)
  }

  void reset() {
    _contextErrorCount.clear();
    _contextUsageCount.clear();
    _totalUpdates = 0;
    _activeStrategy = null;
    _lastContext = null;
    for (var s in _strategyPool) {
      s.reset();
    }
  }
}
