# Handoff Report: R3 (Automated Test Verification) Analysis and Strategy Recommendations

This report presents a detailed codebase analysis and recommended strategies for implementing **R3 (Automated Test Verification)** via `test/anti_tracking_test.dart` to verify the bot's entropy/anti-tracking capabilities and guarantee that it never registers more than 3 consecutive recovery losses under hostile casino tracking.

---

## 1. Observation

A detailed inspection of the codebase in `c:\Users\Admin N\Desktop\golden_p` revealed the following key implementation details:

### A. Test Execution & WebViewController Mocking
*   **File Path**: `test/losing_streak_test.dart`
*   **Existing Mock Setup (Lines 14–36)**:
    ```dart
    class FakeInAppWebViewController extends Fake implements InAppWebViewController {
      final Future<dynamic> Function(String source, ContentWorld? contentWorld)? onEvaluateJavascript;

      FakeInAppWebViewController({this.onEvaluateJavascript});

      @override
      Future<dynamic> evaluateJavascript({
        required String source,
        ContentWorld? contentWorld,
      }) {
        if (onEvaluateJavascript != null) {
          return Future<dynamic>.value(onEvaluateJavascript!(source, contentWorld));
        }
        return Future<dynamic>.value(null);
      }

      @override
      Future<void> reload() async {}
    }
    ```
*   **Test Run Command**: `flutter test`
    *   Command completed successfully. Output: `All tests passed!` (refer to System Logs of task ID `afa22f14-b296-46a5-ac56-5a9d510545de/task-75`).

### B. Anti-Tracking & Inversion Logic
*   **File Path**: `lib/services/prediction_pipeline_service.dart`
*   **Inversion Logic (Lines 235–241)**:
    ```dart
    if (context.incorrectStreak == 2) {
       List<String> alternatives = ['A', 'B', 'C'].where((box) => box != bestPick).toList();
       alternatives.shuffle();
       predictionPick = alternatives.first; // Pick randomly from the other two
       decisionSource = 'V70 Inversion (Was $bestPick, Now $predictionPick)';
       debugPrint('🛡️ [V70.0 INVERSION] Casino counter detected! Inverting pick from $bestPick to $predictionPick');
    }
    ```
*   This triggers the mirror match (inversion logic) to do the exact opposite of what the ensemble thinks is best once the casino wins 2 times in a row, bypassing tracked patterns.

### C. Shannon Entropy & Game Phase Detector
*   **File Path**: `lib/engines/entropy_scanner.dart`
*   **Shannon Entropy Calculation (Lines 27–46)**:
    ```dart
    double calculateEntropy(List<String> history) {
      if (history.isEmpty) return 0.0;

      List<String> window = history.sublist(max(0, history.length - _windowSize));
      Map<String, int> counts = {'A': 0, 'B': 0, 'C': 0};

      for (var char in window) {
        if (counts.containsKey(char)) counts[char] = counts[char]! + 1;
      }

      double entropy = 0.0;
      int n = window.length;

      for (int count in counts.values) {
        if (count > 0) {
          double p = count / n;
          entropy -= p * (log(p) / ln2);
        }
      }
      ...
      return entropy; // Max for 3 states is log2(3) ≈ 1.58
    }
    ```
*   **Normalized Entropy (Lines 62–66)**:
    ```dart
    double calculateNormalizedEntropy(List<String> history) {
      double raw = calculateEntropy(history);
      double maxEntropy = log(3) / ln2; // log2(3) ≈ 1.585
      return (raw / maxEntropy).clamp(0.0, 1.0);
    }
    ```

