"""
═══════════════════════════════════════════════════════════════════════
Autonomous AI Feedback & Correction Loop — ระบบวิเคราะห์และแก้โค้ดอัตโนมัติ
═══════════════════════════════════════════════════════════════════════
ประกอบด้วย 3 คลาสหลัก:
  1. StateTracker    — อ่านจอ + ดักจับ Telemetry + เก็บ Log ตาต่อตา
  2. StrategyAnalyzer — วิเคราะห์จุดอ่อน (Loss Pattern + Ruin Analysis)
  3. CodeUpdater     — สร้างโค้ดกลยุทธ์ใหม่ + เขียนทับ + Build + Deploy

และ Main Loop ที่เชื่อมทั้ง 3 เข้าด้วยกันเป็น Zero-Touch Self-Healing Loop
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime
from collections import Counter

if sys.stdout.encoding != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8')

ADB_PATH = r"C:\LDPlayer\LDPlayer14\adb.exe"
DEVICE = "emulator-5554"

# ค้นหา GOLDEN_P_DIR อัตโนมัติ (รองรับรันจากทุก path)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(SCRIPT_DIR) == "scripts":
    BASE_DIR = os.path.dirname(SCRIPT_DIR)
else:
    BASE_DIR = SCRIPT_DIR
GOLDEN_P_DIR = os.path.join(BASE_DIR, "golden_p")
if not os.path.exists(os.path.join(GOLDEN_P_DIR, "pubspec.yaml")):
    GOLDEN_P_DIR = BASE_DIR

STATE_FILE = os.path.join(BASE_DIR, "watchdog_state.json")
REPORT_FILE = os.path.join(BASE_DIR, "incident_report.json")
ROUND_LOG_FILE = os.path.join(BASE_DIR, "round_log.jsonl")

# เพิ่ม path สำหรับ import engine_generator
sys.path.append(os.path.join(BASE_DIR, "scripts"))
sys.path.append(os.path.join(GOLDEN_P_DIR, "scripts"))

# ═══════════════════════════════════════════════════════════════════════
# คลาสที่ 1: StateTracker — อ่านจอ + ดักจับ Telemetry + เก็บ Log
# ═══════════════════════════════════════════════════════════════════════
class StateTracker:
    """
    ติดตามสถานะของเกมแบบเรียลไทม์ผ่าน ADB Logcat
    บันทึกข้อมูลตาต่อตาลง JSON Lines เพื่อให้ AI วิเคราะห์ต่อได้
    """
    def __init__(self):
        self.total_rounds = 0
        self.wins = 0
        self.losses = 0
        self.current_streak = 0       # จำนวนตาที่แพ้ติดต่อกันปัจจุบัน
        self.max_loss_streak = 0       # แพ้ติดมากที่สุดตั้งแต่เริ่ม
        self.current_balance = 0.0
        self.highest_balance = 0.0
        self.current_coin = "DOGE"
        self.recent_rounds = []        # เก็บข้อมูลตาล่าสุด 50 ตา
        self.mutation_count = 0
        self.is_mutating = False
        self.last_mutation_time = None

    @property
    def win_rate(self):
        """อัตราการชนะ (%)"""
        return (self.wins / self.total_rounds * 100.0) if self.total_rounds > 0 else 0.0

    @property
    def drawdown_pct(self):
        """เปอร์เซ็นต์ที่พอร์ตลดลงจากจุดสูงสุด"""
        if self.highest_balance > 0 and self.current_balance > 0:
            return max(0.0, ((self.highest_balance - self.current_balance) / self.highest_balance) * 100.0)
        return 0.0

    def record_round(self, prediction, actual_bomb, is_win, balance, bet_amount=0.0, strategy="APPI 7.0"):
        """
        บันทึกข้อมูล 1 ตาลง JSON Log
        โครงสร้าง: {round, timestamp, prediction, actual_bomb, is_win, balance, drawdown, streak, strategy}
        """
        self.total_rounds += 1
        if is_win:
            self.wins += 1
            self.current_streak = 0
        else:
            self.losses += 1
            self.current_streak += 1
            if self.current_streak > self.max_loss_streak:
                self.max_loss_streak = self.current_streak

        if balance > self.highest_balance:
            self.highest_balance = balance
        self.current_balance = balance

        # สร้าง JSON Log Entry
        log_entry = {
            "round": self.total_rounds,
            "timestamp": datetime.now().isoformat(),
            "prediction": prediction,
            "actual_bomb": actual_bomb,
            "is_win": is_win,
            "bet_amount": bet_amount,
            "balance_after": balance,
            "highest_balance": self.highest_balance,
            "drawdown_pct": round(self.drawdown_pct, 4),
            "current_streak": self.current_streak,
            "win_rate": round(self.win_rate, 2),
            "strategy_version": strategy
        }

        self.recent_rounds.append(log_entry)
        if len(self.recent_rounds) > 50:
            self.recent_rounds.pop(0)

        # Append ลง JSONL file (1 บรรทัด = 1 ตา)
        try:
            with open(ROUND_LOG_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(log_entry) + "\n")
        except Exception as e:
            print(f"[StateTracker] ⚠️ Log write error: {e}")

        return log_entry

    def save_state(self):
        """บันทึกสถานะรวมลง watchdog_state.json"""
        try:
            data = {
                "timestamp": datetime.now().isoformat(),
                "current_coin": self.current_coin,
                "current_balance": self.current_balance,
                "highest_balance": self.highest_balance,
                "drawdown_pct": round(self.drawdown_pct, 2),
                "total_rounds": self.total_rounds,
                "total_wins": self.wins,
                "total_losses": self.losses,
                "current_streak": self.current_streak,
                "max_loss_streak": self.max_loss_streak,
                "win_rate": round(self.win_rate, 2),
                "mutation_count": self.mutation_count,
                "last_mutation_time": self.last_mutation_time,
                "recent_rounds": self.recent_rounds[-10:]
            }
            with open(STATE_FILE, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception as e:
            print(f"[StateTracker] ⚠️ State save error: {e}")


# ═══════════════════════════════════════════════════════════════════════
# คลาสที่ 2: StrategyAnalyzer — วิเคราะห์จุดอ่อน
# ═══════════════════════════════════════════════════════════════════════
class StrategyAnalyzer:
    """
    วิเคราะห์ 2 ด้าน:
      A) Loss Pattern Analysis — ทำไมอัลกอริทึมทำนายพลาด?
      B) Ruin Analysis — ทำไมเงินหมด/พอร์ตยุบ?
    """
    def __init__(self, tracker: StateTracker):
        self.tracker = tracker

    def analyze_loss_pattern(self) -> dict:
        """
        วิเคราะห์แพทเทิร์นการแพ้ย้อนหลัง 50 ตา:
        - เสาไหนที่ระเบิดลงบ่อยที่สุด?
        - เสาไหนที่ AI ชอบทายแล้วพลาด?
        - มี streak ≥ 3 เกิดขึ้นกี่ครั้ง?
        - มีแพทเทิร์นซ้ำๆ ไหม (เช่น A-B-A-B)?
        """
        rounds = self.tracker.recent_rounds
        if len(rounds) < 5:
            return {"status": "insufficient_data", "detail": "ข้อมูลน้อยกว่า 5 ตา ยังวิเคราะห์ไม่ได้"}

        losses = [r for r in rounds if not r['is_win']]
        if len(losses) == 0:
            return {"status": "healthy", "detail": "ไม่พบการแพ้ใน 50 ตาล่าสุด"}

        # 1. หาเสาที่ระเบิดลงบ่อยที่สุด
        bomb_counts = Counter(r.get('actual_bomb', 'Unknown') for r in losses)
        most_bombed = bomb_counts.most_common(1)[0] if bomb_counts else ('N/A', 0)

        # 2. หาเสาที่ AI ทายแล้วพลาดบ่อยที่สุด
        wrong_pred_counts = Counter(r['prediction'] for r in losses)
        most_wrong = wrong_pred_counts.most_common(1)[0] if wrong_pred_counts else ('N/A', 0)

        # 3. นับจำนวนครั้งที่เกิด streak >= 3
        streak_3_plus = sum(1 for r in rounds if r.get('current_streak', 0) == 3)
        streak_4_plus = sum(1 for r in rounds if r.get('current_streak', 0) == 4)
        streak_5_plus = sum(1 for r in rounds if r.get('current_streak', 0) >= 5)

        # 4. ตรวจหา Pattern ซ้ำในระเบิด (เช่น A-B-A-B)
        bomb_seq = [r.get('actual_bomb', '') for r in losses[-10:]]
        has_alternating = False
        if len(bomb_seq) >= 4:
            for i in range(len(bomb_seq) - 3):
                if bomb_seq[i] == bomb_seq[i+2] and bomb_seq[i+1] == bomb_seq[i+3]:
                    has_alternating = True
                    break

        # 5. สรุปความรุนแรง
        severity = "healthy"
        if streak_5_plus > 0:
            severity = "critical"
        elif streak_4_plus > 0 or self.tracker.current_streak >= 3:
            severity = "warning"
        elif len(losses) / max(len(rounds), 1) > 0.45:
            severity = "degraded"

        result = {
            "status": severity,
            "total_losses_in_window": len(losses),
            "total_rounds_in_window": len(rounds),
            "loss_rate": round(len(losses) / max(len(rounds), 1) * 100, 1),
            "most_bombed_column": {"column": most_bombed[0], "count": most_bombed[1]},
            "most_wrong_prediction": {"column": most_wrong[0], "count": most_wrong[1]},
            "streak_3_plus_count": streak_3_plus,
            "streak_4_plus_count": streak_4_plus,
            "streak_5_plus_count": streak_5_plus,
            "has_alternating_pattern": has_alternating,
            "detail": self._generate_loss_diagnosis(severity, most_bombed, most_wrong, has_alternating)
        }
        return result

    def _generate_loss_diagnosis(self, severity, most_bombed, most_wrong, alternating) -> str:
        """สร้างคำวินิจฉัยเหตุผลที่แพ้ เป็นภาษาไทย"""
        msgs = []
        if most_bombed[1] > 5:
            msgs.append(f"ระเบิดลงที่เสา {most_bombed[0]} บ่อยมาก ({most_bombed[1]} ครั้ง)")
        if most_wrong[1] > 5:
            msgs.append(f"AI ทายเสา {most_wrong[0]} แล้วพลาดบ่อย ({most_wrong[1]} ครั้ง)")
        if alternating:
            msgs.append("พบแพทเทิร์นระเบิดสลับเสา (Alternating Pattern)")
        if severity == "critical":
            msgs.append("เกิด Streak 5+ ตา → ต้องเปลี่ยนสถาปัตยกรรมใหม่ทันที")
        return " | ".join(msgs) if msgs else "ปกติ"

    def analyze_ruin(self) -> dict:
        """
        วิเคราะห์ความเสี่ยงพอร์ตแตก (Ruin Analysis):
        - Drawdown เกิน 3%?
        - Bet Size ขยายเร็วเกินไปหรือไม่?
        - Recovery Strategy ทำให้หนี้สะสมเร็วไหม?
        """
        tracker = self.tracker
        if tracker.total_rounds < 10:
            return {"status": "healthy", "detail": "ข้อมูลน้อยเกินไปสำหรับ Ruin Analysis"}

        drawdown = tracker.drawdown_pct

        # วิเคราะห์ Bet Size ย้อนหลัง
        recent_bets = [r.get('bet_amount', 0.0) for r in tracker.recent_rounds if r.get('bet_amount', 0.0) > 0]
        avg_bet = sum(recent_bets) / max(len(recent_bets), 1)
        max_bet = max(recent_bets) if recent_bets else 0.0

        # ตรวจสอบว่า bet ใหญ่กว่าค่าเฉลี่ยกี่เท่า (บ่งบอก Martingale ที่รุนแรง)
        bet_explosion_ratio = max_bet / avg_bet if avg_bet > 0 else 1.0

        severity = "healthy"
        msgs = []

        if drawdown >= 5.0:
            severity = "critical"
            msgs.append(f"พอร์ตยุบ {drawdown:.2f}% จากจุดสูงสุด → กลยุทธ์ทวงเงินรุนแรงเกินไป")
        elif drawdown >= 3.0:
            severity = "warning"
            msgs.append(f"พอร์ตยุบ {drawdown:.2f}% → เข้าเขตเตือนภัย")

        if bet_explosion_ratio > 5.0:
            severity = "critical" if severity != "critical" else severity
            msgs.append(f"Bet ใหญ่สุดเกินค่าเฉลี่ย {bet_explosion_ratio:.1f} เท่า → Martingale อันตราย")

        return {
            "status": severity,
            "drawdown_pct": round(drawdown, 2),
            "avg_bet": avg_bet,
            "max_bet": max_bet,
            "bet_explosion_ratio": round(bet_explosion_ratio, 1),
            "detail": " | ".join(msgs) if msgs else "การเดินเงินอยู่ในเกณฑ์ปลอดภัย"
        }


# ═══════════════════════════════════════════════════════════════════════
# คลาสที่ 3: CodeUpdater — สร้างโค้ดใหม่ + เขียนทับ + Build + Deploy
# ═══════════════════════════════════════════════════════════════════════
class CodeUpdater:
    """
    รับผลวิเคราะห์จาก StrategyAnalyzer แล้ว:
    1. สร้างโค้ดกลยุทธ์ใหม่ (Engine Generator)
    2. เขียนทับไฟล์ Dart เดิม
    3. สั่ง flutter build apk --debug
    4. สั่ง adb install ลง LDPlayer
    5. รีสตาร์ทแอปให้เล่นต่อด้วยโค้ดใหม่ทันที
    """
    def __init__(self, target_engine_path: str):
        self.target_file = target_engine_path

    def generate_and_deploy(self, loss_report: dict, ruin_report: dict, mutation_id: int) -> bool:
        """
        กระบวนการเปลี่ยนโค้ดทั้งหมด: วิเคราะห์ → สร้างโค้ดใหม่ → Build → Deploy
        คืนค่า True ถ้าสำเร็จ, False ถ้าล้มเหลว
        """
        print(f"\n{'='*60}")
        print(f"[CodeUpdater] 🧬 Mutation #{mutation_id} Initiated")
        print(f"  Loss Report: {loss_report.get('detail', 'N/A')}")
        print(f"  Ruin Report: {ruin_report.get('detail', 'N/A')}")
        print(f"{'='*60}\n")

        # 1. บันทึก Incident Report
        try:
            incident = {
                "timestamp": datetime.now().isoformat(),
                "mutation_id": mutation_id,
                "loss_analysis": loss_report,
                "ruin_analysis": ruin_report,
            }
            with open(REPORT_FILE, "w", encoding="utf-8") as f:
                json.dump(incident, f, indent=2, ensure_ascii=False)
            print(f"[CodeUpdater] 📝 Incident Report บันทึกที่ {REPORT_FILE}")
        except Exception as e:
            print(f"[CodeUpdater] ⚠️ Report error: {e}")

        # 2. สร้างโค้ดใหม่จาก Engine Generator
        try:
            from engine_generator import synthesize_new_engine
            arch_name, new_dart_code = synthesize_new_engine(mutation_id)
            with open(self.target_file, "w", encoding="utf-8") as f:
                f.write(new_dart_code)
            print(f"[CodeUpdater] 🗑️ ลบโค้ดเดิมทิ้ง → เขียนสถาปัตยกรรมใหม่: {arch_name}")
        except Exception as e:
            print(f"[CodeUpdater] ⚠️ Engine Generator fallback: {e}")
            return False

        # 3. Build APK
        print("[CodeUpdater] 🛠️ กำลังคอมไพล์ APK ใหม่...")
        try:
            result = subprocess.run(
                ["flutter.bat", "build", "apk", "--debug"],
                cwd=GOLDEN_P_DIR,
                capture_output=True,
                text=True,
                shell=True,
                timeout=180
            )
            if result.returncode != 0:
                print(f"[CodeUpdater] ❌ Build ล้มเหลว: {result.stderr[:300]}")
                return False
            print("[CodeUpdater] ✅ Build สำเร็จ!")
        except subprocess.TimeoutExpired:
            print("[CodeUpdater] ❌ Build timeout (3 นาที)")
            return False

        # 4. Deploy ลง LDPlayer
        print("[CodeUpdater] 🚀 กำลังติดตั้ง APK ลง LDPlayer...")
        apk_path = os.path.join(GOLDEN_P_DIR, "build", "app", "outputs", "flutter-apk", "app-debug.apk")
        subprocess.run([ADB_PATH, "-s", DEVICE, "install", "-r", apk_path], capture_output=True)

        # 5. รีสตาร์ทแอป
        print("[CodeUpdater] 🔄 รีสตาร์ทแอป...")
        subprocess.run([ADB_PATH, "-s", DEVICE, "shell", "am", "force-stop", "com.example.golden_p"], capture_output=True)
        time.sleep(2)
        subprocess.run([ADB_PATH, "-s", DEVICE, "logcat", "-c"], capture_output=True)
        subprocess.run([ADB_PATH, "-s", DEVICE, "shell", "am", "start", "-n", "com.example.golden_p/.MainActivity"], capture_output=True)

        print(f"[CodeUpdater] 🎉 Mutation #{mutation_id} สำเร็จ! แอปเริ่มเล่นด้วยสมองใหม่แล้ว\n")
        return True


# ═══════════════════════════════════════════════════════════════════════
# Main Autonomous Loop — เชื่อมทุกอย่างเข้าด้วยกัน
# ═══════════════════════════════════════════════════════════════════════
class AutonomousLoop:
    """
    วงจรหลัก: อ่าน Logcat สดๆ → วิเคราะห์ → ตัดสินใจ → เปลี่ยนโค้ดเมื่อจำเป็น
    ไม่มี "หยุดบอท" มีแต่ "เปลี่ยนสมองบอท"
    """
    def __init__(self):
        self.tracker = StateTracker()
        self.analyzer = StrategyAnalyzer(self.tracker)
        engine_path = os.path.join(GOLDEN_P_DIR, "lib", "engines", "omni_matrix_engine.dart")
        self.updater = CodeUpdater(engine_path)

    def _should_mutate(self) -> tuple:
        """
        ตรวจสอบว่าควรเปลี่ยนโค้ดหรือยัง
        เงื่อนไข:
          - Drawdown ≥ 3% (เสียเงินมากเกินไป)
          - Loss Streak ≥ 3 (แพ้ติดกันเยอะ จะไม่รอถึง 5)
        คืนค่า: (should_mutate: bool, reason: str)
        """
        if self.tracker.is_mutating:
            return (False, "กำลังเปลี่ยนโค้ดอยู่")

        # เช็ค Loss Streak
        if self.tracker.current_streak >= 3:
            return (True, f"🚨 Loss Streak = {self.tracker.current_streak} (≥ 3)")

        # เช็ค Drawdown
        if self.tracker.drawdown_pct >= 3.0:
            return (True, f"🚨 Drawdown = {self.tracker.drawdown_pct:.2f}% (≥ 3%)")

        return (False, "ปกติ")

    def _perform_mutation(self, reason: str):
        """ทำการวิเคราะห์และเปลี่ยนโค้ดกลยุทธ์"""
        self.tracker.is_mutating = True
        self.tracker.mutation_count += 1
        self.tracker.last_mutation_time = datetime.now().isoformat()
        self.tracker.save_state()

        print(f"\n[AUTONOMOUS] 🚨 TRIGGER: {reason}")

        # วิเคราะห์จุดอ่อน
        loss_report = self.analyzer.analyze_loss_pattern()
        ruin_report = self.analyzer.analyze_ruin()

        print(f"[AUTONOMOUS] 📊 Loss Analysis: {loss_report['status']} — {loss_report.get('detail', '')}")
        print(f"[AUTONOMOUS] 💰 Ruin Analysis: {ruin_report['status']} — {ruin_report.get('detail', '')}")

        # สร้างโค้ดใหม่และ Deploy
        success = self.updater.generate_and_deploy(loss_report, ruin_report, self.tracker.mutation_count)

        if success:
            self.tracker.current_streak = 0
            self.tracker.highest_balance = self.tracker.current_balance  # Reset baseline correctly
            # Clear history to prevent instant re-triggering
            self.tracker.recent_rounds.clear() 
            self.tracker.save_state()
            time.sleep(10)  # Cooldown หลัง deploy

        self.tracker.is_mutating = False
        self.tracker.save_state()

    def run(self):
        """Main Loop: อ่าน Logcat สดๆ ไม่หยุดจนกว่าจะถูก Kill"""
        print(f"[AUTONOMOUS LOOP] 🚀 เริ่มการเฝ้าระวัง {DEVICE} | Engine: {self.updater.target_file}")
        print(f"[AUTONOMOUS LOOP] 📁 Flutter Root: {GOLDEN_P_DIR}")

        while True:
            try:
                cmd = [ADB_PATH, "-s", DEVICE, "logcat", "-v", "time"]
                proc = subprocess.Popen(
                    cmd, 
                    stdout=subprocess.PIPE, 
                    stderr=subprocess.STDOUT, 
                    text=True, 
                    bufsize=1, 
                    encoding="utf-8", 
                    errors="replace"
                )

                for line in iter(proc.stdout.readline, ''):
                    line_str = line.strip()
                    
                    if not line_str:
                        continue

                # ═══ ดักจับ Telemetry JSON จากแอป ═══
                if "[AUTONOMOUS_FEEDBACK]" in line_str:
                    try:
                        json_part = line_str.split("[AUTONOMOUS_FEEDBACK]", 1)[1].strip()
                        telemetry = json.loads(json_part)
                        is_win = telemetry.get("is_win", False)
                        prediction = telemetry.get("prediction", "?")
                        actual = telemetry.get("actual", "?")
                        balance = telemetry.get("balance", self.tracker.current_balance)
                        bet = telemetry.get("bet_amount", 0.0)

                        # บันทึกตานี้ลง Log
                        self.tracker.record_round(prediction, actual, is_win, balance, bet)
                        self.tracker.save_state()

                        # ตรวจสอบว่าควร Mutate หรือยัง
                        should, reason = self._should_mutate()
                        if should:
                            self._perform_mutation(reason)
                    except Exception:
                        pass

                # ═══ ดักจับ BalanceTracker ═══
                elif "[BalanceTracker]" in line_str:
                    try:
                        if "Success:" in line_str:
                            parts = line_str.split("Success:", 1)[1].split("(")
                            coin_bal = parts[0].strip().split()
                            if len(coin_bal) >= 2:
                                self.tracker.current_coin = coin_bal[0]
                                self.tracker.current_balance = float(coin_bal[1])
                            if "Highest:" in line_str:
                                high_val = line_str.split("Highest:", 1)[1].strip()
                                self.tracker.highest_balance = float(high_val)
                            self.tracker.save_state()

                            # เช็ค Drawdown Trigger
                            should, reason = self._should_mutate()
                            if should:
                                self._perform_mutation(reason)
                    except Exception:
                        pass

                # ═══ ดักจับ WIN/LOSS จาก OmniMatrix ═══
                elif "[OMNI-MATRIX 2.0]" in line_str or "[APPI 7.0]" in line_str:
                    try:
                        if "WIN recorded" in line_str:
                            self.tracker.wins += 1
                            self.tracker.total_rounds += 1
                            self.tracker.current_streak = 0
                            self.tracker.save_state()
                        elif "LOSS recorded" in line_str:
                            self.tracker.losses += 1
                            self.tracker.total_rounds += 1
                            self.tracker.current_streak += 1
                            if self.tracker.current_streak > self.tracker.max_loss_streak:
                                self.tracker.max_loss_streak = self.tracker.current_streak

                            # บันทึกลง recent_rounds สำหรับ Analyzer
                            bomb_info = "?"
                            if "Bomb at:" in line_str:
                                bomb_info = line_str.split("Bomb at:", 1)[1].split(".")[0].strip()
                            pred_info = "?"
                            if "Column" in line_str:
                                pred_info = line_str.split("Column", 1)[1].split(".")[0].strip()

                            self.tracker.recent_rounds.append({
                                "round": self.tracker.total_rounds,
                                "timestamp": datetime.now().isoformat(),
                                "prediction": pred_info,
                                "actual_bomb": bomb_info,
                                "is_win": False,
                                "current_streak": self.tracker.current_streak,
                            })
                            if len(self.tracker.recent_rounds) > 50:
                                self.tracker.recent_rounds.pop(0)

                            self.tracker.save_state()

                            # ตรวจสอบ Mutation Trigger
                            should, reason = self._should_mutate()
                            if should:
                                self._perform_mutation(reason)
                    except Exception:
                        pass

            except KeyboardInterrupt:
                print("[AUTONOMOUS LOOP] หยุดโดยผู้ใช้")
                break
            except Exception as err:
                print(f"[AUTONOMOUS LOOP] ❌ Exception: {err}")
                time.sleep(5)
                continue


# ═══════════════════════════════════════════════════════════════════════
if __name__ == "__main__":
    loop = AutonomousLoop()
    loop.run()
