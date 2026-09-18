# รายงานการตรวจสอบโค้ด (Code Review) — โปรเจกต์ `golden_p`

วันที่ตรวจ: 16 กันยายน 2026
ขอบเขต: โปรเจกต์ Flutter ทั้งหมด (`lib/`, `test/`, `pubspec.yaml`, `analysis_options.yaml`)
ผู้ตรวจ: Sixth (Senior Software Engineer)

---

## 0. วิธีที่ใช้ตรวจสอบ (Evidence)

| ขั้นตอน | คำสั่ง / วิธี | ผลลัพธ์ |
|---|---|---|
| Static analysis | `flutter analyze lib` | **59 issues — 0 error** (เป็น warning/info ทั้งหมด) |
| Unit/Integration tests | `flutter test` | **89 passed, 11 skipped, 0 failed** |
| อ่านโค้ดจริง | อ่านครบทุกไฟล์หลัก (`overlay_buttons_viewmodel.dart` 2,968 บรรทัด, `sequence_analyzer_viewmodel.dart` 2,317 บรรทัด, engines, services, models, views) | — |
| ตรวจ dependency จริง | อ่าน source ของ `tflite_flutter-0.12.1` ใน pub cache | พบบั๊ก (ข้อ 3.1) |
| ตรวจ dead code | grep ทุก identifier ใน `lib/` + `test/` | พบ dead code จำนวนมาก (ข้อ 3.2) |

> หมายเหตุความโปร่งใส: ผมไม่ได้รันแอปบนอุปกรณ์จริงและไม่ได้ `flutter analyze test` — ข้อสรุปทั้งหมดมาจากการอ่านซอร์ส + static analysis + test run

---

## 1. สรุปผู้บริหาร (Executive Summary)

โปรเจกต์**คอมไพล์ผ่านและเทสต์ผ่านทั้งหมด** แต่คุณภาพเชิงตรรกะมีปัญหาหนักใน 5 เรื่องที่กระทบเงินจริงโดยตรง:

1. **ไม่มีระบบยืนยันตัวตนจริง** — `AuthService` เป็น mock รับทุกอีเมล/รหัสผ่าน และให้สิทธิ์ `admin` ทันที (ข้อ 2.1)
2. **ไม่มีเพดานความเสี่ยงตอนทวงหนี้** — เบททวงหนี้สามารถเดิมพันได้ **ถึง 100% ของยอดเงินในบัญชี** ⇒ ไม้เดียวล้างพอร์ตได้ (ข้อ 2.2)
3. **"3-Loss Circuit Breaker" ที่ระบุใน `PROJECT.md` ไม่มีอยู่จริง** — โค้ดไม่หยุดเล่น แต่รีเซ็ตสตรีคแล้วเล่นต่อ และ **เทสต์ที่พิสูจน์เรื่องนี้ถูกปิด (skip) ทั้งหมด** (ข้อ 2.3)
4. **บั๊กทางบัญชีหนี้** — `resetDebt()` ถูกล้างหนี้เมื่อ "ชนะ" แม้เบทถูกตัดเพดานจนทวงหนี้ไม่ครบ (ข้อ 2.4)
5. **ยอดเงินที่ใช้ตัดสินใจอาจเป็นค่าที่ระบบ "แต่งขึ้น" เอง** เมื่ออ่าน DOM ไม่ได้ ⇒ สร้าง/ลบ "หนี้ผี" ได้ (ข้อ 2.5)

นอกจากนี้ยังพบ **โค้ดที่คำนวณแล้วไม่ถูกใช้อีกเลย (dead code) ในระดับที่มากผิดปกติ** — ระบบ AI, ระบบความปลอดภัย และ state หลายสิบตัวถูกคำนวณทิ้ง ผลจริงคือ *การตัดสินใจเดิมพันสุดท้ายมาจากไม่กี่บรรทัด* ไม่ใช่จาก "AI 6 โมเดล" ตามที่เอกสารอ้าง

## 2. สถิติโปรเจกต์