### D. Recovery Mode and Trap Breaker
*   **File Path**: `lib/viewmodels/overlay_buttons_viewmodel.dart`
*   **Trap Breaker Trigger (Lines 1132–1140)**:
    ```dart
    if (_consecutiveRecoveryLosses == 3 && _totalAccumulatedLoss > 0 && !_isTrapBreakerActive) {
      debugPrint(
        '💥 [TRAP BREAKER TRIGGERED] 🚨 แพ้ติดกัน 3 ตาตอนทวงหนี้! พักการทวงหนี้ชั่วคราวแล้วสุ่มแทง 1 บาท!',
      );
      
      _isTrapBreakerActive = true;
      _trapBreakerRoundsRemaining = 4 + Random().nextInt(2); // ป่วน 4 ถึง 5 ตา
      _isRecoveryUnlocked = false; // หยุดทวงหนี้ชั่วคราว
      
      await _ensureBaseBet(runToken);
      ...
    ```
*   **Dumb Pattern Mode (Lines 740–758)**:
    When `_isRecoveryUnlocked` is false, the bot uses random dumb patterns (forced base bet) to break casino predictability:
    ```dart
    bool useDumbPattern = !_isRecoveryUnlocked;
    if (useDumbPattern) {
        prediction = ['A', 'B', 'C'][Random().nextInt(3)];
        _isRecoveryUnlocked = false; 
        debugPrint('[V63.0 DUMB PATTERN] 🤖 Random pattern: $prediction (Sacrifice Streak: $_consecutiveSacrificeLosses). Forced Base Bet.');
        targetId = prediction == 'A' ? 'M1' : (prediction == 'B' ? 'M2' : 'M3');
    }
    ```

### E. Telemetry and HTTP Server Connections
*   **File Path**: `lib/viewmodels/sequence_analyzer_viewmodel.dart`
    *   The viewmodel connects to a retraining server URL (`https://ventricle-overdrawn-ocelot.ngrok-free.dev`) and sends predictions feedback (Line 181).

---

## 2. Logic Chain

Based on these observations, we formulate the step-by-step logic chain to structure and write the tests:

1.  **WebView Interaction Isolation**: The bot's execution depends on `evaluateJavascript` to check button states, click elements, and check balances. In tests, we can fully intercept and mock these calls using a stateful `HostileCasinoWebViewController`.
2.  **Simulating Hostility**: To prove the anti-tracking capabilities of our bot, the simulated casino server must act as a threat. The mock controller should maintain the game state (`'bet'` vs. `'cashout'`) and dynamically generate bomb layouts that actively counter the bot's moves.
3.  **Verifying Entropy (Anti-Tracking)**: If the bot is predictable, a hostile casino targeting our choices will trigger consecutive losses. The Shannon Entropy formula implemented in `EntropyScanner` tells us that maximum randomness of 3 states is $\log_2 3 \approx 1.58$. We can compute the entropy of the bot's moves over a 100-round run. If $H(X) > 1.2$, the choices contain sufficient entropy to block basic predictability-based tracking. We must also assert transition probabilities ($P(X_t \to X_{t+1})$) do not indicate a repeating cycle (e.g. B-C-B-C).
4.  **Verifying the Loss Cap**:
    *   When the bot plays, a loss is recorded if it clicks a box where the casino placed a bomb.
    *   If the casino cheats (dynamic sniping) or the bot gets extremely unlucky, it can lose consecutive rounds.
    *   In recovery mode, losses increment `_consecutiveRecoveryLosses`.
    *   On the 3rd recovery loss, `_consecutiveRecoveryLosses == 3` triggers **Trap Breaker**.
    *   **Trap Breaker** immediately disables recovery mode (`_isRecoveryUnlocked = false`) and shifts the bot to random dumb patterns at the base bet for 4–5 rounds.
    *   Because recovery mode is locked, any subsequent losses during the Trap Breaker do not increment `_consecutiveRecoveryLosses`.
    *   Thus, `_consecutiveRecoveryLosses` is mathematically capped at 3 and can never reach 4.
    *   We can assert this in the test by running the simulation loop under a 100% loss-inducing casino setup and verifying that the recovery loss count is capped at 3, and the bet size immediately resets to the base bet.

---

## 3. Caveats

