import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class PredictionResult {
  final String chosenTarget;
  final double confidence;
  final Map<String, double> distribution;
  final String rationale;

  const PredictionResult({
    required this.chosenTarget,
    required this.confidence,
    required this.distribution,
    required this.rationale,
  });
}

class AutonomousPredictionEngine {
  static final AutonomousPredictionEngine _instance = AutonomousPredictionEngine._internal();
  factory AutonomousPredictionEngine() => _instance;
  AutonomousPredictionEngine._internal() {
    rotateSeed();
  }

  static const List<String> towerColumns = ['A', 'B', 'C'];
  final List<String> _bombHistory = [];
  final List<String> _lossSequence = [];
  final Map<String, Map<String, double>> _markovTransitions = {};

  late String _serverSeed;
  late String _clientSeed;
  int _nonce = 0;
  final Random _rng = Random();

  void rotateSeed() {
    const chars = '0123456789abcdef';
    _serverSeed = Iterable.generate(64, (_) => chars[_rng.nextInt(chars.length)]).join();
    _clientSeed = Iterable.generate(24, (_) => chars[_rng.nextInt(chars.length)]).join();
    _nonce = 0;
  }

  void recordOutcome({required String chosen, required bool won, String? revealedBomb}) {
    if (won) {
      _lossSequence.clear();
    } else {
      _lossSequence.add(chosen);
      if (_lossSequence.length > 10) _lossSequence.removeAt(0);
    }

    String? bomb = revealedBomb ?? (!won ? chosen : null);
    if (bomb != null && towerColumns.contains(bomb)) {
      _bombHistory.add(bomb);
      if (_bombHistory.length > 50) _bombHistory.removeAt(0);

      // Update 1st-Order Markov Chain Transitions
      if (_bombHistory.length >= 2) {
        String prevBomb = _bombHistory[_bombHistory.length - 2];
        _markovTransitions.putIfAbsent(prevBomb, () => {'A': 1.0, 'B': 1.0, 'C': 1.0});
        for (var col in towerColumns) {
          if (col != bomb) {
            _markovTransitions[prevBomb]![col] = (_markovTransitions[prevBomb]![col] ?? 1.0) + 1.0;
          }
        }
      }
    }
  }

  /// Calculates safest candidate
  PredictionResult predictNextMove() {
    final int streak = _lossSequence.length;
    List<String> activeCandidates = List.from(towerColumns);

    // 1. Hard Exclusion: If 1 loss, exclude that column
    if (streak == 1) {
      activeCandidates.remove(_lossSequence.last);
    }

    // 2. Deterministic Isolation: If 2 losses, force 3rd untouched column
    if (streak == 2) {
      final failed = _lossSequence.toSet();
      final untainted = towerColumns.where((c) => !failed.contains(c)).toList();
      if (untainted.isNotEmpty) {
        final target = untainted.first;
        _nonce++;
        return PredictionResult(
          chosenTarget: target,
          confidence: 99.0,
          distribution: {target: 0.99, towerColumns.firstWhere((c) => c != target): 0.005, towerColumns.lastWhere((c) => c != target): 0.005},
          rationale: 'Deterministic 3rd Node Isolation on Loss Streak = 2',
        );
      }
    }

    // 3. Markov + Exponential Spatial Decay Heatmap
    Map<String, double> dangerHeatmap = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    for (int i = 0; i < _bombHistory.length; i++) {
      int stepsAgo = _bombHistory.length - 1 - i;
      double decay = pow(0.70, stepsAgo).toDouble();
      dangerHeatmap[_bombHistory[i]] = (dangerHeatmap[_bombHistory[i]] ?? 0.0) + decay;
    }

    // 4. Scoring and Normalization
    Map<String, double> scores = {};
    for (var col in activeCandidates) {
      double markovScore = 1.0;
      if (_bombHistory.isNotEmpty && _markovTransitions.containsKey(_bombHistory.last)) {
        markovScore = _markovTransitions[_bombHistory.last]![col] ?? 1.0;
      }
      double penalty = dangerHeatmap[col] ?? 0.0;
      scores[col] = max(markovScore - (penalty * 0.5), 0.01);
    }

    double totalScore = scores.values.fold(0.0, (a, b) => a + b);
    Map<String, double> dist = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    scores.forEach((col, val) => dist[col] = val / totalScore);

    String bestTarget = activeCandidates.first;
    double maxProb = -1.0;
    for (var col in activeCandidates) {
      if ((dist[col] ?? 0.0) > maxProb) {
        maxProb = dist[col]!;
        bestTarget = col;
      }
    }

    _nonce++;
    return PredictionResult(
      chosenTarget: bestTarget,
      confidence: min(max(maxProb * 100.0, 60.0), 98.0),
      distribution: dist,
      rationale: 'Bayesian Markov Consensus with Heatmap Repulsion',
    );
  }
}
