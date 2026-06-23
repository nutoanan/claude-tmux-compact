# Architecture

## The core problem

A language model cannot run `/compact` on itself — slash commands are a UI
action. So compaction is a **hand-off**: the model expresses intent (a flag
file), and a shell hook performs the action (`tmux send-keys`). Everything here
is built around that one constraint.

tmux is the delivery layer because `send-keys` writes to the pane's pty directly
and focus-independently. See [TROUBLESHOOTING](TROUBLESHOOTING.md) for why
osascript / terminal-scripting paths were rejected.

## Components

### `bin/request-compact.sh` — the trigger (model-side)

Called by the model when it decides to compact. Resolves its tmux pane, writes a
**flag file** `flags/<pane>` containing the "keep set" instructions, and (by
default) a `flags/<pane>.continue` marker holding a short resume hint. Then the
model ends its turn. If not in tmux, it prints a paste-ready `/compact` fallback
and exits non-zero.

### `hooks/context-guard.sh` — the mechanical floor (`Stop` + `UserPromptSubmit`)

The honor-system "decide when to compact" can fail open (a session can ride to
~100% context). This hook is the backstop. On **Stop** it reads the real context
size and forces a decision; on **UserPromptSubmit** it surfaces a soft nudge.

How it reads context: from the hook payload's `transcript_path`, it scans the
JSONL transcript backwards for the **last assistant `usage`** and sums
`input_tokens + cache_read_input_tokens + cache_creation_input_tokens` — the same
figure the in-app meter reflects.

Tiers (defaults, all configurable):

| Tier | Threshold | Action |
| --- | --- | --- |
| SOFT | ~130k | arm a one-shot nudge, shown at the next prompt (no block) |
| HARD | ~160k | `Stop` **block** → model runs the Worth-It check |
| CRITICAL | ~200k | `Stop` **block** → model **classifies the boundary** |

It **re-fires** every `+CTX_STEP` (~25k) of further growth, so a single declined
checkpoint can't go silent while context keeps climbing. It never compacts
itself — it only emits `{"decision":"block","reason":...}` so the model decides.

State per pane: `flags/<pane>.ctxpressure` (last-fired ctx) and
`flags/<pane>.ctxnudge` (armed nudge text). Both are cleared once context drops
below SOFT, re-arming for the next climb.

### `hooks/fire-compact.sh` — the button-presser (`Stop`)

Runs **after** `context-guard.sh` in the same `Stop` group. If `flags/<pane>`
exists, it sends `/compact <instructions>` into the pane:

- **Stale guard** — a legit flag is consumed within seconds; one older than
  `CTC_FLAG_TTL` (180s) means the writing turn was interrupted, so it's discarded
  without firing.
- **Consume-first** — the flag is removed before sending, so there's no loop even
  if the send fails.
- **Safe send** — `C-u` clears any queued user input; instructions are flattened
  to one line; `send-keys -l` sends literally (so words like "Enter" aren't keys);
  a separate `Enter` submits.

### `hooks/rehydrate.sh` — re-inject + auto-continue (`SessionStart`, matcher `compact`)

Fires after compaction completes. Two jobs:

1. **Inject context** — if a resume file exists (`CTC_STATE`, default
   `<cwd>/.claude/resume.md`), its first `CTC_STATE_MAX` chars are returned as
   `additionalContext`.
2. **Auto-continue** — if a fresh `flags/<pane>.continue` marker exists, a
   detached job waits `CTC_SETTLE` seconds for the prompt to settle, then sends
   `continue: <hint>`. Marker-gated, so manual/auto compactions never auto-resume.

**Why SessionStart, not PostCompact:** PostCompact cannot inject context back into
the model (its output goes to the user as stderr only). `SessionStart`
`additionalContext` does reach the model — so re-injection must live here.

### `hooks/log-compaction.sh` — audit trail (`PreCompact` + `PostCompact`)

Writes one JSONL row per event (`pre`/`post`, `manual`/`auto`, session, cwd) to
`compaction-log.jsonl`, capped at `CTC_LOG_MAX` rows. **PreCompact is blocking**
(a non-zero exit aborts the compaction), so this script always exits 0.

### `lib/common.sh` — shared config + helpers

Env defaults, the tty→pane resolver, portable mtime, JSON field extraction, JSON
emitters (block / SessionStart / UserPromptSubmit), and the capped logger.

## Lifecycle (end to end)

```
turn ends
  └─ Stop: context-guard.sh   → maybe BLOCK ("run the Worth-It check")
  └─ Stop: fire-compact.sh    → flag? → tmux send-keys "/compact <keep set>"
PreCompact (manual|auto)      → log-compaction.sh pre
  … Claude compacts …
PostCompact (manual|auto)     → log-compaction.sh post
SessionStart(source=compact)  → rehydrate.sh
                                  ├─ inject resume.md as context
                                  └─ tmux send-keys "continue: <hint>"
model resumes the next action
```

## Pane resolution

The Bash tool / hook subprocess does **not** inherit `$TMUX_PANE`. Instead the
hook's controlling tty (`ps -o tty= -p $$`) is matched against
`tmux list-panes -a -F '#{pane_id} #{pane_tty}'`. This correctly targets the
right pane even with multiple concurrent `claude` sessions — each one only ever
touches its own flag files.

## Design principles

- **The model decides; hooks act.** No hook ever compacts on its own.
- **Fail safe.** Any parse/IO error exits 0 — a hook must never break a turn
  (and PreCompact must never abort a compaction).
- **Self-consuming flags.** Every flag/marker is removed when handled, so nothing
  loops or surprises a later unrelated turn.
- **Keep pointers, not payloads.** Compaction preserves the next action and file
  paths; heavy content is re-read on demand.