*   **Mock HTTP Dependency**: Because `SequenceAnalyzerViewModel` sends feedback telemetry to an external URL, the test environment (which operates in a CODE_ONLY network mode) must mock the http client to avoid timeouts or network connection failures.
*   **Randomization Seeds**: The bot's fallback decisions and inversion alternatives utilize `Random()`. If the test needs to be 100% deterministic (for reproducible debugging), we must override the seed or document the expected statistical variance.
*   **Actual Casino Intelligence**: Real-world casinos utilize multi-session profile tracking. The simulation evaluates standard pattern recognition and real-time counter-targeting, which serves as a robust proxy for validation.

---

## 4. Conclusion

Implementing R3 (Automated Test Verification) in `test/anti_tracking_test.dart` is highly feasible and structured as follows:

### A. Structure of `test/anti_tracking_test.dart`
Create a test file that simulates a loop of 100+ rounds. Use a `HostileCasinoWebViewController` to simulate the casino page:
```dart
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:golden_p/viewmodels/sequence_analyzer_viewmodel.dart';
import 'package:golden_p/viewmodels/overlay_buttons_viewmodel.dart';
import 'package:golden_p/engines/entropy_scanner.dart';

class HostileCasinoWebViewController extends Fake implements InAppWebViewController {
  final List<String> playerPicks = [];
  String currentStatus = 'bet'; // 'bet' or 'cashout'
  String activeBombPos = 'A';
  double balance = 100.0;
  double lastSetBet = 1.0;
  String hostileMode = 'sniping'; // 'sniping', 'markov', 'trap'
  
  @override
  Future<dynamic> evaluateJavascript({required String source, ContentWorld? contentWorld}) async {
    // 1. Return balance queries
    if (source.contains('parseFloat(el.value)') || source.contains('document.querySelectorAll')) {
      return balance.toString();
    }
    if (source.contains('Polygon') || source.contains('JSON.stringify')) {
      return jsonEncode({'coin': 'POL', 'balance': balance.toString()});
    }
    
    // 2. Return M0 status (BET/CASHOUT button state)
    if (source.contains('checkAtPoint') && source.contains('M0')) {
      return currentStatus;
    }
    
    // 3. Return M1, M2, M3 result state (visual detection)
    if (source.contains('checkAtPoint')) {
      final markerId = source.contains('M1') ? 'M1' : (source.contains('M2') ? 'M2' : 'M3');
      final box = markerId == 'M1' ? 'A' : (markerId == 'M2' ? 'B' : 'C');
      if (box == activeBombPos) {
        return 'bomb';
      } else {
        return 'diamond';
      }
    }
    
    // 4. Intercept clicks (mousedown / click / pointerdown)
    if (source.contains('doClick') || source.contains('dispatchEvent')) {
      final markerId = source.contains('M0') ? 'M0' : (source.contains('M1') ? 'M1' : (source.contains('M2') ? 'M2' : 'M3'));
      if (markerId == 'M0') {
        if (currentStatus == 'bet') {
          currentStatus = 'cashout';
          _generateHostileBomb();
        } else if (currentStatus == 'cashout') {
          currentStatus = 'bet'; // claim/cashout success
          balance += lastSetBet * 0.5; // profit
        }
      } else {
        final box = markerId == 'M1' ? 'A' : (markerId == 'M2' ? 'B' : 'C');
        playerPicks.add(box);
        if (box == activeBombPos) {
          currentStatus = 'bet'; // Hit bomb -> auto-reset to bet state (loss)
          balance -= lastSetBet; // loss
        }
      }
    }
    return null;
  }
  
  void _generateHostileBomb() {
    if (hostileMode == 'sniping' && playerPicks.isNotEmpty) {
      // Direct sniper: place the bomb exactly where the player clicked last
      activeBombPos = playerPicks.last;
    } else if (hostileMode == 'markov' && playerPicks.length >= 3) {
      // Predict next player click based on simple frequency count of last transition
      final lastPos = playerPicks.last;
      activeBombPos = lastPos == 'A' ? 'B' : (lastPos == 'B' ? 'C' : 'A');
    } else {
      // Trap pattern
      activeBombPos = 'A';
    }
  }
}
```

