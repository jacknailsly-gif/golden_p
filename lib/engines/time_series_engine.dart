import 'package:golden_p/models/history_entry.dart';
import 'package:golden_p/engines/i_prediction_engine.dart';

/// 🧠 Probability & Pattern Recognition Engine (A-B-C) v1.0
/// วิเคราะห์ความน่าจะเป็นจากข้อมูลอนุกรมเวลา (Time Series Data) โดยเน้นสถิติสะสมและรูปแบบซ้ำ
class TimeSeriesEngine implements IPredictionEngine {
  final List<String> buttonValues;

  // Weighting configurations (As per Prompt Logic v1.0)
  final double markovWeight = 0.35;
  final double patternWeight = 0.30;
  final double missingWeight = 0.25;
  final double globalWeight = 0.10;

  @override
  String get name => 'Time Series Engine';

  @override
  String get version => '1.0';

  TimeSeriesEngine(this.buttonValues);

  @override
  Map<String, double> predictProbs(List<HistoryEntry> history) {
    final result = analyze(history);
    final confidence = result['prediction']['confidence_score'] / 100.0;
    final primary = result['prediction']['primary'];
    final secondary = result['prediction']['secondary'];
    
    Map<String, double> probs = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    for (var v in buttonValues) {
      if (v == primary) {
        probs[v] = confidence;
      } else if (v == secondary) {
        probs[v] = (1.0 - confidence) * 0.7;
      } else {
        probs[v] = (1.0 - confidence) * 0.3;
      }
    }
    return probs;
  }

  /// เมธอดหลักสำหรับวิเคราะห์ประวัติและให้คำแนะนำในรูปแบบ JSON
  Map<String, dynamic> analyze(List<HistoryEntry> history, {String? lastErrorContext}) {
    if (history.isEmpty) {
      return {
        'prediction': {
          'primary': buttonValues[0],
          'secondary': buttonValues[1],
          'confidence_score': 0.0,
        },
        'statistics': {'frequencies': {}, 'missing_rounds': {}},
        'reasoning': 'ข้อมูลประวัติยังไม่เพียงพอสำหรับการวิเคราะห์',
      };
    }

    // --- STEP 1: Global Frequency Analysis ---
    final Map<String, double> globalFreq = _calculateGlobalFrequency(history);

    // --- STEP 2: Markov Chain (Conditional Probability) ---
    final Map<String, double> markovProbs = _calculateMarkovChain(history);

    // --- STEP 3: Missing/Overdue Analysis (Gap Analysis) ---
    final Map<String, int> gaps = _calculateGaps(history);
    final Map<String, double> gapProbs = _normalizeGapsIntoProbs(gaps);

    // --- STEP 4: Pattern & Cycle Recognition ---
    final Map<String, double> patternProbs = _calculatePatternProbs(history);

    // --- STEP 5: Special Attribute Analysis (Red Markers) ---
    final Map<String, double> attributeInfluence = _analyzeAttributes(history);

    // --- STEP 6: Outlier & Trend Shift Detection (V8.1) ---
    final Map<String, double> dynamicShift = _detectTrendShift(history, lastErrorContext: lastErrorContext);

    // --- COMBINE WEIGHTS ---
    final Map<String, double> finalScores = {};
    for (var val in buttonValues) {
      // Base score calculation using designated weights (Step 6 adjusts these weightings)
      
      // V8.1: Dynamically adjusted weights from Root Cause Analysis
      double currentPatternWeight = patternWeight * (dynamicShift['pattern'] ?? 1.0);
      double currentMarkovWeight = markovWeight * (dynamicShift['markov'] ?? 1.0);
      double currentMissingWeight = missingWeight * (dynamicShift['missing'] ?? 1.0);

      double score =
          (globalFreq[val] ?? 0.0) * globalWeight +
          ((markovProbs[val] ?? 0.0) * currentMarkovWeight) +
          ((gapProbs[val] ?? 0.0) * currentMissingWeight) +
          ((patternProbs[val] ?? 0.0) * currentPatternWeight);

      // Apply attribute influence (Special Step 5)
      score += (attributeInfluence[val] ?? 0.0) * 0.15;

      finalScores[val] = score;
    }

    // --- NEW: Winner-Shift Logic (Prompt Logic v1.1) ---
    // REMOVED: This logic forces the AI to abandon winning streaks and causes stupid ping-pong (A-B-A) oscillations.
    // We should let the AI confidently follow the pattern if it's winning.

    // Sort to determine Primary and Secondary choices
    final sortedByScore = finalScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final String primary = sortedByScore[0].key;
    final String secondary = sortedByScore.length > 1
        ? sortedByScore[1].key
        : primary;

    // Confidence Score Calculation (%)
    double totalCombined = finalScores.values.fold(0, (sum, val) => sum + val);
    double confidence = totalCombined > 0
        ? (finalScores[primary] ?? 0.0) / totalCombined * 100
        : 0.0;

    return {
      'prediction': {
        'primary': primary,
        'secondary': secondary,
        'confidence_score': double.parse(confidence.toStringAsFixed(1)),
      },
      'statistics': {'frequencies': globalFreq, 'missing_rounds': gaps},
      'reasoning': _generateReasoning(history, primary, finalScores),
    };
  }

  // STEP 1: Global Frequency Logic
  Map<String, double> _calculateGlobalFrequency(List<HistoryEntry> history) {
    final counts = <String, int>{};
    for (var v in buttonValues) {
      counts[v] = 0;
    }
    for (var entry in history) {
      if (counts.containsKey(entry.value)) {
        counts[entry.value] = (counts[entry.value] ?? 0) + 1;
      }
    }
    final total = history.length;
    return counts.map((k, v) => MapEntry(k, total > 0 ? v / total : 0.0));
  }

