import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/history_entry.dart';

enum SystemMode { normal, recovery, defense, counter }

enum V13GamePhase { trend, chaos, trap, recovery }

enum BetRecommendation { normal, double, reset, x1_3, x1_5 }

class AgentDecision {
  final String action;
  final double confidence;
  final double riskScore;
  final String reason;

  AgentDecision(this.action, this.confidence, this.riskScore, this.reason);

  @override
  String toString() => '[$action, ${(confidence * 100).toStringAsFixed(0)}%]';
}

class V13Decision {
  final SystemMode mode;
  final V13GamePhase phase;
  final String pattern;
  final String lastResult;
  final int lossStreak;
  final String? blockedAction;
  final String strategyUsed;
  final double confidence;
  final double betAdjustment; // Percentage 0.0 to 1.0
  final String finalDecision;
  final BetRecommendation betRecommendation;
  final String reason;

  V13Decision({
    required this.mode,
    required this.phase,
    required this.pattern,
    required this.lastResult,
    required this.lossStreak,
    this.blockedAction,
    required this.strategyUsed,
    required this.confidence,
    required this.betAdjustment,
    required this.finalDecision,
    required this.betRecommendation,
    required this.reason,
  });

  void printDecision() {
    debugPrint('--- 🧠 CORE ENGINE V13.0 ADAPTIVE RECOVERY ---');
    debugPrint('* Mode: ${mode.toString().split('.').last.toUpperCase()}');
    debugPrint('* Phase: ${phase.toString().split('.').last.toUpperCase()}');
    debugPrint('* Pattern: $pattern');
    debugPrint('* Loss Streak: $lossStreak');
    debugPrint('* Blocked: ${blockedAction ?? "None"}');
    debugPrint('* Strategy: $strategyUsed');
    debugPrint('* Confidence: ${(confidence * 100).toStringAsFixed(1)}%');
    debugPrint('* Bet Adjustment: ${(betAdjustment * 100).toStringAsFixed(0)}%');
    debugPrint('* Recommendation: ${betRecommendation.toString().split('.').last}');
    debugPrint('* Final Decision: $finalDecision');
    debugPrint('* Reason: $reason');
    debugPrint('---------------------------------------------');
  }
}

class V13Engine {
  // Stats & Memory
  SystemMode _currentMode = SystemMode.normal;
  int _consecutiveLosses = 0;
  final Map<String, String> _lossMap = {}; // Pattern -> LastLosingAction
  final List<String> _recentSequenceMemory = []; // Last 3-round sequence that lost
  final Random _rnd = Random();
  int _pivotCount = 0; // Rounds for forced pivot
  
  // V13.1 Global Action Lock
  String? _lastLosingAction;
  int _lockRoundsRemaining = 0;

  // V14.0 Anti-Streak Fortress: Multi-Action Memory
  final Set<String> _streakLockedActions = {}; // ALL actions that failed during this streak
  int _streakLength = 0; // Current losing streak length

  // Mode Thresholds & Rules
  static const double _recoveryBetSize = 0.7; // 70%
  static const double _defenseBetSize = 0.4;  // 40%
  static const double _counterBetSize = 0.5;  // 50%

