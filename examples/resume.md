# Resume state (example)

This file is OPTIONAL. If it exists, `rehydrate.sh` injects it as context right
after a compaction so the model keeps its bearings. Point at it with `CTC_STATE`
(default: `<cwd>/.claude/resume.md`).

Keep it SMALL — only what's needed to resume. The first ~4000 chars are injected
(tune with `CTC_STATE_MAX`). Treat it as durable "next action" state that the
model rewrites as work progresses.

## Current focus
- What you are working on right now (one line).

## Next action
- The single most important next step.

## Useful pointers
- Key file paths, a running dev-server URL, an open PR number, etc.
- Anything you'd otherwise have to re-derive after a compaction.
