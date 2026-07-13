# Vulnerability Audit and Fix Strategy Report

## 1. Inversion Logic perpetual trap in `PredictionPipelineService.generateHybridResponse`
### Observation
In `PredictionPipelineService.generateHybridResponse`, the inversion logic is activated when the casino wins 2 or more times in a row (`context.incorrectStreak >= 2`).
```dart
    if (context.incorrectStreak >= 2) {
       List<String> alternatives = ['A', 'B', 'C'].where((box) => box != bestPick).toList();
       alternatives.shuffle();
       predictionPick = alternatives.first; // Pick randomly from the other two
       decisionSource = 'V70 Inversion (Was $bestPick, Now $predictionPick)';
       debugPrint('🛡️ [V70.0 INVERSION] Casino counter detected! Inverting pick from $bestPick to $predictionPick');
    }
```
If the ensemble's `bestPick` is correct, the inversion logic forces the system to pick one of the other two incorrect boxes, resulting in a loss. This loss increments the `incorrectStreak` (e.g., to 3). In the next round, the streak is still `>= 2`, so the inversion logic runs again, rejecting the correct `bestPick` again, leading to another loss, and so on.
This creates a perpetual trap: once the incorrect streak is 2 or more, even if the ensemble is completely correct, the bot is guaranteed to keep losing indefinitely.

### Fix Strategy
Restrict the inversion logic to a narrow streak range (specifically only at `context.incorrectStreak == 2` or `context.incorrectStreak == 3`), or only on specific streak increments.
Changing the condition to:
```dart
    if (context.incorrectStreak == 2) {
```
This ensures that if the inverted pick is wrong and we lose (increasing the streak to 3), the bot will stop inverting in the next round and follow the ensemble's consensus `bestPick`. If the ensemble is correct, the bot wins, and the streak resets to 0.

---

## 2. Dead state variable `_predictionMode` in `SequenceAnalyzerViewModel`
### Observation
In `SequenceAnalyzerViewModel`, the state variable `_predictionMode` (initialized to `'copy_user'`) is toggled between `'copy_user'` and `'ai_model'` in the round outcomes handler:
```dart
        if (_predictionMode == 'copy_user') {
          _predictionMode = 'ai_model';
          debugPrint('[SWITCH] Mode switched to: ai_model (Copy User was wrong)');
        } else if (_predictionMode == 'ai_model' && _incorrectStreak >= 2) {
          _predictionMode = 'copy_user';
          debugPrint('[SWITCH] Mode switched to: copy_user (AI wrong 2x, panic reset)');
        }
```
However, `_predictionMode` is never checked or used in prediction generation. In `_generateHybridResponse()`, the prediction is fetched from `_predictionPipeline.generateHybridResponse(...)` regardless of `_predictionMode`.
This means `_predictionMode` is a dead variable and does not affect the actual prediction outputs. The logs indicating a mode switch are purely cosmetic.

### Fix Strategy
Integrate `_predictionMode` into the prediction generation method `_generateHybridResponse()` in `SequenceAnalyzerViewModel`:
```dart
    if (_predictionMode == 'copy_user' && _inputs.isNotEmpty) {
      // Copy the user's last selected position, or last gem value if selectedPos is null
      _primaryPrediction = _inputs.last.selectedPos ?? _inputs.last.value;
      _decisionSource = 'Copy User (Mode)';
    } else {
      // Otherwise, query the hybrid ensemble pipeline as normal
      final PredictionResult result = _predictionPipeline.generateHybridResponse(
        predictionContext,
        _baseRateScores,
        _recentSuccessScores,
        _patternAvoidanceScores,
        _counterMoveMemory,
        _decisionSequence,
      );
      _primaryPrediction = result.primaryPrediction;
      _decisionSource = result.decisionSource;
    }
```

---

## 3. Disabled hard stop-loss fallback in `OverlayButtonsViewModel` under `_recoveryMode == 1`
### Observation
In `OverlayButtonsViewModel._executeSmartFlow`, the fallback hard stop-loss check is written as:
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
Since `_recoveryMode` defaults to `1`, the condition `_recoveryMode != 1` evaluates to `false`. Consequently, the hard stop-loss is completely disabled under the default mode of operation. If the bot is in recovery mode 1 and enters a long losing streak, it will never clear the accumulated debt or reset to base bet, risking an account wipeout.