  V13Engine() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? mapStr = prefs.getString('v13_loss_map');
      if (mapStr != null) {
        _lossMap.addAll(Map<String, String>.from(jsonDecode(mapStr)));
      }
    } catch (e) {
      debugPrint('⚠️ V13 Load Error: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('v13_loss_map', jsonEncode(_lossMap));
    } catch (e) {
      debugPrint('⚠️ V13 Save Error: $e');
    }
  }
  void updateState(List<HistoryEntry> history, bool won, {String? lastAction}) {
    _updateMode(history, won, lastAction);
  }

  V13Decision processRound(List<HistoryEntry> history, {String? lastAction}) {
    String pattern = _buildPattern(history);
    V13GamePhase phase = _detectPhase(history);
    
    // Determine effective blocked action
    String? blocked = _lossMap[pattern];
    if (_lockRoundsRemaining > 0) {
      blocked = _lastLosingAction;
    }

    // V14.0: Build the full blocked set from streak memory
    Set<String> allBlocked = {..._streakLockedActions};
    if (blocked != null) allBlocked.add(blocked);

    // 2. Select Strategy & Action based on Mode
    String action = 'A';
    String strategy = 'Pattern';
    double confidence = 0.5;
    double adjustment = 1.0;
    BetRecommendation betRec = BetRecommendation.normal;
    String reason = 'Normal Protocol';

    switch (_currentMode) {
      case SystemMode.normal:
        action = _predictNormal(history, blocked);
        strategy = 'Pattern Intelligence';
        confidence = 0.8;
        adjustment = 1.0;
        betRec = BetRecommendation.normal;
        reason = 'Standard Operation';
        break;

      case SystemMode.recovery:
        action = _predictRecovery(history, blocked);
        strategy = 'Stabilization Pivot';
        confidence = 0.65;
        adjustment = _recoveryBetSize;
        betRec = BetRecommendation.x1_3;
        reason = 'Post-Loss Recovery (x1.3 Enabled)';
        break;

      case SystemMode.defense:
        action = _predictDefense(history, blocked);
        strategy = 'Capital Shield';
        confidence = 0.75;
        adjustment = _defenseBetSize;
        betRec = BetRecommendation.x1_5;
        reason = 'High Risk Defense (x1.5 Enabled)';
        break;

      case SystemMode.counter:
        action = _predictCounter(history, blocked);
        strategy = 'Entropy Counter';
        confidence = 0.6;
        adjustment = _counterBetSize;
        betRec = BetRecommendation.reset;
        reason = 'Pattern Break Execution (Force RESET)';
        break;
    }

    // --- V14.0 Anti-Streak Fortress ---
    if (_streakLength >= 5) {
      // DEEP STREAK: Force M4 RESET to cut losses
      action = _predictInverse(history, allBlocked);
      strategy = 'Anti-Streak Fortress (DEEP RESET)';
      confidence = 0.5;
      betRec = BetRecommendation.reset;
      reason = 'STREAK ${_streakLength}x: Force RESET & Inverse Pick';
    } else if (_streakLength >= 3) {
      // 3-4 STREAK: Force inverse pick (LEAST used action)
      action = _predictInverse(history, allBlocked);
      strategy = 'Anti-Streak Inverse';
      confidence = 0.55;
      reason = 'STREAK ${_streakLength}x: Inverse Logic Active';
    }

    // V14.0: Ensure the chosen action is NOT in the blocked set
    if (allBlocked.contains(action)) {
      List<String> safeOptions = ['A', 'B', 'C'].where((e) => !allBlocked.contains(e)).toList();
      if (safeOptions.isNotEmpty) {
        action = safeOptions[_rnd.nextInt(safeOptions.length)];
        strategy += ' (Forced Safe Pivot)';
      }
    }

    // --- V13.1 Chaos Shield & Pivot Logic ---
    double entropy = _calculateEntropy(history);
    if (entropy > 0.85 || _pivotCount > 0) {
       // Chaos Detected or Pivot Active
       action = _predictPivot(action, history, blocked);
       strategy = 'Chaos Shield Pivot';
       if (_pivotCount > 0) _pivotCount--;
    }

    // --- V13.1 Sequence Exclusion ---
    String currentSeq = _buildPattern(history);
    if (_recentSequenceMemory.contains(currentSeq)) {
        // We are entering a sequence that led to a loss. Pivot.
        List<String> alts = ['A', 'B', 'C'].where((e) => e != action && e != blocked).toList();
        if (alts.isNotEmpty) {
           action = alts[_rnd.nextInt(alts.length)];
           strategy = 'Sequence Memory Shield';
        }
    }

    // Zero-Skip Policy: Always return A, B, or C
    if (action == 'Skip') {
      action = ['A', 'B', 'C'].where((e) => e != blocked).first;
    }

    return V13Decision(
      mode: _currentMode,
      phase: phase,
      pattern: pattern,
      lastResult: history.isEmpty ? 'None' : (!history.last.isRed ? 'Win' : 'Loss'),
      lossStreak: _consecutiveLosses,
      blockedAction: _streakLockedActions.isNotEmpty 
          ? '${_streakLockedActions.join(",")} (Streak Lock x$_streakLength)' 
          : (_lockRoundsRemaining > 0 ? '$_lastLosingAction (Global Lock)' : blocked),
      strategyUsed: strategy,
      confidence: confidence,
      betAdjustment: adjustment,
      finalDecision: action,
      betRecommendation: betRec,
      reason: reason,
    );
  }

  // --- Internals ---

  void _updateMode(List<HistoryEntry> history, bool won, String? lastAction) {
    if (won) {
      _consecutiveLosses = 0;
      // Step back one level
      if (_lockRoundsRemaining > 0) _lockRoundsRemaining--;
      
      // V14.0: Clear ALL streak locks on win
      _streakLockedActions.clear();
      _streakLength = 0;
      _lastLosingAction = null;
      _lockRoundsRemaining = 0;
      debugPrint('[V14.0] 🏆 WIN: All streak locks cleared.');
      
      if (_currentMode == SystemMode.counter) {
        _currentMode = SystemMode.defense;
      } else if (_currentMode == SystemMode.defense) {
        _currentMode = SystemMode.recovery;
      } else {
        _currentMode = SystemMode.normal;
      }
    } else {
      _consecutiveLosses++;
      String pattern = _buildPattern(history);
      if (history.isNotEmpty) {
        // V14.1 Fix: Lock the ACTION we took, not the winning gem!
        String losingActionToLock = lastAction ?? history.last.value;

        // V13.1 Global Lock
        _lastLosingAction = losingActionToLock;
        _lockRoundsRemaining = 2 + _consecutiveLosses; // Escalating lock duration

        // V14.0: Add to streak memory
        _streakLockedActions.add(losingActionToLock);
        _streakLength = _consecutiveLosses;
        debugPrint('[V14.1] 🔒 Streak Lock: ${_streakLockedActions.toList()} (x$_streakLength)');

        // Map the loss to pattern
        _lossMap[pattern] = losingActionToLock;
        // Limit loss map size to prevent permanent rigidity over long sessions
        if (_lossMap.length > 12) {
          _lossMap.remove(_lossMap.keys.first);
        }
        _saveToPrefs();
      }

      // Transition forward
      if (_consecutiveLosses == 1) {
        _currentMode = SystemMode.recovery;
      } else if (_consecutiveLosses == 2) {
        _currentMode = SystemMode.defense;
        _pivotCount = 3; // Force pivot for 3 rounds
      } else if (_consecutiveLosses >= 3) {
        _currentMode = SystemMode.counter;
        _pivotCount = 5; // Force deep pivot
      }

      // V13.1 Record sequence memory on loss
      if (history.length >= 3) {
        String seq = _buildPattern(history);
        if (!_recentSequenceMemory.contains(seq)) {
          _recentSequenceMemory.add(seq);
          if (_recentSequenceMemory.length > 5) _recentSequenceMemory.removeAt(0);
        }
      }
    }
  }

  double _calculateEntropy(List<HistoryEntry> history) {
    if (history.length < 10) return 0.5;
    Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};
    var slice = history.sublist(history.length - 10);
    for (var h in slice) {
      counts[h.value] = (counts[h.value] ?? 0) + 1;
    }
    
    double entropy = 0;
    for (var count in counts.values) {
      if (count > 0) {
        double p = count / 10.0;
        entropy -= p * (log(p) / log(3));
      }
    }
    return entropy;
  }

  String _predictPivot(String originalAction, List<HistoryEntry> history, String? blocked) {
    // If original fails or we are in pivot, pick the 2nd best or inverse
    List<String> opts = ['A', 'B', 'C'];
    opts.remove(originalAction);
    if (blocked != null) opts.remove(blocked);
    return opts.isNotEmpty ? opts[_rnd.nextInt(opts.length)] : (originalAction == 'A' ? 'B' : 'A');
  }

  String _predictNormal(List<HistoryEntry> history, String? blocked) {
    if (history.isEmpty) return 'A';
    String last = history.last.value;
    return last == blocked ? (last == 'A' ? 'B' : 'A') : last;
  }

  String _predictRecovery(List<HistoryEntry> history, String? blocked) {
    // Avoid repeating last action + avoid blocked
    if (history.isEmpty) return 'B';
    String last = history.last.value;
    List<String> valid = ['A', 'B', 'C'];
    valid.remove(last);
    if (blocked != null) valid.remove(blocked);
    return valid.isNotEmpty ? valid[_rnd.nextInt(valid.length)] : 'C';
  }

  String _predictDefense(List<HistoryEntry> history, String? blocked) {
    // Highly selective statistically
    Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};
    for (var h in history.reversed.take(15)) {
      counts[h.value] = (counts[h.value] ?? 0) + 1;
    }
    var options = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    String best = options.first.key;
    if (best == blocked) best = options[1].key;
    return best;
  }

  String _predictCounter(List<HistoryEntry> history, String? blocked) {
    // Reverse predict or inject 20% randomness
    if (_rnd.nextDouble() < 0.2) return ['A', 'B', 'C'][_rnd.nextInt(3)];
    
    // Reverse Logic: Pick the LEAST frequent in last 5 rounds
    Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};
    for (var h in history.reversed.take(5)) {
      counts[h.value] = (counts[h.value] ?? 0) + 1;
    }
    var options = counts.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    String target = options.first.key;
    if (target == blocked) target = options[1].key;
    return target;
  }

  // V14.0: Pick the LEAST used action from recent history, avoiding ALL blocked actions
  String _predictInverse(List<HistoryEntry> history, Set<String> blocked) {
    Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};
    int lookback = min(10, history.length);
    if (lookback > 0) {
      for (var h in history.sublist(history.length - lookback)) {
        counts[h.value] = (counts[h.value] ?? 0) + 1;
      }
    }
    // Sort ascending (least used first)
    var options = counts.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    // Pick the least used that is NOT blocked
    for (var entry in options) {
      if (!blocked.contains(entry.key)) {
        return entry.key;
      }
    }
    // Fallback: If ALL are blocked (rare), pick the absolute least used
    return options.first.key;
  }

  String _buildPattern(List<HistoryEntry> history) {
    if (history.isEmpty) return 'START';
    int lookback = min(3, history.length);
    return history.sublist(history.length - lookback).map((e) => e.value).join();
  }

  V13GamePhase _detectPhase(List<HistoryEntry> history) {
    if (_consecutiveLosses >= 2) return V13GamePhase.trap;
    if (history.length < 5) return V13GamePhase.chaos;
    return V13GamePhase.trend;
  }
}
