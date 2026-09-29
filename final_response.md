1. **Scope (G1)**
   - **Goal**: แก้ปัญหาบอททวงหนี้ติดๆ กันแบบไม่ยอมรอชิงจังหวะ (Quota=2) และแก้บัคเมื่อบอทแพ้ 3 ตาติดแล้วไม่ยอมเข้าสู่โหมดดูเชิง 3-5 ตาตามกฎ แต่กลับกระโดดไปทวงหนี้ทันที
   - **In-scope**: อัปเดต `lib/viewmodels/overlay_buttons_viewmodel.dart`
   - **Out-of-scope**: การปรับจูนค่าสัญญาณ OmniMatrix หรือกฎการเล่นอื่นๆ
   - **Unknowns**: ไม่มี

2. **Evidence**
   - `lib/viewmodels/overlay_buttons_viewmodel.dart:108` - ตัวแปร `maxRecoveryStepsThisCycle` สามารถสุ่มได้ถึง 2 ทำให้บอทยิงทวงไม้ซ้อนได้โดยไม่เว้นระยะ
   - `lib/viewmodels/overlay_buttons_viewmodel.dart:2310` - ใน `_detectVisualOutcome` การนับ `observationRoundsRemaining` ถูกหักลบและเช็คก่อนที่จะตรวจสอบ `consecutiveLossesStreak >= 3` พอค่าเวลาดูเชิงหมด มันเลยเด้งเข้า `RecoveryGate` ทันทีแม้ว่าควรจะต้องเข้าโหมดดูเชิงหลังแพ้ 3 ตา

3. **Repro output**
   - อาการตรงกับบันทึกการทวงหนี้ที่ผู้ใช้แนบมา:
     ```text
     USDT0.0707 0.00× -0.0707 Verify (ทวงหนี้ซ้อน)
     USDT0.0685 0.00× -0.0685 Verify (ทวงหนี้ไม้ก่อนหน้า)
     ```
     ยอดรวมติดลบและล้างพอร์ตทันทีโดยไม่มีการรอชิงจังหวะรอบที่ 8-12

4. **Diff**
   ```diff
   --- a/lib/viewmodels/overlay_buttons_viewmodel.dart
   +++ b/lib/viewmodels/overlay_buttons_viewmodel.dart
   @@ -107,17 +107,3 @@ class GameModeSessionState {
   -  int maxRecoveryStepsThisCycle = 2; // 🎯 โควตาสุ่มทวงหนี้ในรอบนี้ (1-3 ไม้)
   +  int maxRecoveryStepsThisCycle = 1;
   +  double savedScrollY = 0.0;
    
      int randomizeRecoveryQuota({int? fixedForTest}) {
   -    final int roll = Random().nextInt(100);
   -    int quota = roll < 50 ? 1 : (roll < 85 ? 2 : 3);
   -    maxRecoveryStepsThisCycle = quota;
   -    return maxRecoveryStepsThisCycle;
   +    maxRecoveryStepsThisCycle = 1;
   +    return 1;
      }
   @@ -2310,6 +2312,17 @@ class OverlayButtonsViewModel with ChangeNotifier {
   +          if (state.consecutiveLossesStreak >= 3) {
   +            // FORCE OBSERVATION IMMEDIATELY! Do not let it process observation decrement!
   +            state.recoveryStepInCycle = 0;
   +            state.isLossStreakBaseBetLocked = true;
   +            state.isCurrentlyRecoveryRound = false;
   +            final int obsRounds = 3 + Random().nextInt(3);
   +            state.observationRoundsRemaining = state.observationRoundsRemaining > obsRounds ? state.observationRoundsRemaining : obsRounds;
   +            state.currentRecoveryCycle = 2;
   +            transitionRecoveryState(mode, RecoveryState.observation, reason: 'Normal Base Bet lost 3 consecutive times -> FORCE Observation');
   +          }
   +
              if (state.observationRoundsRemaining > 0) {
                state.observationRoundsRemaining--;
   ```

5. **Verification output**
   ```text
   Running Gradle task 'assembleRelease'...
   Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 7812 bytes (99.5% reduction). 
   Built build\app\outputs\flutter-apk\app-release.apk (73.8MB)
   
   Performing Streamed Install
   Success
   Events injected: 1
   ```

6. **Counter-evidence**
   - 1) บอทอาจจะยังทวงติดกันได้ถ้ามีสถานะหลุดจากการรันข้ามคืนหรือโหมดหยุดชะงัก
     **วิธีพิสูจน์**: ต้องเปิด Logcat สังเกตการณ์ดูรอบ RECOVERY_GATE ว่ามันขึ้นทีละ 1 ไม้เสมอไหม และรอบถัดไปบังคับเข้าสู่การดูเชิง (Observation) เสมอหรือเปล่า
   - 2) อาจมีการค้างในหน้าจอโหมดการดูเชิง (Observation Lock) นานกว่า 5 ตา
     **วิธีพิสูจน์**: ตรวจสอบจำนวนตาหลังแพ้ติด 3 รอบ ว่าเมื่อถึงตาที่ 4 หรือ 5 สามารถหลุดกลับมาทวงหนี้ (Recovery) ได้หรือไม่

7. **Risks & next steps**
   - **ความเสี่ยง 1**: เมื่อบอทรอดูเชิงนานขึ้น อาจทำให้จำนวนรอบการเล่นรวมสูงขึ้น ซึ่งส่งผลต่อความถี่ในการเล่นรวมต่อวัน
   - **ความเสี่ยง 2**: ฐานการเดิมพันเล็กๆ (Base Bet) จะสะสมผลแพ้เรื่อยๆ หากอัตราการชนะใน 8-12 รอบนั้นยังอยู่ในเกณฑ์ที่ต่ำ
   - **Next Steps**: แนะนำให้ตั้งยอดเงินน้อยๆ รันบอททดสอบสถานการณ์จริงแบบ 24 ชั่วโมง แล้วเก็บ `adb logcat` ไว้เพื่อดูกราฟ Drawdown อีกครั้งครับ
