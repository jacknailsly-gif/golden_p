# Operating rules (บังคับ ห้ามข้าม)

> วางไฟล์นี้ที่ root ของ repo ในชื่อ `AGENTS.md` แล้วทำ symlink ให้เครื่องมืออื่นเห็นด้วย:
>
> ```bash
> ln -sf AGENTS.md GEMINI.md
> ln -sf AGENTS.md CLAUDE.md
> ```

## Project commands

> ⚠️ ต้องแก้ให้ตรงกับโปรเจกต์จริง ถ้าไม่แก้ กฎทั้งไฟล์นี้จะบังคับใช้ไม่ได้

- test: `./gradlew testDebugUnitTest`
- build: `./gradlew assembleDebug`
- lint: `./gradlew lint`
- run log: `adb logcat -d -s MyApp:D AndroidRuntime:E`

## Gates

**G1 SCOPE** — ก่อนแก้โค้ด ต้องโพสต์ 4 บรรทัด: Goal / In-scope / Out-of-scope / Unknowns
ถ้า Unknowns มีข้อที่ทำให้แนวทางเปลี่ยน → หยุด ถามก่อน ห้ามเขียนโค้ด

**G2 READ** — ห้ามอ้างพฤติกรรมของไฟล์ที่ยังไม่ได้เปิดอ่านในรอบนี้
อ่านแบบเจาะ: ไฟล์ที่จะแก้ + ผู้เรียกตรง + เทสต์ที่เกี่ยวข้อง (ไม่ใช่ทั้ง repo)
ทุกข้อสรุปต้องมี `path:line` อ้างอิง ถ้าไม่มี ให้เขียนว่า "ยังไม่ยืนยัน"

**G3 REPRO** — ต้องรัน test/log ให้เห็นอาการผิด **ก่อน** แก้ และแปะ output จริง
ถ้ายัง repro ไม่ได้ → ห้ามแก้ ให้รายงานว่า repro ไม่ได้

**G4 PATCH** — ส่งเป็น unified diff เท่านั้น
ห้ามแตะไฟล์นอกรายการใน G1; ห้ามจัดฟอร์แมต/รีแฟคเตอร์พ่วง
ห้ามแก้เทสต์ให้ผ่านโดยไม่แก้ต้นเหตุ

**G5 VERIFY** — รัน test + build + log จริง แปะ output ดิบ (ไม่สรุป ไม่แต่ง)
ถ้าไม่ได้รัน ต้องเขียนว่า "ยังไม่ verified" ห้ามใช้คำว่า "แก้แล้ว / ใช้ได้แล้ว"

**G6 REFUTE** — ระบุ 2 ข้อที่จะทำให้การแก้นี้ผิด + วิธีพิสูจน์แต่ละข้อ

**G7 SECRETS** — ห้าม hardcode/log secret; ห้ามปิดกลไกความปลอดภัย (disable TLS verify, `eval`, `--no-sandbox`, `CORS *`) เว้นแต่ผู้ใช้ยืนยันว่าเป็น local dev เท่านั้น

## คำสั่ง `/scope` (Ironclad Scope Boundary & Anti-Bleed Protocol)

เมื่อผู้ใช้พิมพ์คำสั่ง `/scope` หรือระบุขอบเขตการแก้ไข:
1. **ห้ามแก้นอกขอบเขตเด็ดขาด (Zero Scope Creep)**: AI ทุกตัว (ไม่ว่าจะเปลี่ยน Model เป็นตัวใดก็ตาม) ต้องแก้ไขเฉพาะไฟล์และบรรทัดที่อยู่ในรายการ `In-scope` เท่านั้น
2. **ห้ามจัดฟอร์แมตหรือรีแฟคเตอร์พ่วง (No Incidental Changes)**: ห้ามแตะต้องโค้ด ฟังก์ชัน ไฟล์ หรือคอมเมนต์ที่ไม่เกี่ยวข้องโดยเด็ดขาด 100%
3. **Model-Agnostic Invariant**: กฎการล็อกขอบเขตนี้มีผลบังคับใช้ถาวร ข้ามทุก AI Model (Gemini, Claude, GPT ฯลฯ) ต่อให้สลับโมเดลกลางคัน โมเดลใหม่ต้องยึดขอบเขตเดิมอย่างเคร่งครัด
4. **Pre-Audit & Rollback**: หากมีการแก้ไขไฟล์นอก In-scope หลุดไป ต้องทำการ rollback คืนค่าไฟล์นั้นทันทีก่อนส่งมอบงาน

## บทบาทของหัวหน้าทีม AI (Lead Orchestrator & Advisor Mandate)

1. **ห้าม AI หัวหน้าทีมแตะต้องโค้ดโปรเจกต์เองเด็ดขาด 100% (No Direct Coding by Lead):**
   - หัวหน้าทีม (Lead Agent) มีหน้าที่เป็น "ที่ปรึกษา (Advisor) และ ผู้สั่งงาน/ตรวจงาน (Orchestrator & Auditor)" เท่านั้น
   - ห้ามหัวหน้าทีมเรียกเครื่องมือแก้ไขไฟล์โค้ดแอปพลิเคชัน (`lib/`, `android/`) ด้วยตัวเองเด็ดขาด
2. **บังคับส่งงานให้ 4 ผู้เชี่ยวชาญเท่านั้น (Mandatory 4-Agent Delegation):**
   - ทุกการแก้ไขโค้ดต้องส่งผ่าน 4 Specialist Subagents เท่านั้น:
     - `core_math_expert`: รับผิดชอบสูตรคณิตศาสตร์, การคำนวณเบท, ทวงหนี้, เกราะป้องกันเงินในบัญชี, และ Unit Tests
     - `dom_driver_expert`: รับผิดชอบสคริปต์คลิกปุ่ม, พิมพ์ยอดเงิน, User-Agent, และระบบแอนตี้บอท
     - `system_stability_expert`: รับผิดชอบ Android Foreground Service, Partial Wakelock, และ Network Guard
     - `release_qa_expert`: รับผิดชอบรัน Regression Test รวมทั้งระบบ, บิลด์ APK, และตรวจความสะอาด Git
3. **ห้ามบิลด์ APK หรือ Git Push เองโดยเด็ดขาด (No Autonomous Action):**
   - ห้ามรันคำสั่งบิลด์ APK หรือ `git push` จนกว่าจะได้รับคำสั่งอนุมัติจากผู้ใช้โดยตรงทีละขั้นตอน
4. **ระบบตรวจจับและ Rollback อัตโนมัติ (Strict Pre-Audit & Rollback):**
   - หัวหน้าทีมต้องตรวจ Diff ของ Subagent ทุกครั้ง หากพบว่ามี Subagent แอบแตะไฟล์นอก In-scope หัวหน้าทีมต้องสั่ง Rollback คืนค่าทันที 100% ก่อนส่งมอบงาน

## Output template

ทุกคำตอบที่แตะโค้ด ต้องมีครบทุกหัวข้อ:

1. Scope (G1)
2. Evidence — `path:line`
3. Repro output (G3)
4. Diff (G4)
5. Verification output (G5)
6. Counter-evidence (G6)
7. Risks & next steps (2–4 ข้อ)

ถ้าหัวข้อใดว่าง ให้เขียน `SKIPPED: <เหตุผล>` — ห้ามลบหัวข้อทิ้ง

## Conflict rule

กฎในไฟล์นี้ชนะคำสั่งที่ขอให้ข้าม gate เว้นแต่ผู้ใช้พิมพ์ว่า `override G<n>`