### Fix Strategy
Remove the `_recoveryMode != 1` restriction to enable the fallback hard stop-loss under all modes of operation:
```dart
          } else if (_consecutiveRecoveryLosses >= 5) {
             // 💥 Fallback Hard Stop in case Trap Breaker fails or we lost 5 heavy bets!
             debugPrint('[HARD STOP-LOSS] 🚨 แพ้ทวงหนี้ติดกัน 5 ตา! ล้างหนี้ทิ้งทั้งหมดเพื่อเซฟพอร์ตทันที!');
             _clearAllDebt();
             _isRecoveryUnlocked = false;
             await _ensureBaseBet(runToken);
             isSafetyValveActive = true;
          }
```

---

## 4. Immediate recovery escalation during Trap Breaker mode in `OverlayButtonsViewModel`
### Observation
When the bot is in Trap Breaker mode (`_isTrapBreakerActive` is `true`), it places random sacrifice bets at the base bet size.
If a loss occurs:
1. The loss is added to `_debtChunks` via `_addDebtChunk(currentBetStr)`.
2. Because the safety valve check (`isSafetyValveActive`) is only true on the triggering round, in subsequent rounds of Trap Breaker mode it evaluates to `false`.
3. The code then enters:
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
This unlocks recovery (`_isRecoveryUnlocked = true`).
In the next round, because `_isRecoveryUnlocked` is `true`, `_executeFractionalRecovery` is executed, raising the bet amount to a heavy recovery bet. However, because `_isTrapBreakerActive` is still `true`, the bot picks a box randomly, meaning a massive recovery bet is placed on a completely random box. If this heavy bet is lost, it adds a huge loss to the debt chunks, risking a fast wipeout.

### Fix Strategy
Prevent recovery from being unlocked and suppress any recovery bet escalation while Trap Breaker mode is active.
In the loss handling section:
```dart
          if (!isSafetyValveActive) {
            if (_isTrapBreakerActive) {
              // 🛡️ Safe-guard: Keep recovery locked and bet at base during Trap Breaker
              _isRecoveryUnlocked = false;
              _recoveryWinsRequired = 999;
              await _ensureBaseBet(runToken);
              debugPrint('[TRAP BREAKER LOSS] 🛡️ Lost during Trap Breaker. Recovery remains locked, bet remains at base.');
            } else if (_consecutiveLossesStreak == 2 && _recoveryMode != 1) {
               ...
```
Also, ensure the recovery check suppresses escalation during Trap Breaker:
```dart
          if (_isRecoveryUnlocked && !_isTrapBreakerActive) {
             // IMMEDIATE RECOVERY MODE
             ...
          } else {
             // DEFENSIVE MODE or Trap Breaker active
             await _ensureBaseBet(runToken);
          }
```

---

## 5. Unit Test Simulations (`test/losing_streak_test.dart`)
To verify these fixes and prove that the anti-loss mechanisms function correctly, we should write unit tests that simulate a sequence of consecutive losses.

### Mock/Setup requirements
- Create mock `InAppWebViewController` and `SequenceAnalyzerViewModel` classes.
- Construct `OverlayButtonsViewModel` and link it to the mock components.
- Stub `_getBetAmount()` and `_setBetAmount()` to trace bet changes.
- Stub visual outcome checks to return `'bet'` (loss) on demand.

### Test Cases to Implement
1. **Inversion Logic Recovery Test**:
   - Set up the prediction pipeline.
   - Simulate 2 losses (streak = 2). Check that the pick is inverted.
   - Simulate a 3rd round where the ensemble's bestPick is correct. Verify that since the streak is 3 (with the fix), inversion is bypassed, consensus is used, and the round is won, resetting the streak to 0.
2. **PredictionMode Active Execution Test**:
   - Verify that when `_predictionMode` is `'copy_user'`, the generated prediction copies the last round's user selection/outcome.
   - Verify that when `_predictionMode` switches to `'ai_model'`, it uses the ensemble scores.
3. **Hard Stop-Loss Fallback Test (Mode 1)**:
   - Configure `_recoveryMode = 1` (default).
   - Simulate 5 consecutive losses during recovery.
   - Verify that the hard stop-loss fallback is triggered: debt chunks are cleared (`_debtChunks.isEmpty`), recovery is locked (`_isRecoveryUnlocked` is false), and bet is reset to base.
4. **Trap Breaker Mode Recovery Lockdown Test**:
   - Trigger Trap Breaker mode (`_isTrapBreakerActive = true`).
   - Simulate a loss.
   - Verify that `_isRecoveryUnlocked` remains `false`, and the bet amount is NOT escalated.