  // STEP 2: Markov Chain Logic (Conditional Probability)
  Map<String, double> _calculateMarkovChain(List<HistoryEntry> history) {
    if (history.length < 2) {
      return {};
    }
    final lastState = history.last.value;
    final successors = <String, int>{};
    for (var v in buttonValues) {
      successors[v] = 0;
    }

    int totalMatches = 0;
    for (int i = 0; i < history.length - 1; i++) {
      if (history[i].value == lastState) {
        final nextVal = history[i + 1].value;
        if (successors.containsKey(nextVal)) {
          successors[nextVal] = (successors[nextVal] ?? 0) + 1;
          totalMatches++;
        }
      }
    }

    if (totalMatches == 0) {
      return {};
    }
    return successors.map((k, v) => MapEntry(k, v / totalMatches));
  }

  // STEP 3: Missing/Overdue Analysis (Gap Analysis)
  Map<String, int> _calculateGaps(List<HistoryEntry> history) {
    final gaps = <String, int>{};
    for (final char in buttonValues) {
      int count = 0;
      for (int i = history.length - 1; i >= 0; i--) {
        if (history[i].value == char) {
          break;
        }
        count++;
      }
      gaps[char] = count;
    }
    return gaps;
  }

  Map<String, double> _normalizeGapsIntoProbs(Map<String, int> gaps) {
    if (gaps.isEmpty) return {};

    double totalGaps = gaps.values.fold(
      0.0,
      (sum, val) => sum + val.toDouble(),
    );
    if (totalGaps == 0) {
      return {};
    }
    // High Gap = High Probability (Rebound Weight)
    return gaps.map((k, v) => MapEntry(k, v.toDouble() / totalGaps));
  }

  // STEP 4: Pattern & Cycle Recognition
  Map<String, double> _calculatePatternProbs(List<HistoryEntry> history) {
    final Map<String, double> probs = {};
    for (var v in buttonValues) {
      probs[v] = 0.0;
    }
    if (history.length < 2) {
      return probs;
    }

    final sequence = history.map((e) => e.value).toList();
    final n = sequence.length;

    // Detect Ping-Pong Flow: A-B-A -> Target B
    if (n >= 3 &&
        sequence[n - 1] == sequence[n - 3] &&
        sequence[n - 1] != sequence[n - 2]) {
      probs[sequence[n - 2]] = 1.0;
    }

    // Detect Double Streaks: B-B -> Target A/C (Pattern Break / Switch)
    if (sequence[n - 1] == sequence[n - 2]) {
      for (var v in buttonValues) {
        if (v != sequence[n - 1]) {
          probs[v] = 0.5;
        }
      }
    }

    return probs;
  }

  // STEP 5: Special Attribute Analysis (Red Markers)
  Map<String, double> _analyzeAttributes(List<HistoryEntry> history) {
    final influence = <String, double>{};
    for (var v in buttonValues) {
      influence[v] = 0.0;
    }
    if (history.isEmpty) {
      return influence;
    }

    final lastEntry = history.last;
    if (lastEntry.isRed) {
      // After a 'red' marker, prioritize 'Switching' algorithm or Trend Following
      for (var v in buttonValues) {
        if (v != lastEntry.value) {
          influence[v] = 0.4; // Weighted influence to favor switch
        }
      }
    }

    return influence;
  }

  // STEP 6: Outlier & Trend Shift Detection
  Map<String, double> _detectTrendShift(List<HistoryEntry> history, {String? lastErrorContext}) {
    final shifts = {'markov': 1.0, 'pattern': 1.0, 'missing': 1.0};
    
    // V8.1 Self-Correction Overrides
    if (lastErrorContext != null) {
      if (lastErrorContext == "Pattern Inversion") {
        shifts['pattern'] = 0.4;  // Distrust pattern heavily
        shifts['missing'] = 1.5;  // Trust missing/gaps more
      } else if (lastErrorContext == "Overdue Rebound") {
        shifts['markov'] = 1.6;   // Heavy bias toward the new Markov flow
      } else if (lastErrorContext == "Streak Broken") {
        shifts['pattern'] = 1.3;  // Look for a new pattern
        shifts['markov'] = 0.5;   // Distrust Markov
      }
    }

    if (history.length < 4) {
      return shifts;
    }

    final seq = history.map((e) => e.value).toList();
    final n = seq.length;

    // Detect 'Outlier' event: e.g. 4 identical characters in a row (Extreme Trend)
    if (seq[n - 1] == seq[n - 2] &&
        seq[n - 2] == seq[n - 3] &&
        seq[n - 3] == seq[n - 4]) {
      // Trend Shift: Reduce reliance on pattern/markov, increase reliance on overdue GAP
      shifts['markov'] = (shifts['markov'] ?? 1.0) * 0.4;
      shifts['pattern'] = (shifts['pattern'] ?? 1.0) * 0.3;
      shifts['missing'] = (shifts['missing'] ?? 1.0) * 1.5;
    }

    return shifts;
  }

  String _generateReasoning(
    List<HistoryEntry> history,
    String prediction,
    Map<String, double> finalWeights,
  ) {
    if (history.length < 3) {
      return 'คำนวณจาก Global Frequency และสถิติพื้นฐาน';
    }

    // Check for Winner-Shift (Last was Win)
    if (history.isNotEmpty && !history.last.isRed) {
      return 'Winner Shift: Avoiding [${history.last.value}] implies new pattern start.';
    }

    // Check dominant factor
    if ((finalWeights[prediction] ?? 0) > 0.6) {
      return 'ตรวจพบรูปแบบซ้ำซ้อน (Strong Pattern Match) และ Markov Flow';
    }

    return 'วิเคราะห์รูปแบบการไหล (Flow Analysis) และสถิติตามน้ำ (Trend Following)';
  }
}
