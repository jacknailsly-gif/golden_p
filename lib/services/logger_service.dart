import 'dart:convert';
import 'package:flutter/foundation.dart';

enum GameType { towers, mines }

class RoundTelemetry {
  final int roundIndex;
  final GameType gameType;
  final String predictedChoice;
  final String actualOutcome;
  final bool isWin;
  final double betAmount;
  final double currentBalance;
  final int consecutiveLossStreak;
  final Map<String, double> probabilityDist;
  final List<String> recentBombHistory;

  RoundTelemetry({
    required this.roundIndex,
    required this.gameType,
    required this.predictedChoice,
    required this.actualOutcome,
    required this.isWin,
    required this.betAmount,
    required this.currentBalance,
    required this.consecutiveLossStreak,
    required this.probabilityDist,
    required this.recentBombHistory,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': DateTime.now().toIso8601String(),
    'round': roundIndex,
    'game': gameType.name,
    'prediction': predictedChoice,
    'actual': actualOutcome,
    'is_win': isWin,
    'bet': betAmount,
    'balance': currentBalance,
    'loss_streak': consecutiveLossStreak,
    'distribution': probabilityDist,
    'bomb_history': recentBombHistory,
  };
}

class TelemetryLoggerService {
  static final TelemetryLoggerService _instance = TelemetryLoggerService._internal();
  factory TelemetryLoggerService() => _instance;
  TelemetryLoggerService._internal();

  void logRound(RoundTelemetry telemetry) {
    final payload = jsonEncode(telemetry.toJson());
    // Emit Logcat prefix specifically for Host Watchdog extraction
    debugPrint('[AUTONOMOUS_FEEDBACK] $payload');
  }
}