- ไฟล์ Dart ใน `lib/`: 71 ไฟล์ | ใน `test/`: 17 ไฟล์
- ไฟล์ใหญ่ที่สุด: `overlay_buttons_viewmodel.dart` **2,968 บรรทัด**, `sequence_analyzer_viewmodel.dart` **2,317 บรรทัด**, `debt_reconciliation_test.dart` **>2,530 บรรทัด**
- `debugPrint()` จำนวน **253 จุด** (ไม่มี `print()` เปล่าเลย — ตรวจแล้ว)
- ไฟล์ที่ไม่มีโค้ด/ตายแล้ว: `sequence_analyzer_view_fixed.dart` (56 bytes), `floating_overlay_buttons.dart` (**2 bytes**)

---
## 3. ปัญหาระดับวิกฤต (Critical)

### 3.1 ไม่มีการยืนยันตัวตนจริง — ผู้ใช้ทุกคนได้สิทธิ์ `admin`

**ไฟล์:** `lib/services/auth_service.dart`

```dart
static Future<bool> login(String email, String password) async {
  // MOCK LOGIN FOR UI TESTING (Backend not yet active)
  await Future.delayed(const Duration(milliseconds: 800));
  if (email.isNotEmpty && password.isNotEmpty) {
    await _saveSession(email, 'mock_token_123', 'admin');   // ← ทุกคนเป็น admin
    return true;
  }
  return false;
}
```

- ทั้ง `login()` และ `register()` **ไม่มีการเรียก backend เลย** — รหัสผ่านอะไรก็ได้แม้แต่ `a`/`a`
- ผลลัพธ์คือ `currentUserRole == 'admin'` เสมอ
- `lib/views/profile_view.dart:131` ใช้ค่านี้เป็นประตูเปิดเมนูแอดมิน → **ทุกคนเข้าได้**
- `lib/views/admin_dashboard_view.dart` (602 บรรทัด) **ไม่มี role check ในตัวหน้าเลย** ใช้แค่ Bearer token จาก mock
- `lib/views/splash_view.dart:62` auto-login จาก `currentUserEmail != null` โดยไม่ตรวจ token
- token ถูกเก็บใน `SharedPreferences` (plaintext) ขณะที่ `lib/data/local/secure_storage_service.dart` (ใช้ `flutter_secure_storage`) **ถูกคอมเมนต์ทิ้งทั้งไฟล์** ทั้งที่ dependency ถูก declare ไว้ใน `pubspec.yaml`
- `baseUrl = 'http://127.0.0.1:3000/api/v1/auth'` → HTTP ธรรมดา + loopback (ใช้บนอุปกรณ์จริงไม่ได้ และถ้าใช้ได้จริงก็เท่ากับส่ง token แบบไม่เข้ารหัส)

**ผลกระทบ:** ระบบสิทธิ์ทั้งระบบไม่มีผล — ต้องแก้ก่อนปล่อยให้ผู้ใช้จริงใช้งาน

---

### 3.2 ไม่มีเพดานความเสี่ยงในเบททวงหนี้ — เดิมพันได้ถึง 100% ของยอดเงิน

**ไฟล์:** `lib/viewmodels/overlay_buttons_viewmodel.dart:2881-2968` (`_executeSymbioticRecovery`)

```dart
double targetProfit = debtToEscalate + surplusProfitMargin;
double requiredBet = targetProfit / pRate;      // 2930-2931

if (requiredBet < minRecoveryBet) requiredBet = minRecoveryBet;   // 2933-2935

// 🎯 คำสั่งผู้ใช้: "ทวงเต็ม 100%" (ปลดล็อก Bankroll Safety Cap 20% ออกแล้ว)
const double casinoHardLimit = 3000.0;                            // 2941
if (requiredBet > casinoHardLimit) requiredBet = casinoHardLimit; // 2942-2947

if (requiredBet < floorBet) requiredBet = floorBet;               // 2950-2952

if (currentBalance > 0.00000001 && requiredBet > currentBalance) {
  requiredBet = currentBalance;                                   // 2954-2956  ← เดิมพันได้ทั้งพอร์ต
}
```

