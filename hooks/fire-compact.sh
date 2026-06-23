#!/usr/bin/env bash
# Stop hook: the hand that "presses the button" for us. If request-compact.sh
# left a flag for this pane, send `/compact <instructions>` into the now-idle
# prompt via tmux. Runs AFTER context-guard.sh in the same Stop group, so the
# model has already had its chance to decide + queue.
#
# Registered in settings.json under Stop (second in the group).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

payload="$(ctc_read_payload)"   # consume stdin; not otherwise needed

pane="$(ctc_resolve_pane)" || exit 0
key="$(ctc_key "$pane")"
flag="$CTC_FLAG_DIR/$key"
[ -f "$flag" ] || exit 0

# stale guard: a legit flag is consumed at the very next turn end (seconds).
# If it's older than the TTL, the writing turn was interrupted before its Stop
# hook ran — consume + discard without firing, so it never surprises a later turn.
age=$(( $(ctc_now) - $(ctc_mtime "$flag") ))
if [ "$age" -gt "$CTC_FLAG_TTL" ]; then
  rm -f "$flag"
  ctc_log "{\"ts\":\"$(date -u +%FT%TZ)\",\"event\":\"fire-compact\",\"status\":\"stale-discarded\",\"pane\":\"$pane\",\"age\":$age}"
  exit 0
fi

# flatten CR/LF/tab -> space so a multi-line instruction can't submit early
instr="$(tr '\r\n\t' '   ' < "$flag")"
rm -f "$flag"   # consume FIRST — no loop even if the send fails

# re-verify the pane still exists before sending
tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane" || {
  ctc_log "{\"ts\":\"$(date -u +%FT%TZ)\",\"event\":\"fire-compact\",\"status\":\"pane-gone\",\"pane\":\"$pane\"}"
  exit 0
}

cmd="/compact"
[ -n "$instr" ] && cmd="/compact $instr"

# C-u clears any text the user queued during the turn (Escape is intentionally
# NOT used — it misbehaves on some TUIs). -l sends the command literally so words
# like "Enter"/"Space" inside it aren't interpreted as keys.
tmux send-keys -t "$pane" C-u 2>/dev/null
tmux send-keys -t "$pane" -l "$cmd" 2>/dev/null
sleep 0.4
tmux send-keys -t "$pane" Enter 2>/dev/null

ctc_log "{\"ts\":\"$(date -u +%FT%TZ)\",\"event\":\"fire-compact\",\"status\":\"fired\",\"pane\":\"$pane\"}"
exit 0