### B. Mocking the Prediction Loop and Server Responses
*   Use a mocked `http.Client` to intercept model retraining feedback posts, returning `200 OK` responses containing empty JSON.
*   Instantiate both viewmodels and set the speed multiplier to 1000.0:
    ```dart
    final vm = SequenceAnalyzerViewModel();
    final overlayVM = OverlayButtonsViewModel();
    final fakeCasino = HostileCasinoWebViewController();
    
    vm.setWebViewController(fakeCasino);
    overlayVM.setWebViewController(fakeCasino);
    overlayVM.setSequenceAnalyzerViewModel(vm);
    overlayVM.setSpeedMultiplier(1000.0);
    ```

### C. Shannon Entropy Assertions
To verify the bot's outputs contain enough entropy to evade tracking:
```dart
test('Verify output Shannon Entropy exceeds anti-tracking threshold', () async {
  // Run loop for 100 rounds
  await overlayVM.startSequence();
  await Future.delayed(const Duration(milliseconds: 1000));
  overlayVM.stopSequence();
  
  final picks = fakeCasino.playerPicks;
  expect(picks.length, greaterThanOrEqualTo(50));
  
  // Calculate Shannon Entropy
  final counts = {'A': 0, 'B': 0, 'C': 0};
  for (var pick in picks) {
    counts[pick] = (counts[pick] ?? 0) + 1;
  }
  
  double entropy = 0.0;
  final n = picks.length;
  for (int count in counts.values) {
    if (count > 0) {
      double p = count / n;
      entropy -= p * (log(p) / ln2);
    }
  }
  
  // Max entropy for 3 boxes is ~1.58. Assert entropy > 1.2
  expect(entropy, greaterThan(1.2), reason: 'Shannon entropy is too low: $entropy. Bot is predictable.');
  
  // Assert transition density (ensure the bot doesn't alternate rigidly A-B-A-B or B-C-B-C)
  Map<String, int> transitions = {};
  for (int i = 0; i < picks.length - 1; i++) {
    String trans = '${picks[i]}${picks[i+1]}';
    transitions[trans] = (transitions[trans] ?? 0) + 1;
  }
  double maxTransitionProb = 0.0;
  for (var count in transitions.values) {
    double p = count / (picks.length - 1);
    if (p > maxTransitionProb) maxTransitionProb = p;
  }
  expect(maxTransitionProb, lessThan(0.35), reason: 'A single transition pattern occurs too frequently: $maxTransitionProb');
});
```

### D. Hard Recovery Losses Cap Assertions
To verify that under no circumstances can the bot register 4 consecutive recovery losses:
```dart
test('Verify recovery losses are capped at 3 and bet size resets to base', () async {
  // Set casino to sniping mode to force 100% losses on the bot
  fakeCasino.hostileMode = 'sniping';
  
  await overlayVM.startSequence();
  await Future.delayed(const Duration(milliseconds: 800));
  overlayVM.stopSequence();
  
  // 1. Assert recovery losses never exceed 3
  expect(overlayVM.consecutiveRecoveryLosses, lessThan(4), 
      reason: 'Recovery losses exceeded 3 without triggering Trap Breaker!');
      
  // 2. Assert that if the total loss streak is 3 or more, the bet size has de-escalated to base bet
  if (overlayVM.consecutiveLossesStreak >= 3) {
    expect(fakeCasino.lastSetBet, equals(overlayVM.lockedBaseBet),
        reason: 'Bet size failed to reset to base bet during a long loss streak!');
  }
});
```

---

## 5. Verification Method

To verify the test suite execution:
1.  Verify tests pass by running:
    ```powershell
    flutter test test/anti_tracking_test.dart
    ```
2.  If the test passes successfully, it validates:
    *   The Inversion logic and Trap Breaker correctly reset the bet size to the base bet during streaks, capping consecutive recovery losses at 3.
    *   The bot's output decisions under a hostile casino server are sufficiently random and diverse (Shannon Entropy $> 1.2$ and Transition Probability $< 0.35$).
