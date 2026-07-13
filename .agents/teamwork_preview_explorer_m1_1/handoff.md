# Handoff Report

## 1. Observation
1. In `lib/viewmodels/overlay_buttons_viewmodel.dart` lines 1886–1892:
   ```dart
   // V100.0: Restore 10% cap to allow actual recovery to succeed
   double maxCap = balance * 0.10; 

   if (requiredBet > maxCap) {
      debugPrint('[V100.0 SMART CAP] 🚨 Bet exceeds 10% cap. Reducing from ${requiredBet.toStringAsFixed(2)} to ${maxCap.toStringAsFixed(2)}');
      requiredBet = maxCap;
   }
   ```
2. In `lib/engines/provably_fair_engine.dart` lines 18–23:
   ```dart
   /// Rotates the seed pair completely. Simulates "Changing the Seed"
   void rotateSeed() {
     _serverSeed = _generateRandomHex(64); // 256-bit random server seed
     _clientSeed = _generateRandomHex(24); // Random client seed
     _nonce = 0;
   }
   ```
3. In `lib/viewmodels/overlay_buttons_viewmodel.dart` lines 681–687:
   ```dart
      // V18 Shadow Hunter: Emergency Reset Check
      if (_sequenceAnalyzerViewModel.isEmergencyResetRequired &&
          _lowestObservedBet != null) {
        debugPrint("🕵️ [V18 EMERGENCY] Hunt detected! Resetting bet to base.");
   ```
4. The test execution of `flutter test` failed with:
   ```
   00:51 +7 -2: C:/Users/Admin N/Desktop/golden_p/test/anti_tracking_test.dart: Anti-Tracking and Strict Circuit Breaker Tests Verify bot outputs contain enough entropy to evade tracking [E]
     Expected: a value greater than or equal to <50>
       Actual: <0>
        Which: is not a value greater than or equal to <50>
     Expected to run at least 50 rounds
   ```
5. In `test/anti_tracking_test.dart` lines 275–286:
   ```dart
      await vm.updateServerUrl('');
      await overlayVM.initialize();
      overlayVM.setSpeedMultiplier(1000.0);
      overlayVM.setSpeedMultiplier(1000.0);

      // Set unique positions to distinguish buttons
      overlayVM.buttons.firstWhere((b) => b.id == 'M0').position = const Offset(10, 10);
      overlayVM.buttons.firstWhere((b) => b.id == 'M1').position = const Offset(100, 100);
      overlayVM.buttons.firstWhere((b) => b.id == 'M2').position = const Offset(200, 200);
      overlayVM.buttons.firstWhere((b) => b.id == 'M3').position = const Offset(300, 300);

      // Run autoplay prediction loop
      await overlayVM.startSequence();
   ```

## 2. Logic Chain
1. **Local Provably Fair Disconnect**: Observation 2 shows that `ProvablyFairEngine` generates client and server seeds randomly and locally. Since these seeds have no correlation with the casino's actual server seeds, the predictions act as pseudo-random picks.
2. **Negative Expected Value (EV)**: Because the picks are pseudo-random, the bot has a mathematical win rate of $2/3$ (66.67%) on a single-tier row. Given the 1.42x payout, the expected return is $0.6667 \times 1.42 = 0.9467$, representing a $-5.33\%$ house edge. Therefore, the bot is guaranteed to lose balance in the long run.
3. **Bankruptcy via Martingale Escalation & Balance Cap Trap**: Observation 1 shows that if the required recovery bet exceeds 10% of the balance, it is capped. When capped, a single win can no longer recover the accumulated debt. The bot enters a state where it must win multiple capped bets in a row to recover, which is statistically rare, causing a slow bleed of the remaining balance until bankruptcy.
4. **Test Suite Bug**: In Observation 5, the tests call `overlayVM.initialize()`, which loads `_isSmartMode` from shared preferences. Since the mock preferences are empty, it defaults to `false`. The tests call `startSequence()` but never set `_isSmartMode` to `true`. This causes the loop to run `_executeSequence` instead of `_executeSmartFlow`. Since `_sequenceSteps` is empty, the custom sequence loop runs indefinitely doing nothing, resulting in 0 rounds played (Observation 4).

## 3. Caveats
- We did not connect to a live casino backend or inspect the live casino's seed generation code; we assume standard provably fair hashing based on standard documentation.
- We did not attempt to fix the test setup bugs as our current task is read-only exploration and analysis.

## 4. Conclusion
The bot uses a sophisticated multi-engine ensemble (with LSTM retraining on a Flask server) to generate predictions and implements a defensive recovery state machine with Ghost Betting and Ghost Sniper win requirements. However, it is mathematically vulnerable to bankruptcy because its predictions are pseudo-random (negative EV), leading to exponential debt growth and eventual balance capping, which prevents recovery. Additionally, the existing tests are currently failing due to a setup bug where smart mode is not enabled during initialization.

## 5. Verification Method
1. Run the test command `flutter test` from the project root directory.
2. Verify that `Verify bot outputs contain enough entropy to evade tracking` and `R2: Strict 3-Loss Hard Limit / Circuit Breaker reload and halt` fail.
3. To verify the test setup bug, modify `test/anti_tracking_test.dart` and `test/losing_streak_test.dart` to call `overlayVM.toggleSmartMode();` immediately after `overlayVM.initialize();`, and run `flutter test` again (note: some tests might still fail if the circuit breaker is not fully implemented in the main branch, but the round count will be > 0 instead of 0).
