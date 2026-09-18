import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// V122: AI Training Data Logger
/// Captures round-by-round prediction data for ML model training.
/// Saves data as CSV files to device storage for offline analysis.
class TrainingDataLogger {
  static final TrainingDataLogger _instance = TrainingDataLogger._internal();
  factory TrainingDataLogger() => _instance;
  TrainingDataLogger._internal();

  final List<Map<String, dynamic>> _buffer = [];
  static const int _flushThreshold = 50; // Auto-save every 50 rounds
  int _sessionRoundCount = 0;
  String? _sessionId;

  /// CSV Header columns
  static const List<String> csvHeaders = [
    'timestamp',
    'session_id',
    'round_index',
    'bomb_history_last5',
    'bomb_freq_A',
    'bomb_freq_B',
    'bomb_freq_C',
    'win_streak',
    'loss_streak',
    'ai_prediction',
    'ai_confidence',
    'bot_selected',
    'bet_amount',
    'balance',
    'pattern_last3',
    'pattern_last5',
    'entropy',
    'decision_source',
    'actual_bomb_pos',
    'actual_gem_pos',
    'was_correct',
  ];

  /// Initialize a new session
  void startSession() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _sessionRoundCount = 0;
    debugPrint('[V122 DATA LOGGER] 📊 New training session started: $_sessionId');
  }

  /// End session and flush remaining data
  Future<void> endSession() async {
    debugPrint('[V122 DATA LOGGER] 🛑 Session ended: $_sessionId. Flushing remaining data...');
    await flushToFile();
  }

  /// Log a single round of data
  Future<void> logRound({
    required int roundIndex,
    required List<String> bombHistoryLast12,
    required int winStreak,
    required int lossStreak,
    required String aiPrediction,
    required double aiConfidence,
    required String botSelected,
    required double betAmount,
    required double balance,
    required List<String> recentGemPositions,
    required double entropy,
    required String decisionSource,
    required String actualBombPos,
    required String actualGemPos,
    required bool wasCorrect,
  }) async {
    _sessionRoundCount++;

    // Calculate bomb frequencies from last 12 bombs
    int totalBombs = bombHistoryLast12.length;
    double freqA = totalBombs > 0 ? bombHistoryLast12.where((b) => b == 'A').length / totalBombs : 0.33;
    double freqB = totalBombs > 0 ? bombHistoryLast12.where((b) => b == 'B').length / totalBombs : 0.33;
    double freqC = totalBombs > 0 ? bombHistoryLast12.where((b) => b == 'C').length / totalBombs : 0.33;

    // Get last 5 bomb history as string
    List<String> last5Bombs = bombHistoryLast12.length > 5
        ? bombHistoryLast12.sublist(bombHistoryLast12.length - 5)
        : bombHistoryLast12;

    // Get pattern last 3 and last 5 gem positions
    List<String> patternLast3 = recentGemPositions.length > 3
        ? recentGemPositions.sublist(recentGemPositions.length - 3)
        : recentGemPositions;
    List<String> patternLast5 = recentGemPositions.length > 5
        ? recentGemPositions.sublist(recentGemPositions.length - 5)
        : recentGemPositions;

    final Map<String, dynamic> row = {
      'timestamp': DateTime.now().toIso8601String(),
      'session_id': _sessionId ?? 'unknown',
      'round_index': roundIndex,
      'bomb_history_last5': last5Bombs.join(';'),
      'bomb_freq_A': freqA.toStringAsFixed(4),
      'bomb_freq_B': freqB.toStringAsFixed(4),
      'bomb_freq_C': freqC.toStringAsFixed(4),
      'win_streak': winStreak,
      'loss_streak': lossStreak,
      'ai_prediction': aiPrediction,
      'ai_confidence': aiConfidence.toStringAsFixed(2),
      'bot_selected': botSelected,
      'bet_amount': betAmount.toStringAsFixed(6),
      'balance': balance.toStringAsFixed(6),
      'pattern_last3': patternLast3.join(';'),
      'pattern_last5': patternLast5.join(';'),
      'entropy': entropy.toStringAsFixed(4),
      'decision_source': decisionSource,
      'actual_bomb_pos': actualBombPos,
      'actual_gem_pos': actualGemPos,
      'was_correct': wasCorrect ? '1' : '0',
    };

    _buffer.add(row);

    debugPrint('[V122 DATA LOGGER] 📝 Round $_sessionRoundCount logged. Buffer: ${_buffer.length}/$_flushThreshold');

    // Auto-flush when buffer reaches threshold
    if (_buffer.length >= _flushThreshold) {
      await flushToFile();
    }
  }

  /// Flush buffer to CSV file on device storage
  Future<String?> flushToFile() async {
    if (_buffer.isEmpty) {
      debugPrint('[V122 DATA LOGGER] ⚠️ No data to flush.');
      return null;
    }

    try {
      final directory = await _getStorageDirectory();
      if (directory == null) {
        debugPrint('[V122 DATA LOGGER] ❌ Could not get storage directory.');
        return null;
      }

      final String fileName = 'training_data_${_sessionId ?? 'unknown'}.csv';
      final File file = File('${directory.path}/$fileName');

      // Check if file exists (if not, write header first)
      bool fileExists = await file.exists();

      final StringBuffer csvContent = StringBuffer();

      if (!fileExists) {
        // Write CSV header
        csvContent.writeln(csvHeaders.join(','));
      }

      // Write each buffered row
      for (final row in _buffer) {
        List<String> values = csvHeaders.map((header) {
          String val = (row[header] ?? '').toString();
          // Escape commas and quotes in values
          if (val.contains(',') || val.contains('"')) {
            val = '"${val.replaceAll('"', '""')}"';
          }
          return val;
        }).toList();
        csvContent.writeln(values.join(','));
      }

      // Append to file
      await file.writeAsString(csvContent.toString(), mode: FileMode.append);

      int flushedCount = _buffer.length;
      _buffer.clear();

      debugPrint('[V122 DATA LOGGER] ✅ Flushed $flushedCount rows to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[V122 DATA LOGGER] ❌ Error flushing data: $e');
      return null;
    }
  }

  /// Export all buffered data immediately (manual trigger from UI)
  Future<String?> exportNow() async {
    debugPrint('[V122 DATA LOGGER] 📤 Manual export triggered. Buffer: ${_buffer.length} rows.');
    return await flushToFile();
  }

  /// Get total rows logged this session
  int get totalRowsLogged => _sessionRoundCount;

  /// Get current buffer size
  int get bufferSize => _buffer.length;

  /// Get storage directory for CSV files
  Future<Directory?> _getStorageDirectory() async {
    try {
      // Try external storage first (Download folder on Android)
      if (Platform.isAndroid) {
        final Directory downloadDir = Directory('/storage/emulated/0/Download/golden_p_training_data');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      }
      // Fallback to app documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory trainingDir = Directory('${appDir.path}/golden_p_training_data');
      if (!await trainingDir.exists()) {
        await trainingDir.create(recursive: true);
      }
      return trainingDir;
    } catch (e) {
      debugPrint('[V122 DATA LOGGER] ❌ Storage error: $e');
      // Final fallback
      try {
        return await getApplicationDocumentsDirectory();
      } catch (e2) {
        debugPrint('[V122 DATA LOGGER] ❌ Final fallback failed: $e2');
        return null;
      }
    }
  }

  /// Get the file path for the current session's CSV
  Future<String?> getCurrentFilePath() async {
    final directory = await _getStorageDirectory();
    if (directory == null) return null;
    return '${directory.path}/training_data_${_sessionId ?? 'unknown'}.csv';
  }

  /// Get list of all training data files
  Future<List<FileSystemEntity>> getAllTrainingFiles() async {
    final directory = await _getStorageDirectory();
    if (directory == null) return [];
    try {
      return directory.listSync().where((f) => f.path.endsWith('.csv')).toList();
    } catch (e) {
      return [];
    }
  }
}
