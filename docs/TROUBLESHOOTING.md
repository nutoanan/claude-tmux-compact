# Troubleshooting

## Nothing happens when the model calls `request-compact.sh`

- **Are you in tmux?** Self-compaction only works when Claude runs inside tmux.
  Launch with `cc` (from `shell/cc.sh`). Check: `echo $TMUX` should be non-empty
  in the Claude session.
- **Is the `Stop` hook registered?** `fire-compact.sh` fires on the *next turn
  end*. Verify it's in `~/.claude/settings.json` under `Stop`, after
  `context-guard.sh`.
- **Stale flag?** A flag older than `CTC_FLAG_TTL` (180s) is discarded. If the
  turn that called the trigger was interrupted before it ended, the flag never
  fires. Look for `"status":"stale-discarded"` in the log.
- **Check the log:** `tail ~/.cache/claude-tmux-compact/compaction-log.jsonl`.

## The `/compact` text appears but doesn't submit

- A slash menu or picker may have eaten the `Enter`. Increase the settle/sleep by
  raising `CTC_SETTLE`, and avoid leaving a picker open when a compact is due.
- `Escape` is intentionally **not** sent to clear input (it misbehaves on some
  TUIs). Only `C-u` (readline kill-line) is used. If you had text queued that
  wasn't cleared, that edge isn't covered — clear the input before ending the turn.

## Auto-continue doesn't resume after compaction

- Auto-continue is **marker-gated**: only compactions triggered via
  `request-compact.sh` (without `no-continue`) resume. Manual `/compact` and the
  app's automatic compaction never auto-resume by design.
- The marker has a `CTC_CONTINUE_TTL` (600s) freshness window; a compaction that
  took too long won't auto-resume. Look for `"status":"stale-continue"`.
- The pane may have changed. Look for `continue-armed` vs nothing in the log.

## Context guard never blocks (rides to 100%)

- Confirm `context-guard.sh stop` is registered under `Stop` and runs.
- It needs a readable `transcript_path` in the payload; if absent it exits 0.
- Thresholds too high? Check `CTX_HARD` / `CTX_CRIT`.
- It won't block while a compact is already queued, or when `stop_hook_active` is
  true (loop guards). That's expected.

## Context guard blocks too often / too aggressively

- Raise `CTX_SOFT` / `CTX_HARD` / `CTX_CRIT` (see [CONFIGURATION](CONFIGURATION.md)).
- It re-fires every `+CTX_STEP` of growth by design, so a declined checkpoint
  can't go silent. Raise `CTX_STEP` to space them out.

## PreCompact seems to abort compaction

- `PreCompact` is a **blocking** hook — any non-zero exit aborts the compaction.
  `log-compaction.sh` always exits 0; if you customized it, make sure it still
  does.

## `stat` / `date` errors on Linux

- The scripts try BSD `stat -f %m` then GNU `stat -c %Y`; both are handled. If you
  see errors, ensure `coreutils` is installed and `python3` is on `PATH`.

## Why not osascript / a terminal-scripting CLI instead of tmux?

- On some terminals (e.g. Warp) there is **no send-text CLI**, and `osascript`
  "System Events keystroke" is blocked (error 1002) until Accessibility is
  granted — and even then it's focus-fragile (keys go to whatever app is
  frontmost). `tmux send-keys` writes to the pane's pty directly and is
  focus-independent, which is why it's the chosen mechanism.

## Multiple concurrent Claude sessions

- Supported. Pane resolution is by controlling tty, so each session only ever
  touches its own flag files. No cross-talk.
