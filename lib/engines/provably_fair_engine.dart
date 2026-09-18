import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// V103: Smart Prediction Engine with Bomb History Evasion
/// 
/// Instead of pure random HMAC prediction, this engine:
/// 1. Tracks recent bomb positions to identify patterns
/// 2. Avoids columns that were recently bombs (frequency analysis)
/// 3. Uses HMAC-SHA256 as a tiebreaker only when frequencies are equal
/// 4. Applies anti-consecutive-loss shield (never pick same losing column twice)
class ProvablyFairEngine {
  static final ProvablyFairEngine _instance = ProvablyFairEngine._internal();
  factory ProvablyFairEngine() => _instance;
  ProvablyFairEngine._internal() {
    rotateSeed();
  }

  late String _serverSeed;
  late String _clientSeed;
  int _nonce = 0;

  final Random _random = Random();

  // V103: Bomb History Tracking
  final List<String> _bombHistory = []; // Last N bomb positions (A, B, C)
  final List<String> _lossHistory = []; // Last N positions we lost on
  
  // V124: Dynamic Parameters
  int maxBombHistory = 12;
  int maxLossHistory = 3;
  double hmacThreshold = 0.15;

  /// Record where the bomb actually was after a round
  void recordBomb(String bombPosition) {
    if (bombPosition != 'A' && bombPosition != 'B' && bombPosition != 'C') return;
    _bombHistory.add(bombPosition);
    if (_bombHistory.length > maxBombHistory) _bombHistory.removeAt(0);
  }

  /// Record our losing pick (what we chose when we lost)
  void recordLoss(String lostPosition) {
    if (lostPosition != 'A' && lostPosition != 'B' && lostPosition != 'C') return;
    _lossHistory.add(lostPosition);
    if (_lossHistory.length > maxLossHistory) _lossHistory.removeAt(0);
  }

  /// Clear loss history on win (streak broken)
  void recordWin() {
    _lossHistory.clear();
  }

  /// Rotates the seed pair completely. Simulates "Changing the Seed"
  void rotateSeed() {
    _serverSeed = _generateRandomHex(64); // 256-bit random server seed
    _clientSeed = _generateRandomHex(24); // Random client seed
    _nonce = 0;
  }

  /// V103: Smart prediction with bomb evasion
  /// 
  /// Strategy:
  /// 1. Count bomb frequency for each column in recent history
  /// 2. Rank columns from safest (fewest bombs) to most dangerous
  /// 3. Apply anti-consecutive-loss filter
  /// 4. Use HMAC as tiebreaker between equally safe columns
  String getNextPrediction() {
    final candidates = ['A', 'B', 'C'];
    
    // Step 1: Calculate bomb frequency scores (lower = safer)
    Map<String, double> dangerScore = {'A': 0.0, 'B': 0.0, 'C': 0.0};
    
    if (_bombHistory.isNotEmpty) {
      // Weight recent bombs more heavily (exponential decay)
      for (int i = 0; i < _bombHistory.length; i++) {
        double weight = (i + 1) / _bombHistory.length; // More recent = higher weight
        dangerScore[_bombHistory[i]] = dangerScore[_bombHistory[i]]! + weight;
      }
      
      // Normalize to 0-1 range
      double maxDanger = dangerScore.values.reduce(max);
      if (maxDanger > 0) {
        for (var key in dangerScore.keys) {
          dangerScore[key] = dangerScore[key]! / maxDanger;
        }
      }
    }
    
    // Step 2: HARD RULE — Never pick the column with highest bomb frequency
    // This is the #1 most important rule: if A has been the bomb 100% of the time, NEVER pick A.
    List<String> safeCandidates = List.from(candidates);
    
    if (_bombHistory.length >= 3) {
      // Find the most dangerous column
      String mostDangerous = candidates.first;
      double highestDanger = -1.0;
      for (var c in candidates) {
        if (dangerScore[c]! > highestDanger) {
          highestDanger = dangerScore[c]!;
          mostDangerous = c;
        }
      }
      // If a column is significantly more dangerous than the others, blacklist it
      double secondHighest = dangerScore.values.where((v) => v < highestDanger).fold(0.0, max);
      if (highestDanger - secondHighest > 0.15) {
        safeCandidates.remove(mostDangerous);
      }
    }

    // 🛡️ Step 2.5: 4-Pillar Streak Suppression Engine (กดการแพ้ติดกันไม่ให้เกิน 3-4 ตา)
    // Pillar A: Tri-State Anti-Clustering Rotation (ถ้าแพ้ 2 ตาติดบน 2 เสาที่ต่างกัน ให้บังคับเลือกเสาที่ 3 ทันที)
    if (_lossHistory.length >= 2) {
      final recentLosses = _lossHistory.sublist(_lossHistory.length - 2).toSet();
      if (recentLosses.length >= 2) {
        final remaining3rd = candidates.where((c) => !recentLosses.contains(c)).toList();
        if (remaining3rd.isNotEmpty) {
          safeCandidates = remaining3rd;
          debugPrint('[PROVABLY FAIR] 🛡️ Tri-State Rotation: Eliminating lost columns $recentLosses -> Forced to $safeCandidates');
        }
      }
    }

    // Pillar B: Hard Anti-Consecutive Loss Filter (ห้ามแทงเสาที่เพิ่งแพ้ในตาล่าสุดซ้ำ 100%)
    if (_lossHistory.isNotEmpty && safeCandidates.length > 1) {
      String lastLostColumn = _lossHistory.last;
      if (safeCandidates.contains(lastLostColumn)) {
        safeCandidates.remove(lastLostColumn);
        debugPrint('[PROVABLY FAIR] 🚫 Hard Loss Filter: Blacklisted $lastLostColumn. Remaining candidates: $safeCandidates');
      }
    }
    
    // Step 3: Among safe candidates, pick the one with lowest danger score
    safeCandidates.sort((a, b) => dangerScore[a]!.compareTo(dangerScore[b]!));
    
    // Step 4: If top candidates have similar danger scores, use HMAC as tiebreaker
    String bestPick;
    
    if (safeCandidates.length >= 2 && 
        (dangerScore[safeCandidates[0]]! - dangerScore[safeCandidates[1]]!).abs() < hmacThreshold) {
      // Scores are close — use HMAC to break the tie unpredictably
      bestPick = _hmacTiebreaker(safeCandidates);
    } else {
      bestPick = safeCandidates.first; // Clear safest choice
    }
    
    _nonce++;
    return bestPick;
  }

  /// Use HMAC-SHA256 to pick unpredictably among tied candidates
  String _hmacTiebreaker(List<String> candidates) {
    String message = '$_clientSeed:$_nonce:0';
    
    var key = utf8.encode(_serverSeed);
    var bytes = utf8.encode(message);

    var hmacSha256 = Hmac(sha256, key);
    var digest = hmacSha256.convert(bytes);
    
    List<int> hashBytes = digest.bytes;
    int chunk = (hashBytes[0] << 24) | (hashBytes[1] << 16) | (hashBytes[2] << 8) | hashBytes[3];
    double roll = (chunk >>> 0) / 4294967296.0;

    int index = (roll * candidates.length).floor();
    if (index >= candidates.length) index = candidates.length - 1;
    
    return candidates[index];
  }

  String _generateRandomHex(int length) {
    const chars = '0123456789abcdef';
    return Iterable.generate(length, (_) => chars[_random.nextInt(chars.length)]).join();
  }
}
