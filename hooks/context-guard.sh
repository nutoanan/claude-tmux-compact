#!/usr/bin/env bash
# Mechanical context-pressure floor. Because the model deciding when to compact
# is honor-system (and can fail open — riding context to ~100%), this hook reads
# the REAL context size every turn end and forces a decision at thresholds.
#
# IMPORTANT: this hook never compacts on its own. At HARD/CRITICAL it emits a
# Stop `block` to FORCE the model to run the Worth-It check; the model still
# decides whether and how to compact (via request-compact.sh).
#
# Registered TWICE in settings.json:
#   Stop:             context-guard.sh stop
#   UserPromptSubmit: context-guard.sh prompt
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/../lib/common.sh" ] || { echo "claude-tmux-compact: missing $DIR/../lib/common.sh — keep the repo intact and point hooks at <repo>/hooks (re-run install.sh)." >&2; exit 0; }
. "$DIR/../lib/common.sh"

mode="${1:-stop}"
payload="$(ctc_read_payload)"

# key = tmux pane if resolvable, else the session id from the payload
key="$(ctc_resolve_pane)" || key=""
[ -n "$key" ] || key="$(ctc_json_field "$payload" session_id)"
key="$(ctc_key "$key")"
[ -n "$key" ] || exit 0

pflag="$CTC_FLAG_DIR/$key.ctxpressure"   # last-fired ctx (int)
nflag="$CTC_FLAG_DIR/$key.ctxnudge"      # armed SOFT nudge text

# --- UserPromptSubmit: surface the armed nudge, then clear it -------------
if [ "$mode" = "prompt" ]; then
  if [ -f "$nflag" ]; then
    msg="$(cat "$nflag" 2>/dev/null)"
    rm -f "$nflag"
    [ -n "$msg" ] && ctc_emit_prompt_context "$msg"
  fi
  exit 0
fi

# --- Stop: read context, decide whether to block -------------------------
# never re-block inside a stop-hook continuation (loop guard)
[ "$(ctc_json_field "$payload" stop_hook_active)" = "true" ] && exit 0
# if a compact is already queued for this pane, don't fight the send-keys
[ -f "$CTC_FLAG_DIR/$key" ] && exit 0

tpath="$(ctc_json_field "$payload" transcript_path)"
[ -n "$tpath" ] && [ -f "$tpath" ] || exit 0

# sum input + cache_read + cache_creation of the LAST assistant usage
ctx="$(python3 - "$tpath" <<'PY'
import sys, json
total = 0
try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except Exception:
            continue
        u = None
        if isinstance(o, dict):
            m = o.get("message")
            if isinstance(m, dict) and isinstance(m.get("usage"), dict):
                u = m["usage"]
            elif isinstance(o.get("usage"), dict):
                u = o["usage"]
        if u:
            total = ((u.get("input_tokens") or 0)
                     + (u.get("cache_read_input_tokens") or 0)
                     + (u.get("cache_creation_input_tokens") or 0))
            break
except Exception:
    total = 0
print(total)
PY
)"
ctx="$(ctc_int "$ctx")"

# below SOFT: reset state so the next crossing re-arms cleanly
if [ "$ctx" -lt "$CTX_SOFT" ]; then
  rm -f "$pflag" "$nflag"
  exit 0
fi

last=0
[ -f "$pflag" ] && last="$(ctc_int "$(tr -dc '0-9' < "$pflag" 2>/dev/null)")"

# SOFT band: arm a non-blocking nudge once per crossing
if [ "$ctx" -lt "$CTX_HARD" ]; then
  if [ "$last" -lt "$CTX_SOFT" ]; then
    printf 'Context is at ~%sk tokens (SOFT). Start hunting for a safe compaction boundary soon.' "$((ctx / 1000))" > "$nflag"
    printf '%s' "$ctx" > "$pflag"
  fi
  exit 0
fi

# HARD / CRITICAL: fire on first crossing, then re-fire every +CTX_STEP growth
if [ "$last" -ge "$CTX_HARD" ] && [ "$((ctx - last))" -lt "$CTX_STEP" ]; then
  exit 0
fi
printf '%s' "$ctx" > "$pflag"

if [ "$ctx" -ge "$CTX_CRIT" ]; then
  reason="$(cat "$DIR/../share/reason-critical.txt" 2>/dev/null)"
else
  reason="$(cat "$DIR/../share/reason-hard.txt" 2>/dev/null)"
fi
reason="${reason//\{CTX\}/$((ctx / 1000))}"
ctc_emit_block "$reason"
exit 0
