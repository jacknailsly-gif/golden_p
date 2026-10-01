---
name: scope
description: >-
  Strictly enforces boundary confinement and zero-bleed modification protocol.
  Use whenever the user invokes /scope, specifies strict scope boundaries, or commands not to touch unrelated code.
  Absolute prohibition against modifying, formatting, or refactoring ANY code or file outside the explicitly declared scope, regardless of AI model changes.
---

# คำสั่ง /scope (Ironclad Scope Boundary & Zero-Bleed Enforcement)

คำสั่ง `/scope` มีไว้เพื่อ **ล็อกขอบเขตการแก้ไขโค้ดอย่างเด็ดขาด 100% (Strict Boundary Confinement)** ป้องกันไม่ให้ AI ทำการแก้ไข, รีแฟกเตอร์, ลบโค้ด, หรือเปลี่ยนสไตล์ไฟล์ใดๆ นอกเหนือจากเป้าหมายที่กำหนดไว้ ไม่ว่าจะเปลี่ยน AI Model (Gemini, Claude, GPT, DeepSeek, Flash, Pro) หรือเริ่มเซสชันใหม่ก็ตาม

---

## 🔒 กฎเหล็ก 5 ประการของ /scope (The 5 Scope Invariants)

### 1. 🎯 Explicit Whitelisting (ล็อกเป้าเฉพาะไฟล์ที่ระบุ)
- ทันทีที่ผู้ใช้เรียก `/scope` หรือสั่งงานที่มีการกำหนดขอบเขต AI จะต้องประกาศกรอบ 4 บรรทัดตาม **G1 SCOPE**:
  - **Goal:** วัตถุประสงค์เดียวที่ต้องทำให้สำเร็จ
  - **In-scope:** รายชื่อไฟล์และฟังก์ชันที่อนุญาตให้แตะต้องได้เท่านั้น
  - **Out-of-scope:** ทุกไฟล์ ทุกฟังก์ชัน ทุกหน้าจอที่ไม่อยู่ใน In-scope (ห้ามแตะเด็ดขาด)
  - **Unknowns:** ข้อสงสัยที่หากเปลี่ยนแนวทางต้องถามก่อน
- **ไฟล์ใดที่ไม่ได้อยู่ใน In-scope ถือเป็น "เขตหวงห้ามเด็ดขาด" ห้ามเรียกใช้เครื่องมือเขียนหรือแก้ไขไฟล์นั้นเป็นอันขาด**

### 2. 🚫 Zero Incidental Changes (ห้ามจัดระเบียบหรือแก้งานพ่วง)
- **ห้าม** จัด Format โค้ดทั้งไฟล์ (No Auto-formatting / Lint cleanup ทั่วทั้งไฟล์)
- **ห้าม** รีแฟกเตอร์ (No Refactoring) โค้ดรอบข้างที่ไม่เกี่ยวกับบักหรือฟีเจอร์ที่สั่ง
- **ห้าม** ลบตัวแปร, ฟังก์ชัน, คอมเมนต์ หรือ import ที่ไม่ได้สร้างปัญหาโดยตรง
- **ห้าม** แก้ไข Unit Test อื่นให้ผ่านโดยไม่แก้ที่ต้นเหตุ

### 3. 🌐 Model-Agnostic Invariant (มีผลบังคับใช้เหนือกฎทุก Model AI)
- กฎนี้ถูกเขียนลงในแกนกลางของโปรเจกต์ (`AGENTS.md`, `GEMINI.md`, `CLAUDE.md`, `.agents/rules/`) 
- **ต่อให้เปลี่ยน AI Model ไปเป็นโมเดลใดก็ตาม** โมเดลที่เข้ามารับช่วงต่อจะต้องอ่านและปฏิบัติตามกฎนี้โดยไม่มีข้อยกเว้น ห้ามอ้างว่าโมเดลใหม่ไม่รู้บริบท

### 4. 🛡️ Pre-Tool Boundary Check (ตรวจก่อนลงมือแก้)
- ก่อนเรียกใช้เครื่องมือ `replace_file_content` หรือ `write_to_file`:
  1. ตรวจสอบว่าไฟล์เป้าหมายตรงกับรายการใน In-scope หรือไม่
  2. หากไม่ใช่ไฟล์ใน In-scope **ต้องยกเลิกคำสั่งทันที** และห้ามแตะต้อง

### 5. 🔍 Post-Edit Git Audit (ตรวจสอบก่อนส่งงาน)
- หลังลงมือแก้เสร็จ ทุกครั้งต้องรันคำสั่ง:
  ```bash
  git status
  git diff --stat
  ```
- หากพบว่ามีไฟล์นอกรายการ In-scope ถูกแก้ไข แม้แต่ไฟล์เดียวหรือบรรทัดเดียว:
  - ต้องสั่ง `git checkout -- <file>` หรือคืนค่าเดิมทันที
  - ไม่อนุญาตให้ปล่อยผ่าน

---

## 📋 แม่แบบการประกาศ /scope เมื่อเริ่มงาน

เมื่อผู้ใช้พิมพ์ `/scope` หรือเริ่มงานใหม่ AI ต้องตอบรับด้วยรูปแบบนี้ก่อนลงมือเสมอ:

```markdown
### 🛡️ [ACTIVE /SCOPE LOCK]
- **Goal:** [ระบุเป้าหมายที่แท้จริง]
- **In-scope:** [ระบุเฉพาะไฟล์:บรรทัดที่จะแก้]
- **Out-of-scope:** [ระบุไฟล์หรือระบบที่ห้ามแตะต้องเด็ดขาด เช่น โครงสร้าง AI, UI, สูตรคำนวณ]
- **Unknowns:** [ถ้ามีข้อสงสัยที่ทำให้แนวทางเปลี่ยน ให้ถามก่อน ห้ามเดา]
```