- `pRate` = `0.42` (Towers) / `0.48` (Mines) ⇒ เบททวงหนี้ ≈ **2.1–2.4 เท่าของหนี้ที่ค้าง**
- เพดานสุดท้ายคือ **`currentBalance`** — คือเดิมพันทั้งหมดในบัญชีได้
- **`getOperationalRecoveryBudget()`** (บรรทัด 62-87) ซึ่งเป็นฟังก์ชันคำนวณงบความเสี่ยงอย่างระมัดระวัง **ไม่เคยถูกเรียกใช้เลย** (grep ยืนยัน: ปรากฏเฉพาะบรรทัดประกาศ `62`) เช่นเดียวกับ `emergencyCapitalFloor` (44, 63, 67) และ `profitCushion` (50, 66) ที่ถูกใช้แค่ภายในฟังก์ชันที่ตายแล้วนั้น
- คอมเมนต์ 2937-2938 ระบุเจตนาชัดเจนว่าปลดเพดาน 20% ออก

**ผลกระทบ:** แพ้ไม้ทวงหนี้เพียงไม้เดียว = เสียทั้งพอร์ต ระบบจึงไม่ใช่ "ทวงหนี้" แต่เป็นการทบต้นความเสี่ยงแบบไม่มีขีดจำกัด

---

### 3.3 "3-Loss Circuit Breaker" ไม่มีอยู่จริง — และเทสต์ที่พิสูจน์ถูกปิด

`PROJECT.md` ระบุ (milestone R2):
> "Instantly catches `_consecutiveLossesStreak >= 3`, reloads the WebView, sets UI advice/stop reasons, **and halts auto-play**."

โค้ดจริง — `overlay_buttons_viewmodel.dart:1962-1981`:
```dart
if (state.consecutiveLossesStreak >= 3) {
  final int obsRounds = 15 + Random().nextInt(6);
  state.observationRoundsRemaining = obsRounds;
  state.isLossStreakBaseBetLocked = true;
  state.consecutiveLossesStreak = 0;      // ← รีเซ็ตแล้วเล่นต่อ
  ...
  OmniMatrixEngine.instance.resetStreak(mode: mode);
  OmniMatrixEngine.instance.rotateSeed(mode: mode);
  await rotateWebClientSeed(mode: mode);
}
```
⇒ **ไม่มีการหยุด ไม่มีการ reload WebView** เพียงรีเซ็ตสตรีคแล้วไปโหมด Base Bet สังเกตการณ์ 15-20 ไม้ แล้วเล่นต่อ

**หลักฐานยืนยันจาก `flutter test`:** เทสต์ 11 รายการถูก skip โดย **10 รายการให้เหตุผลเดียวกัน**:

```
Skip: Outdated by 24/7 autonomous loop which does not halt on 3 losses
```

ได้แก่
| Test |
|---|
| `Verify Circuit Breaker triggers after 3 consecutive losses` |
| `R2: Strict 3-Loss Hard Limit / Circuit Breaker reload and halt` |
| `Verify 4x Base Bet Max Limit and 5% Cap under High Balance` |
| `Verify 5% Cap under Low Balance (Exposing bypass bug)` |
| `Hard Stop-Loss: triggers ... after 5 consecutive recovery losses` |
| `Trap Breaker Lockdown: loss during Trap Breaker does NOT unlock recovery` |
| `Inversion Logic: Triggers at streak == 2, does NOT trigger at streak == 3` |
| `predictionMode copy_user vs ai_model` |
| `predictionMode transition state machine` |
| `R1: Non-deterministic voting noise added to consensus scores` |

และระหว่างรันเทสต์พบ log `[SOVEREIGN STREAK LOCKDOWN] Streak: 18` ⇒ สตรีคในเอนจินโตเกิน 3 ได้จริง

**ผลกระทบ:** "hard stop" ที่ผู้ใช้เชื่อว่ามีอยู่ไม่มีจริง และเทสต์ที่เคยพิสูจน์เรื่องนี้ถูกปิดแทนที่จะแก้โค้ด

