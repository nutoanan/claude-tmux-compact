#!/usr/bin/env bash
# Queue a self-compaction. This is the MODEL-SIDE trigger: Claude calls it when
# it decides (via the Worth-It check) that compacting is worth it. It does NOT
# compact immediately — it drops a flag file that the Stop hook (fire-compact.sh)
# consumes on the next turn end, sending `/compact <instructions>` into the tmux
# pane. A model cannot run a slash command on itself, so this hand-off is the
# whole point.
#
# Usage:
#   request-compact.sh "<preserve instructions + next action>"
#   request-compact.sh "<...>" no-continue   # compact but do NOT auto-resume
#
# Auto-continue (default ON): also writes a `<pane>.continue` marker so the
# SessionStart(compact) hook sends a "continue" prompt once compaction finishes,
# resuming the next action with no keystroke. We compact only when there IS more
# work, so resuming is the right default; pass `no-continue` to opt out.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

instr="${1:-}"

pane="$(ctc_resolve_pane)" || {
  echo "NOT in tmux (or tmux unavailable) — self-compact is not available here." >&2
  echo "Fallback — paste this to compact manually:" >&2
  echo "/compact ${instr}" >&2
  exit 1
}
key="$(ctc_key "$pane")"
printf '%s' "$instr" > "$CTC_FLAG_DIR/$key"

if [ "${2:-}" = "no-continue" ]; then
  rm -f "$CTC_FLAG_DIR/$key.continue"
  echo "compact queued for pane $pane (fires on turn end; auto-continue OFF)"
else
  printf '%s' "$instr" | cut -c1-120 > "$CTC_FLAG_DIR/$key.continue"
  echo "compact queued for pane $pane (fires on turn end; auto-continue ON)"
fi
