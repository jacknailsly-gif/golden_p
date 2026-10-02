import 'package:golden_p/models/game_mode.dart';

/// Represents a recorded Take-Profit milestone session when the bot hits its profit target.
class StopProfitMilestoneRecord {
  final DateTime timestamp;
  final GameMode mode;
  final double pnlPercent;
  final double targetPercent;
  final double endingBalance;
  final int breakMinutes;
  final DateTime resumeTime;

  StopProfitMilestoneRecord({
    required this.timestamp,
    required this.mode,
    required this.pnlPercent,
    required this.targetPercent,
    required this.endingBalance,
    required this.breakMinutes,
    required this.resumeTime,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'mode': mode.name,
        'pnlPercent': pnlPercent,
        'targetPercent': targetPercent,
        'endingBalance': endingBalance,
        'breakMinutes': breakMinutes,
        'resumeTime': resumeTime.toIso8601String(),
      };

  factory StopProfitMilestoneRecord.fromJson(Map<String, dynamic> json) {
    return StopProfitMilestoneRecord(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      mode: GameMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => GameMode.towers,
      ),
      pnlPercent: (json['pnlPercent'] as num?)?.toDouble() ?? 0.0,
      targetPercent: (json['targetPercent'] as num?)?.toDouble() ?? 0.0,
      endingBalance: (json['endingBalance'] as num?)?.toDouble() ?? 0.0,
      breakMinutes: (json['breakMinutes'] as num?)?.toInt() ?? 0,
      resumeTime: DateTime.tryParse(json['resumeTime']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
