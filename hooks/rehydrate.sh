#!/usr/bin/env bash
# SessionStart(source=compact) hook. Fires AFTER a compaction completes. Two jobs:
#   1) Re-inject a project resume file as additionalContext (the model keeps its
#      bearings — phase, next action, URLs — without re-reading everything).
#   2) Auto-continue: send a "continue" prompt into the pane so work resumes with
#      no keystroke. Claude Code has NO native post-compaction auto-continue, so
#      this is done the same way as the trigger — tmux send-keys.
#
# Why here and not PostCompact: PostCompact CANNOT inject context back into the
# model (stderr-to-user only); SessionStart additionalContext does reach it.
#
# Registered in settings.json under SessionStart with matcher "compact".
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

payload="$(ctc_read_payload)"

cwd="$(ctc_json_field "$payload" cwd)"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
state="${CTC_STATE:-$cwd/.claude/resume.md}"

# 1) inject the resume file as context (if present and non-empty)
if [ -f "$state" ]; then
  content="$(head -c "$CTC_STATE_MAX" "$state" 2>/dev/null)"
  if [ -n "$content" ]; then
    ctc_emit_sessionstart_context "RESUME STATE (from ${state}):
${content}"
  fi
fi

# 2) auto-continue (marker-gated => user/auto compactions never auto-resume)
pane="$(ctc_resolve_pane)" || exit 0
key="$(ctc_key "$pane")"
marker="$CTC_FLAG_DIR/$key.continue"
[ -f "$marker" ] || exit 0

age=$(( $(ctc_now) - $(ctc_mtime "$marker") ))
hint="$(tr '\r\n\t' '   ' < "$marker")"
rm -f "$marker"
if [ "$age" -gt "$CTC_CONTINUE_TTL" ]; then
  ctc_log "{\"ts\":\"$(date -u +%FT%TZ)\",\"event\":\"rehydrate\",\"status\":\"stale-continue\",\"pane\":\"$pane\",\"age\":$age}"
  exit 0
fi

# detached: let the freshly-compacted prompt settle, then send the continue
( sleep "$CTC_SETTLE"
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane" || exit 0
  tmux send-keys -t "$pane" C-u 2>/dev/null
  tmux send-keys -t "$pane" -l "continue: ${hint} (post-compaction auto-resume)" 2>/dev/null
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null
) >/dev/null 2>&1 &

ctc_log "{\"ts\":\"$(date -u +%FT%TZ)\",\"event\":\"rehydrate\",\"status\":\"continue-armed\",\"pane\":\"$pane\"}"
exit 0