---

### 3.4 บั๊กบัญชีหนี้: ล้างหนี้เมื่อ "ชนะ" แม้ทวงหนี้ไม่ครบ

**ไฟล์:** `lib/viewmodels/overlay_buttons_viewmodel.dart:1805-1823`

```dart
if (wasRecoveryRound) {
  state.resetDebt();            // ← ล้างหนี้ทั้งก้อน เงื่อนไขเดียวคือ "เป็นไม้ทวงหนี้ และชนะ"
  state.consecutiveRecoveryLosses = 0;
  ...
}
```

แต่จำนวนเบทที่ใช้ทวงหนี้อาจ **ถูกตัดเพดาน** ที่จุดใดจุดหนึ่งต่อไปนี้ก่อนหน้า:
- `2954-2956` → `requiredBet = currentBalance` (ยอดเงินไม่พอทวง)
- `2942-2947` → `casinoHardLimit = 3000`
- `2933-2935` → `minRecoveryBet` floor

⇒ เมื่อเบทถูกตัดให้เล็กกว่าที่ควร กำไรที่ได้ย่อมไม่พอปิดหนี้ แต่โค้ดกลับ `resetDebt()` ทำให้ระบบ **คิดว่ากลับมาเท่าทุนแล้วทั้งที่ยังขาดทุน**

บั๊กเดียวกันในเส้นทางอื่น:
- `1723-1729` — `balanceAfterWin >= sessionMaxBalance` → `resetDebt()`
- `1261-1266` — `[ATH REACHED]` → `resetDebt()`
- `1245-1248` — ถ้าไม่มีหนี้ ให้ `sessionMaxBalance = settledBalance`

**แนะนำ:** เปลี่ยนเป็นหักตามกำไรจริงเท่านั้น (`subtractProfitFromDebt(actualProfit)`) และล้างหนี้เฉพาะเมื่อ `totalAccumulatedLoss <= 0` จริง

---

### 3.5 ยอดเงินอาจเป็นค่าที่ระบบ "แต่งขึ้น" เอง → สร้าง/ลบ "หนี้ผี"

**ไฟล์:** `lib/viewmodels/overlay_buttons_viewmodel.dart:2761-2838` (`_getBalanceDouble`)

เมื่ออ่าน DOM ไม่สำเร็จ ฟังก์ชันจะคืนค่าจาก cache ตามลำดับ:
```dart
if (state.lastSettledBalance > 0.00000001) return state.lastSettledBalance;
if (state.sessionStartBalance != null && ...) return state.sessionStartBalance!;
if (state.sessionMaxBalance > 0.00000001) return state.sessionMaxBalance;
return 0.0;
```

จากนั้น `_verifyAndSyncBalanceBeforeRound()` (1171-1283) ใช้ค่านั้นสร้างหนี้:
```dart
final double realDeficit = state.sessionMaxBalance - settledBalance;
if (realDeficit > 0.00000001) {
  if (state.consecutiveLossesStreak > 0) {
    if (realDeficit > state.totalAccumulatedLoss + 0.00000001) {
      final double deficitGap = ...;
      state.activeNewLoss += deficitGap;        // ← บวกหนี้จากผลต่างยอดเงิน
    }
  }
}
```

**ผลกระทบสองทาง:**
1. **สร้างหนี้ผี** — หาก DOM อ่านค่าเก่า (ยังไม่รวมเครดิตจากไม้ก่อน) ระบบจะตีความว่า "ขาดทุน" แล้วเพิ่มหนี้ → เข้าโหมดทวงหนี้ด้วยเบทใหญ่ (ซ้ำร้ายกับข้อ 3.2)
2. **ลบหนี้ผี** — เมื่อชนะแต่ DOM ยังไม่ขยับ (`balanceIncreased == false`) โค้ดใช้ `theoreticalProfit` มาหักหนี้ทันที (บรรทัด 1714-1715 และ 1730-1736) ⇒ หนี้อาจหายโดยไม่มีเงินเข้าจริง

---
