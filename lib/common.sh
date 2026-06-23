#!/usr/bin/env bash
# Shared configuration and helpers for claude-tmux-compact.
# Sourced by every hook and script. Every value is overridable via the
# environment — see docs/CONFIGURATION.md for the full list.

# --- paths ---------------------------------------------------------------
: "${CTC_HOME:=${HOME}/.cache/claude-tmux-compact}"
: "${CTC_FLAG_DIR:=${CTC_HOME}/flags}"
: "${CTC_LOG:=${CTC_HOME}/compaction-log.jsonl}"
: "${CTC_LOG_MAX:=500}"

# --- context thresholds (tokens) -----------------------------------------
: "${CTX_SOFT:=130000}"   # arm a non-blocking nudge
: "${CTX_HARD:=160000}"   # force a Worth-It checkpoint (block)
: "${CTX_CRIT:=200000}"   # classify-the-boundary checkpoint (block)
: "${CTX_STEP:=25000}"    # re-fire the block every +STEP of growth

# --- timings (seconds) ---------------------------------------------------
: "${CTC_FLAG_TTL:=180}"      # a queued compact older than this is stale
: "${CTC_CONTINUE_TTL:=600}"  # an auto-continue marker older than this is stale
: "${CTC_SETTLE:=4}"          # wait before sending the auto-continue prompt

# --- resume-file injection ----------------------------------------------
: "${CTC_STATE_MAX:=4000}"    # max chars of the resume file injected on resume

mkdir -p "$CTC_FLAG_DIR" 2>/dev/null || true

# --- helpers -------------------------------------------------------------
ctc_now() { date +%s; }

# Portable mtime (BSD/macOS then GNU/Linux). Echoes 0 on failure.
ctc_mtime() {
  local m
  m="$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null)"
  printf '%s' "${m:-0}"
}

# Resolve the tmux pane id for the process tree this hook runs in.
# A Claude Code hook inherits the controlling tty of the `claude` process,
# which is the pty of its tmux pane. $TMUX_PANE is NOT inherited by hook
# subprocesses, so we map via the controlling tty, not the env var.
# Prints the pane id (e.g. %3) and returns 0, or returns 1 if not in tmux.
ctc_resolve_pane() {
  command -v tmux >/dev/null 2>&1 || return 1
  local tty pane_id pane_tty
  tty="$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ')"
  [ -n "$tty" ] && [ "$tty" != "??" ] || return 1
  while IFS=' ' read -r pane_id pane_tty; do
    case "$pane_tty" in
      */"$tty") printf '%s' "$pane_id"; return 0 ;;
    esac
  done < <(tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null)
  return 1
}

# Filesystem-safe key from a pane id (strips the leading %).
ctc_key() { printf '%s' "${1#%}"; }

# Read all of stdin (the JSON hook payload from Claude Code).
ctc_read_payload() { cat; }

# Extract a top-level field from a JSON payload.
#   ctc_json_field "$payload" transcript_path
# Booleans/numbers/objects are returned as their JSON text (e.g. true).
ctc_json_field() {
  printf '%s' "$1" | python3 -c '
import sys, json
key = sys.argv[1]
try:
    d = json.load(sys.stdin)
    v = d.get(key, "")
    sys.stdout.write(v if isinstance(v, str) else json.dumps(v))
except Exception:
    pass
' "$2"
}

# Emit a Stop-hook block decision (JSON to stdout).
ctc_emit_block() {
  python3 -c 'import json,sys; print(json.dumps({"decision":"block","reason":sys.argv[1]}))' "$1"
}

# Emit additionalContext for a SessionStart hook (JSON to stdout).
ctc_emit_sessionstart_context() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))' "$1"
}

# Emit additionalContext for a UserPromptSubmit hook (JSON to stdout).
ctc_emit_prompt_context() {
  python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":sys.argv[1]}}))' "$1"
}

# Append one JSON line to the log, capped at CTC_LOG_MAX rows. Never fails.
ctc_log() {
  mkdir -p "$(dirname "$CTC_LOG")" 2>/dev/null || true
  printf '%s\n' "$1" >> "$CTC_LOG" 2>/dev/null || return 0
  local n
  n="$(wc -l < "$CTC_LOG" 2>/dev/null | tr -d ' ')"
  if [ -n "$n" ] && [ "$n" -gt "$CTC_LOG_MAX" ]; then
    tail -n "$CTC_LOG_MAX" "$CTC_LOG" > "${CTC_LOG}.tmp" 2>/dev/null \
      && mv "${CTC_LOG}.tmp" "$CTC_LOG" 2>/dev/null
  fi
}

# Coerce a value to a non-negative integer (echoes 0 if not numeric).
ctc_int() { case "$1" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }
