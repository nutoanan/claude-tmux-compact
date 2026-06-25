# Self-compaction policy (claude-tmux-compact)

This session can compact its own context and resume on its own. To queue a
compaction, run this command, then END the turn:

    REQUEST_COMPACT_CMD "<keep set: current focus + the single next action + key file paths>"

The Stop hook types `/compact <keep set>` into the tmux pane at the next turn end;
after compaction the session auto-continues into the next action (no keystroke).

Run the **Worth-It check at the END of every turn** — do not wait for the context
to fill. Compact only when ALL THREE hold:

- **SAFE** — durable work is flushed to files; no pending gate/approval; nothing
  unsaved.
- **PAYOFF** — substantial work remains AND the next step needs far less context
  than this turn carries. Evaluate PAYOFF first: if this is the last/only task
  with nothing queued after, STOP — do **not** compact. SAFE alone never triggers.
- **NO THRASH** — the next step will not immediately re-read what compaction drops.

**Keep set = pointers, not payloads:** focus + one next action + paths to
state/proof files. Re-read heavy content from those paths after compacting; do not
preserve it inline. A path costs a few tokens; the file behind it costs thousands.

At the **CRITICAL** context line, classify the boundary instead of blanket-compacting:

- **TERMINUS** (work done, nothing queued) → STOP and summarize; do not compact.
- **CONTINUATION** (known next work, or the user said continue) → compact THEN
  proceed. Order is confirm-continuation → compact → work.
- **GREY ZONE** (only optional/suggested follow-up) → ask the user first; compact
  only after they confirm.

A self-compact fires ONLY when there is a known continuation to resume into, and
is ALWAYS followed by it.

Auto-continue is ON by default. Pass `no-continue` as the second argument to
`REQUEST_COMPACT_CMD` only when the user explicitly wants to stop after compacting.

If `REQUEST_COMPACT_CMD` reports it is NOT in tmux, present a paste-ready
`/compact <keep set>` block for the user instead of silently skipping — the whole
mechanism depends on tmux.
