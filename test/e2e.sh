#!/usr/bin/env bash
# End-to-end test harness for claude-tmux-compact.
# Isolated: temp CTC_HOME, throwaway tmux session. Touches nothing real.
set -u
# repo root, auto-detected relative to this script (test/e2e.sh -> repo root)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$(mktemp -d)/ctc"; mkdir -p "$H/flags"
export CTC_HOME="$H" CTC_SETTLE=1 CTC_FLAG_TTL=180
SESS="ctctest_$$"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1  -- $2"; }
hr(){ echo "------------------------------------------------------------"; }

hr; echo "A. STATIC / UNIT (no tmux)"; hr

# A1 syntax
synfail=0
for f in "$REPO"/lib/common.sh "$REPO"/bin/*.sh "$REPO"/hooks/*.sh "$REPO"/shell/cc.sh "$REPO"/install.sh; do
  bash -n "$f" || synfail=1
done
[ "$synfail" -eq 0 ] && ok "all scripts parse" || no "syntax" "see above"

# A2 context-guard CRITICAL blocks
mku(){ printf '{"type":"assistant","message":{"usage":{"input_tokens":0,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' "$1" > "$H/t.jsonl"; }
guard(){ echo "{\"transcript_path\":\"$H/t.jsonl\",\"session_id\":\"s\",\"stop_hook_active\":false}" | bash "$REPO/hooks/context-guard.sh" stop; }
rm -f "$H/flags/"*; mku 210000
o="$(guard 2>/tmp/cg.err)"
echo "$o" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("decision")=="block" and "CRITICAL" in d.get("reason","") else 1)' \
  && ok "CRITICAL -> block (valid JSON)" || no "CRITICAL block" "out=$o"
[ -s /tmp/cg.err ] && no "CRITICAL no stderr leak" "$(cat /tmp/cg.err)" || ok "no stderr leak on first write"

# A3 re-fire suppression then +STEP refire
rm -f "$H/flags/"*; mku 210000; guard >/dev/null
out2="$(mku 210000; guard)"; [ -z "$out2" ] && ok "no re-fire under +STEP" || no "re-fire suppression" "got output"
mku 240000; guard | grep -q block && ok "re-fire after +30k" || no "re-fire +STEP" "no block"

# A4 SOFT nudge -> prompt surfaces
rm -f "$H/flags/"*; mku 135000; s="$(guard)"; [ -z "$s" ] && ok "SOFT no block" || no "SOFT" "blocked"
echo '{"session_id":"s"}' | bash "$REPO/hooks/context-guard.sh" prompt | grep -q SOFT && ok "SOFT nudge surfaced at prompt" || no "nudge surface" "missing"

# A5 below SOFT clears
mku 50000; guard >/dev/null; ls "$H/flags" 2>/dev/null | grep -q . && no "below-SOFT clears" "flags remain" || ok "below-SOFT clears state"

# A6 log-compaction exits 0 + row
echo '{"session_id":"x","cwd":"/p"}' | bash "$REPO/hooks/log-compaction.sh" pre manual; rc=$?
[ "$rc" -eq 0 ] && tail -1 "$H/compaction-log.jsonl" | grep -q '"phase":"pre"' && ok "log pre exit0 + row" || no "log" "rc=$rc"

# A7 request-compact non-tmux fallback
env -u TMUX -u CTC_HOME bash "$REPO/bin/request-compact.sh" "x" >/tmp/rc.out 2>&1; rc=$?
[ "$rc" -eq 1 ] && grep -q '/compact x' /tmp/rc.out && ok "non-tmux fallback (exit1 + paste block)" || no "fallback" "rc=$rc"

# A8 install.sh generates valid settings (--print: never touches real ~/.claude)
( cd "$REPO" && ./install.sh --print >/dev/null 2>&1 )
python3 -m json.tool "$REPO/examples/settings.generated.json" >/dev/null 2>&1 && ! grep -q REPO_DIR "$REPO/examples/settings.generated.json" && ok "install: valid settings, path filled" || no "install" "bad json or placeholder"

# A9 rehydrate stdout injection (resume file) - no tmux needed
printf '# next\n- do the thing\n' > "$H/resume.md"
echo "{\"cwd\":\"$H\",\"session_id\":\"s\"}" | CTC_STATE="$H/resume.md" bash "$REPO/hooks/rehydrate.sh" 2>/dev/null \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["hookSpecificOutput"]["additionalContext"])' 2>/dev/null \
  | grep -q "do the thing" && ok "rehydrate injects resume file as context" || no "rehydrate inject" "no additionalContext"

hr; echo "B. REAL TMUX (resolve pane, send-keys, auto-continue)"; hr
if ! command -v tmux >/dev/null 2>&1; then echo "  SKIP  tmux not available"; else
  tmux kill-session -t "$SESS" 2>/dev/null
  tmux new-session -d -s "$SESS" -x 220 -y 50 "bash --norc --noprofile"
  sleep 0.5
  PANE="$(tmux list-panes -t "$SESS" -F '#{pane_id}')"
  inpane(){ tmux send-keys -t "$PANE" "$1" Enter; }   # run a command inside the pane

  # B1 pane resolution from within the pane
  inpane ". $REPO/lib/common.sh; ctc_resolve_pane > $H/resolved 2>&1"
  sleep 0.6
  [ "$(cat "$H/resolved" 2>/dev/null)" = "$PANE" ] && ok "ctc_resolve_pane = $PANE" || no "pane resolve" "got '$(cat "$H/resolved" 2>/dev/null)' want $PANE"

  # B2 request-compact writes flag + continue marker (run inside pane)
  inpane "export CTC_HOME=$H; bash $REPO/bin/request-compact.sh 'KEEPTOK next=do-X'"
  sleep 0.6
  key="${PANE#%}"
  [ -f "$H/flags/$key" ] && grep -q KEEPTOK "$H/flags/$key" && ok "request-compact wrote flag" || no "flag write" "missing/empty"
  [ -f "$H/flags/$key.continue" ] && ok "request-compact wrote continue marker" || no "continue marker" "missing"

  # B3 fire-compact sends /compact into the pane + consumes flag
  inpane "echo '{}' | CTC_HOME=$H bash $REPO/hooks/fire-compact.sh"
  sleep 1.2
  cap="$(tmux capture-pane -t "$PANE" -p)"
  echo "$cap" | grep -q "/compact KEEPTOK" && ok "fire-compact typed '/compact KEEPTOK ...' into pane" || no "send-keys /compact" "capture lacks it"
  [ ! -f "$H/flags/$key" ] && ok "fire-compact consumed the flag" || no "flag consume" "flag remains"

  # B4 stale flag is discarded without firing
  printf 'STALEKEEP' > "$H/flags/$key"
  touch -t 200001010000 "$H/flags/$key"   # ancient mtime
  inpane "echo '{}' | CTC_HOME=$H bash $REPO/hooks/fire-compact.sh"
  sleep 0.8
  cap2="$(tmux capture-pane -t "$PANE" -p)"
  if echo "$cap2" | grep -q "/compact STALEKEEP"; then no "stale discard" "stale flag fired"; else ok "stale flag NOT fired"; fi
  [ ! -f "$H/flags/$key" ] && ok "stale flag discarded" || no "stale cleanup" "remains"
  grep -q '"status":"stale-discarded"' "$H/compaction-log.jsonl" && ok "stale logged" || no "stale log" "no row"

  # B5 rehydrate auto-continue sends 'continue:' into the pane
  printf 'do-X-hint' > "$H/flags/$key.continue"
  inpane "export CTC_HOME=$H CTC_SETTLE=1; echo '{\"cwd\":\"$H\"}' | bash $REPO/hooks/rehydrate.sh >/dev/null 2>&1"
  sleep 3
  cap3="$(tmux capture-pane -t "$PANE" -p)"
  echo "$cap3" | grep -q "continue: do-X-hint" && ok "rehydrate auto-typed 'continue: ...' into pane" || no "auto-continue" "capture lacks 'continue:'"

  tmux kill-session -t "$SESS" 2>/dev/null
fi

hr; echo "RESULT: PASS=$PASS  FAIL=$FAIL"; hr
rm -rf "$(dirname "$H")"
[ "$FAIL" -eq 0 ]