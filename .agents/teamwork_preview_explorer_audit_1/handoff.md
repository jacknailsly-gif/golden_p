# Handoff Report — Codebase Audit on Losing Streaks and Safety Vulnerabilities

## 1. Observation
We conducted a read-only codebase audit of specific files:
- `lib/services/prediction_pipeline_service.dart`
- `lib/viewmodels/sequence_analyzer_viewmodel.dart`
- `lib/viewmodels/overlay_buttons_viewmodel.dart`

Direct observations from the code:
- **Inversion Logic Trap**: In `lib/services/prediction_pipeline_service.dart` (lines 235–241), we observed:
  ```dart
  if (context.incorrectStreak >= 2) {
     List<String> alternatives = ['A', 'B', 'C'].where((box) => box != bestPick).toList();
     alternatives.shuffle();
     predictionPick = alternatives.first; // Pick randomly from the other two
     decisionSource = 'V70 Inversion (Was $bestPick, Now $predictionPick)';
     debugPrint('🛡️ [V70.0 INVERSION] Casino counter detected! Inverting pick from $bestPick to $predictionPick');
  }
  ```
- **Dead Variable `_predictionMode`**: In `lib/viewmodels/sequence_analyzer_viewmodel.dart`, the variable `_predictionMode` is declared on lines 193–194:
  ```dart
  String _predictionMode = 'copy_user'; // 'copy_user' or 'ai_model'
  String get predictionMode => _predictionMode;
  ```
  It is toggled in the result evaluation block on lines 1147–1159:
  ```dart
  if (_predictionMode == 'copy_user') {
    _predictionMode = 'ai_model';
    debugPrint('[SWITCH] Mode switched to: ai_model (Copy User was wrong)');
  } else if (_predictionMode == 'ai_model' && _incorrectStreak >= 2) {
    _predictionMode = 'copy_user';
    debugPrint('[SWITCH] Mode switched to: copy_user (AI wrong 2x, panic reset)');
  }
  ```
  However, it is never read or referenced during the decision-making logic inside `_generateHybridResponse()` or `_finalizePrediction()`.
- **Disabled Hard Stop-Loss Fallback**: In `lib/viewmodels/overlay_buttons_viewmodel.dart` (lines 1148–1155):
  ```dart
  } else if (_consecutiveRecoveryLosses >= 5 && _recoveryMode != 1) {
     // 💥 Fallback Hard Stop in case Trap Breaker fails or we lost 5 heavy bets!
     debugPrint('[HARD STOP-LOSS] 🚨 แพ้ทวงหนี้ติดกัน 5 ตา! ล้างหนี้ทิ้งทั้งหมดเพื่อเซฟพอร์ตทันที!');
     _clearAllDebt();
     _isRecoveryUnlocked = false;
     await _ensureBaseBet(runToken);
     isSafetyValveActive = true;
  }
  ```
- **Trap Breaker Recovery Escalation**: In `lib/viewmodels/overlay_buttons_viewmodel.dart` (lines 1175–1196), in the loss-handling block:
  ```dart
  if (!isSafetyValveActive) {
    if (_consecutiveLossesStreak == 2 && _recoveryMode != 1) {
       ...
    } else {
       debugPrint('[V22.0] ⚡ Immediate Recovery Triggered after loss.');
       _recoveryWinsRequired = 0;
       _isRecoveryUnlocked = true;
    }
  }
  ```
  This triggers `_isRecoveryUnlocked = true` on any loss during Trap Breaker mode (when it is not the initial safety valve trigger round), escalating the bet amount to recovery sizes while the prediction logic is still randomly shuffling boxes.

---

## 2. Logic Chain
- **Inversion Logic Trap**:
  1. The bot enters a losing streak of `incorrectStreak >= 2`.
  2. The inversion logic is activated. Instead of using `bestPick` from the ensemble, the bot shuffles the other two options and picks one.
  3. If the ensemble's `bestPick` is correct, the inverted pick is guaranteed to be incorrect.
  4. This guarantees a loss, which keeps the streak `>= 2` (incremented to 3).
  5. The bot remains locked in the inversion loop, rejecting correct consensus picks and losing indefinitely.
- **Dead Variable `_predictionMode`**:
  1. `_predictionMode` changes on losses and resets.
  2. In `_generateHybridResponse()`, `_primaryPrediction` is directly set to the return value of `_predictionPipeline.generateHybridResponse(...)`.
  3. No conditional branch checks `_predictionMode` before setting the primary prediction.
  4. Thus, `_predictionMode` is a dead variable and does not affect the prediction outputs.
- **Disabled Hard Stop-Loss**:
  1. `_recoveryMode` defaults to `1` (line 357).
  2. The condition for the hard stop-loss is `_consecutiveRecoveryLosses >= 5 && _recoveryMode != 1`.
  3. Under default settings, `_recoveryMode != 1` is false, completely disabling the stop-loss check.
  4. The bot will keep accumulating debt and doubling down indefinitely on consecutive losses.
- **Trap Breaker Recovery Escalation**:
  1. When Trap Breaker mode is active, the bot plays random sacrifice bets at the base bet size.
  2. If a loss occurs in Trap Breaker mode, it is added to `_debtChunks` and `_isRecoveryUnlocked` is set to `true`.
  3. On the next round, because `_isRecoveryUnlocked` is true, the bot escalates the bet size using `_executeFractionalRecovery` but still picks a box randomly because `_isTrapBreakerActive` is true.
  4. This risks large losses on random plays.

---

## 3. Caveats
- We did not execute live betting simulation runs on the WebView because it requires real-time network interaction which is restricted in `CODE_ONLY` network mode.
- We assumed the default recovery mode of operation is indeed `_recoveryMode = 1` as initialized in the constructor/fields.

---

## 4. Conclusion
Four critical logical flaws exist in the prediction and recovery flows:
1. Inversion logic gets locked into a perpetual losing loop when the ensemble is correct but the streak is `>= 2`.
2. `_predictionMode` does not alter output predictions, failing to implement the user-copying fallback.
3. The hard stop-loss is bypassed under default conditions, risking portfolio ruin.
4. Trap Breaker mode triggers recovery escalation inappropriately, risking heavy losses on random choices.

Actionable fixes have been documented in `analysis.md` and precise changes are detailed in `proposed_fixes.patch`.

---

## 5. Verification Method
- Execute the unit tests located in `test/losing_streak_test.dart` to simulate these edge cases:
  - Command: `flutter test test/losing_streak_test.dart`
- Verify code edits visually to confirm that:
  - Inversion logic only triggers on `context.incorrectStreak == 2`.
  - `_predictionMode == 'copy_user'` overrides the prediction generation.
  - The fallback hard stop-loss condition does not check `_recoveryMode != 1`.
  - Recovery is locked (`_isRecoveryUnlocked = false`) while `_isTrapBreakerActive == true`.
