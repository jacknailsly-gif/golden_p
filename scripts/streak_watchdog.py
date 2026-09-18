import os
import sys
import subprocess
import time
import json
import re
from datetime import datetime

# Ensure UTF-8 output encoding for Windows consoles
if sys.stdout and hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if sys.stderr and hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

GOLDEN_P_DIR = r"C:\Users\Admin N\Desktop\Agents\golden_p\golden_p"
ADB_PATH = r"C:\LDPlayer\LDPlayer14\adb.exe"
DEVICE = "127.0.0.1:5555"
STATE_FILE = os.path.join(GOLDEN_P_DIR, "watchdog_state.json")

class StreakWatchdog:
    def __init__(self):
        self.total_rounds = 0
        self.total_wins = 0
        self.total_losses = 0
        self.current_streak = 0
        self.max_loss_streak = 0
        self.current_balance = 0.0
        self.current_coin = "UNKNOWN"
        self.highest_balance = 0.0
        self.recent_losses = []
        self.rebuild_count = 0
        self.last_rebuild_time = None
        self.is_rebuilding = False

    def save_state(self):
        state = {
            "timestamp": datetime.now().isoformat(),
            "current_coin": self.current_coin,
            "current_balance": self.current_balance,
            "highest_balance": self.highest_balance,
            "total_rounds": self.total_rounds,
            "total_wins": self.total_wins,
            "total_losses": self.total_losses,
            "current_streak": self.current_streak,
            "max_loss_streak": self.max_loss_streak,
            "win_rate": round((self.total_wins / self.total_rounds * 100) if self.total_rounds > 0 else 0.0, 2),
            "recent_losses": self.recent_losses[-10:],
            "rebuild_count": self.rebuild_count,
            "last_rebuild_time": self.last_rebuild_time,
            "is_rebuilding": self.is_rebuilding
        }
        try:
            with open(STATE_FILE, "w", encoding="utf-8") as f:
                json.dump(state, f, indent=2)
        except Exception as e:
            print(f"[WATCHDOG] Error saving state: {e}")

    def trigger_auto_fix_and_rebuild(self, reason):
        # Pure passive logging - DO NOT restart or reinstall the app automatically
        print(f"\n[WATCHDOG 📊 LOG ONLY] {reason}")
        self.save_state()

    def run(self):
        print(f"[WATCHDOG] Starting Real-time Loss Streak Watchdog on {DEVICE}...")
        while True:
            try:
                subprocess.run([ADB_PATH, "connect", DEVICE], capture_output=True)
                subprocess.run([ADB_PATH, "-s", DEVICE, "logcat", "-c"], capture_output=True)

                logcat_proc = subprocess.Popen(
                    [ADB_PATH, "-s", DEVICE, "logcat", "-v", "time"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1
                )

                print("[WATCHDOG] Streaming live logs... Ready to intercept 3-loss streaks!")

                for line in iter(logcat_proc.stdout.readline, ''):
                    if not line:
                        continue

                    # 1. Parse BalanceTracker
                    if "[BalanceTracker]" in line:
                        match = re.search(r'Success:\s+([A-Z]+)\s+([\d\.]+).*Highest:\s+([\d\.]+)', line)
                        if match:
                            self.current_coin = match.group(1)
                            self.current_balance = float(match.group(2))
                            self.highest_balance = float(match.group(3))
                            self.save_state()

                    # 2. Parse Win
                    if "WIN recorded" in line:
                        self.total_rounds += 1
                        self.total_wins += 1
                        self.current_streak = 0
                        print(f"[{datetime.now().strftime('%H:%M:%S')}] 🌟 WIN! Rounds: {self.total_rounds} | Streak: 0 | Bal: {self.current_balance} {self.current_coin}")
                        self.save_state()

                    # 3. Parse Loss
                    if "LOSS recorded" in line or "Streak:" in line:
                        match_loss = re.search(r'Column\s+([A-C]).*Bomb at:\s+([A-C\?]+).*Streak:\s+(\d+)', line)
                        if match_loss:
                            col = match_loss.group(1)
                            bomb = match_loss.group(2)
                            streak = int(match_loss.group(3))
                            self.total_rounds += 1
                            self.total_losses += 1
                            self.current_streak = streak
                            self.recent_losses.append({
                                "time": datetime.now().strftime("%H:%M:%S"),
                                "column": col,
                                "bomb": bomb,
                                "streak": streak
                            })
                            if streak > self.max_loss_streak:
                                self.max_loss_streak = streak

                            print(f"[{datetime.now().strftime('%H:%M:%S')}] 🚨 LOSS on Col {col} (Bomb: {bomb}) | Consecutive Losses: {streak}")
                            self.save_state()

                            # 🚨 CRITICAL WATCHDOG TRIGGER: Streak >= 3
                            if streak >= 3 and not self.is_rebuilding:
                                self.trigger_auto_fix_and_rebuild(f"Loss Streak reached {streak} >= 3 on Column {col}!")

            except KeyboardInterrupt:
                print("\n[WATCHDOG] Stopping watchdog daemon...")
                break
            except Exception as e:
                print(f"[WATCHDOG] Logcat streaming error: {e}. Reconnecting in 5s...")
                time.sleep(5)

if __name__ == "__main__":
    dog = StreakWatchdog()
    dog.run()
