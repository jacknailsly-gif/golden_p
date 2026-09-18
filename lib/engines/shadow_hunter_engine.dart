import 'dart:math';
import 'package:flutter/foundation.dart';

/// 🧠 V18 'Shadow Hunter' Engine
/// Focuses on 'Server Fingerprinting' and 'Proactive Deception'.
class ShadowHunterEngine {
  final Map<String, int> _bombAtClickPosCount = {'A': 0, 'B': 0, 'C': 0};
  final List<String> _lastClickHistory = [];
  final List<String> _lastBombHistory = [];
  
  int _huntStreak = 0;
  double _huntCertainty = 0.0;
  
  void recordRound({
    required String? clickedPos,
    required String? bombPos,
    required bool won,
    double entropy = 0.0,
  }) {
    if (clickedPos == null || bombPos == null) return;

    _lastClickHistory.add(clickedPos);
    _lastBombHistory.add(bombPos);

    if (clickedPos == bombPos) {
      _bombAtClickPosCount[clickedPos] = (_bombAtClickPosCount[clickedPos] ?? 0) + 1;
      _huntStreak++;
      debugPrint("🕵️ [V18.1 FLASH] Hunt detected! (Streak: $_huntStreak)");
    } else {
      _huntStreak = 0;
    }

    // V18.1: Shorter window for faster reaction (last 5 rounds)
    if (_lastClickHistory.length > 5) {
      _lastClickHistory.removeAt(0);
      _lastBombHistory.removeAt(0);
    }

    int matchesInLast5 = 0;
    for (int i = 0; i < _lastClickHistory.length; i++) {
      if (i < _lastBombHistory.length && _lastClickHistory[i] == _lastBombHistory[i]) {
        matchesInLast5++;
      }
    }

    // High sensitivity formula
    double baseCertainty = (_huntStreak * 0.45) + (matchesInLast5 / 5.0);
    
    _huntCertainty = baseCertainty.clamp(0.0, 1.0);
  }

  /// V18.1: Immediate Deception for fast-moving traps
  String getFlashDeceptiveChoice(Map<String, double> aiScores, List<String> forbidden, int streak) {
    var candidates = aiScores.entries.toList()
      ..removeWhere((e) => forbidden.contains(e.key))
      ..sort((a, b) => b.value.compareTo(a.value));

    if (candidates.isEmpty) return 'A';

    // V29.2 Confidence Guard: If top candidate has a significant lead (>2.0 score difference), don't override.
    if (candidates.length >= 2 && (candidates[0].value - candidates[1].value) > 2.0) {
      debugPrint("🕵️ [V18.1 FLASH] Confidence Guard: Top choice has significant lead. Skipping Shadow Move.");
      return candidates.first.key;
    }

    // If we've lost even once, and there's ANY hint of a hunt, jump to Shadow Move
    if (streak >= 1 && (_huntCertainty > 0.3 || _huntStreak >= 1)) {
       // Pick the MIDDLE option — not the top (predictable) nor the bottom (often bomb position)
       debugPrint("🕵️ [V18.1 FLASH] Executing Proactive Shadow Move (Certainty: $_huntCertainty)");
       int midIndex = candidates.length ~/ 2;
       // Safety: if only 2 candidates, use Random 50/50 to avoid being predictable
       if (candidates.length <= 2) {
         return candidates[Random().nextInt(candidates.length)].key;
       }
       return candidates[midIndex].key; 
    }

    return candidates.first.key;
  }

  /// Returns a 'Deceptive' move that defies standard AI patterns.
  String getDeceptiveChoice(Map<String, double> aiScores, List<String> forbidden) {
    var candidates = aiScores.entries.toList()
      ..removeWhere((e) => forbidden.contains(e.key))
      ..sort((a, b) => b.value.compareTo(a.value));

    if (candidates.isEmpty) return 'A';

    // V29.2 Confidence Guard: Skip deception if top choice is very strong
    if (candidates.length >= 2 && (candidates[0].value - candidates[1].value) > 2.5) {
       return candidates.first.key;
    }

    // If certainty is extreme (>0.8), the server expects us to pick the 'Best' (Rank 1).
    // So we pick Rank 2 or 3 (The Shadow Move).
    if (_huntCertainty > 0.8 && candidates.length >= 2) {
      debugPrint("🕵️ [SHADOW HUNTER] CRITICAL HUNT: Executing Rank 2 Shadow Move.");
      return candidates[1].key;
    }

    // If certainty is high (>0.5), we pick based on 'Inverse Probability'.
    if (_huntCertainty > 0.5 && candidates.length >= 2) {
      // Pick the candidate that has NOT been targeted recently.
      String leastTargeted = candidates.first.key;
      int minTargetCount = _bombAtClickPosCount[leastTargeted] ?? 0;

      for (var c in candidates) {
        int count = _bombAtClickPosCount[c.key] ?? 0;
        if (count < minTargetCount) {
          minTargetCount = count;
          leastTargeted = c.key;
        }
      }
      debugPrint("🕵️ [SHADOW HUNTER] HUNT DETECTED: Picking Least-Targeted: $leastTargeted");
      return leastTargeted;
    }

    // Standard behavior: Return top choice
    return candidates.first.key;
  }

  bool isEmergencyResetRequired() {
    // If we have 3 consecutive targeted bombs, the server is in 'Lock-On' mode.
    // We should reset the bet to stop giving them money.
    return _huntStreak >= 3;
  }

  double get huntCertainty => _huntCertainty;
}
