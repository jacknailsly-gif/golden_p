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
