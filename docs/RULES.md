# Rules to add to your CLAUDE.md

The hooks are the **mechanism**. These rules are the **policy** — they tell the
model *when* and *how* to compact. Paste the English blocks into your global
`~/.claude/CLAUDE.md` (the model works most reliably in English). Each rule
includes *why* it exists, in English and Thai.

> Adjust the trigger path to where you cloned the repo
> (`/abs/path/bin/request-compact.sh`).

---

## Rule 1 — Worth-It Calculation

```text
Compact only when ALL THREE hold:
- SAFE: durable work is flushed to files; no pending approval/gate; nothing unsaved.
- PAYOFF: substantial work remains AND the next step needs far less context than this turn carries.
- NO THRASH: the next step will not immediately re-read what compaction would drop.
When all three hold and a KNOWN next action exists, call:
  /abs/path/bin/request-compact.sh "<keep set: focus + next action + key paths>"
then END the turn. Run this check at the END of every turn — do not wait for context to bloat.
```

**Why:** compaction has a cost (summary generation + cache reset), so it should
only happen when it clearly pays for itself. The three gates rule out the cases
where it doesn't.

**ทำไม:** การ compact มีต้นทุน (สร้าง summary + รีเซ็ต cache) จึงควรทำเฉพาะตอนที่
คุ้มจริง ๆ — SAFE กันของหาย, PAYOFF กันการ compact ทั้งที่งานใกล้จบ (ไม่คุ้ม),
NO THRASH กันการ compact แล้วต้องรีบโหลดของเดิมกลับมาทันที (เสียเปล่าสองรอบ)

---

## Rule 2 — PAYOFF first

```text
Evaluate PAYOFF first. If this is the last/only task with nothing queued after,
STOP — do NOT compact. SAFE alone never triggers a compaction.
```

**Why:** compacting at a true terminus (work done, nothing next) burns tokens on
a summary nobody will use, and — with auto-continue off — can leave the session
in a dead, contextless state.

**ทำไม:** ถ้า compact ตอนงานจบพอดี (ไม่มีอะไรทำต่อ) จะเสีย token ไปกับ summary
ที่ไม่มีใครได้ใช้ และอาจทำให้ session ค้างแบบไม่มี context กฎนี้บังคับให้เช็ก
"ยังมีงานต่อไหม" ก่อนเสมอ

---

## Rule 3 — Classify the boundary at CRITICAL

```text
At the CRITICAL context line, do NOT blanket-compact — classify the boundary:
- TERMINUS (work done, nothing queued): STOP and summarize. Do NOT compact.
- CONTINUATION (known next work, or the user said continue): compact THEN proceed.
  Order is confirm-continuation -> compact -> work.
- GREY ZONE (only optional/suggested follow-up): ask the user first; compact only after they confirm.
A self-compact fires ONLY with a known continuation to resume into, and is ALWAYS followed by it.
```

**Why:** the CRITICAL line means "don't carry a huge context across into more
work" — not "always compact." Forcing a compaction at a dead end is the exact
waste Rule 2 prevents; this rule keeps that true even under context pressure.

**ทำไม:** เส้น CRITICAL แปลว่า "อย่าแบก context สูง ๆ ข้ามไปทำงานต่อ" ไม่ได้แปลว่า
"เจอเส้นแล้วต้อง compact ทุกกรณี" — การ compact ที่ทางตันคือความสิ้นเปลืองที่
Rule 2 กันไว้ กฎนี้รักษาหลักการนั้นไว้แม้ context จะสูง

---

## Rule 4 — Auto-continue is the default

```text
After a self-compact, resume the next action automatically (auto-continue ON by default).
Pass `no-continue` to request-compact.sh ONLY when the user explicitly wants to stop.
```

**Why:** the only reason to compact is that work remains (PAYOFF), so resuming is
the natural default; stopping is the exception.

**ทำไม:** เหตุผลเดียวที่ compact คือ "ยังมีงานต่อ" (PAYOFF) ดังนั้นการทำงานต่อให้เอง
จึงควรเป็นค่าเริ่มต้น จะปิด (`no-continue`) เฉพาะตอนผู้ใช้สั่งหยุดจริง ๆ

---

## Rule 5 — Keep pointers, not payloads

```text
The compaction "keep set" carries only what's needed to resume: current focus,
the single next action, and paths to state/proof files. Re-read heavy content
from those paths after compaction instead of preserving it inline.
```

**Why:** this is what makes the context drop large (~80%) while losing nothing —
a path is a few tokens; the file behind it is thousands.

**ทำไม:** นี่คือเหตุผลที่ context ลดลงเยอะ (~80%) โดยไม่เสียข้อมูล — path กินไม่กี่
token แต่ไฟล์ที่มันชี้ไปกินเป็นพัน อ่านกลับเมื่อต้องใช้พอ

---

## Optional: a non-tmux fallback line

```text
If request-compact.sh reports it is NOT in tmux, present a paste-ready
`/compact <keep set>` block for the user instead of silently skipping.
```

**Why / ทำไม:** the whole mechanism depends on tmux; outside it, degrade
gracefully to a manual paste. — กลไกทั้งหมดพึ่ง tmux เมื่ออยู่นอก tmux ให้ถอย
ไปเป็นบล็อก `/compact` ให้ผู้ใช้วางเองแทนการเงียบหาย
