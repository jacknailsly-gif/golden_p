import 'package:golden_p/models/history_entry.dart';
import 'package:golden_p/engines/time_series_engine.dart';
import 'package:golden_p/engines/v13_engine.dart';
import 'package:golden_p/engines/shadow_hunter_engine.dart';

class PredictionContext {
  final List<HistoryEntry> inputs;
  final String? lastFailedPrediction;
  final int incorrectStreak;
  final bool isV1EngineDominant;
  final Map<String, Map<String, int>> learningMemory;
  final bool isHighRisk; // V28.0: True during recovery/escalation rounds
  final int nonce; // V36.1: True Nonce for Cryptographic Determinism
  final double normalizedEntropy; // V70.1: Normalized Entropy for Anti-Overthinking (0.0 to 1.0)
  
  // Engines passed by reference for the pipeline to use
  final TimeSeriesEngine timeSeriesEngine;
  final V13Engine v13Engine;
  final ShadowHunterEngine shadowHunter;

  PredictionContext({
    required this.inputs,
    this.lastFailedPrediction,
    required this.incorrectStreak,
    required this.isV1EngineDominant,
    required this.learningMemory,
    this.isHighRisk = false,
    required this.nonce,
    this.normalizedEntropy = 0.0,
    required this.timeSeriesEngine,
    required this.v13Engine,
    required this.shadowHunter,
  });
}
