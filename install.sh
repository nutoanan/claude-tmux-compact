#!/usr/bin/env bash
# claude-tmux-compact installer — one shot, idempotent, reversible.
#
# By default it wires up EVERYTHING:
#   - merges the hooks into ~/.claude/settings.json   (mechanism)
#   - generates a resolved policy file and @imports it from ~/.claude/CLAUDE.md  (policy)
#   - sources shell/cc.sh from your shell rc          (tmux launcher)
# Every file it touches is backed up first (<file>.ctc-bak.<epoch>), and every
# edit is idempotent + marked, so re-running updates in place (never duplicates)
# and an uninstall is a clean delete of the marked block.
#
# Flags:
#   --print     don't modify anything; just generate the snippets and print steps
#   --help      this help
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTC_HOME_DEFAULT="${CTC_HOME:-$HOME/.cache/claude-tmux-compact}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
POLICY_SRC="$REPO/share/compaction-policy.md"
POLICY_GEN="$REPO/compaction-policy.generated.md"
REQUEST_CMD="bash $REPO/bin/request-compact.sh"

MODE="install"
case "${1:-}" in
  --print) MODE="print" ;;
  --help|-h) sed -n '2,18p' "$0"; exit 0 ;;
  "") ;;
  *) echo "unknown arg: $1 (use --help)"; exit 2 ;;
esac

say() { printf '%s\n' "$*"; }
bar() { printf '%s\n' "------------------------------------------------------------"; }

bar; say "claude-tmux-compact installer ($MODE)"; say "repo: $REPO"; bar

# 1) prerequisites
miss=0
for d in tmux python3 bash; do
  if command -v "$d" >/dev/null 2>&1; then
    say "  ok    $d -> $(command -v "$d")"
  else
    say "  MISS  $d  (required)"; miss=1
  fi
done
[ "$miss" -eq 0 ] || say "  WARNING: install the missing tools above before using."

# 2) make scripts executable
chmod +x "$REPO"/bin/*.sh "$REPO"/hooks/*.sh 2>/dev/null || true
say "  made bin/ and hooks/ scripts executable"

# 3) create state dir
mkdir -p "$CTC_HOME_DEFAULT/flags"
say "  created state dir: $CTC_HOME_DEFAULT/flags"

# 4) generate the settings snippet (reference / --print) with the real path
gen="$REPO/examples/settings.generated.json"
sed "s|REPO_DIR|$REPO|g" "$REPO/examples/settings.json" > "$gen"
say "  wrote merge-ready hooks: $gen"

# 5) generate the resolved policy file (real request-compact path baked in)
sed "s|REQUEST_COMPACT_CMD|$REQUEST_CMD|g" "$POLICY_SRC" > "$POLICY_GEN"
say "  wrote resolved policy:   $POLICY_GEN"

# --- helpers --------------------------------------------------------------
backup() { [ -f "$1" ] && cp -p "$1" "$1.ctc-bak.$(date +%s)" && say "  backup:  $1.ctc-bak.*"; }

# merge our hook groups into settings.json (idempotent + update-safe)
merge_settings() {
  python3 - "$SETTINGS" "$REPO" <<'PY'
import sys, json, os
settings_path, repo = sys.argv[1], sys.argv[2]
def cmd(s): return {"type": "command", "command": f"bash {repo}/hooks/{s}"}
ours = {
  "SessionStart": [ {"matcher": "compact", "hooks": [cmd("rehydrate.sh")]} ],
  "Stop":         [ {"hooks": [cmd("context-guard.sh stop"), cmd("fire-compact.sh")]} ],
  "UserPromptSubmit": [ {"hooks": [cmd("context-guard.sh prompt")]} ],
  "PreCompact":  [ {"matcher": "manual", "hooks": [cmd("log-compaction.sh pre manual")]},
                   {"matcher": "auto",   "hooks": [cmd("log-compaction.sh pre auto")]} ],
  "PostCompact": [ {"matcher": "manual", "hooks": [cmd("log-compaction.sh post manual")]},
                   {"matcher": "auto",   "hooks": [cmd("log-compaction.sh post auto")]} ],
}
try:
    with open(settings_path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        print("PARSE_ERROR", file=sys.stderr); sys.exit(3)
except FileNotFoundError:
    data = {}
except Exception:
    print("PARSE_ERROR", file=sys.stderr); sys.exit(3)

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}; data["hooks"] = hooks
marker = repo + "/hooks/"
def is_ours(g):
    return isinstance(g, dict) and any(
        marker in (h.get("command", "")) for h in g.get("hooks", []) if isinstance(h, dict))
for event, groups in ours.items():
    cur = hooks.get(event)
    cur = cur if isinstance(cur, list) else []
    cur = [g for g in cur if not is_ours(g)]   # drop prior install -> idempotent
    cur.extend(groups)
    hooks[event] = cur
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
print("OK")
PY
}

# upsert a marked block into a text file (create if missing)
upsert_block() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
path, begin, end, content = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(path) as f: txt = f.read()
except FileNotFoundError:
    txt = ""
block = begin + "\n" + content.rstrip("\n") + "\n" + end + "\n"
if begin in txt and end in txt:
    pre = txt.split(begin)[0]
    post = txt.split(end, 1)[1]
    new = pre.rstrip("\n") + ("\n\n" if pre.strip() else "") + block + post.lstrip("\n")
else:
    sep = "" if (not txt or txt.endswith("\n")) else "\n"
    new = (txt + sep + ("\n" if txt.strip() else "")) + block
with open(path, "w") as f: f.write(new)
print("OK")
PY
}

if [ "$MODE" = "print" ]; then
  bar
  say "PRINT MODE — nothing was modified. To finish manually:"
  say "  1) merge the hooks block from: $gen  into  $SETTINGS"
  say "  2) add to $CLAUDE_MD :   @$POLICY_GEN"
  say "  3) add to your shell rc:  source $REPO/shell/cc.sh   (then launch with: cc)"
  bar
  exit 0
fi

# 6) merge hooks into settings.json
bar; say "WIRING (idempotent — safe to re-run)"
backup "$SETTINGS"
if merge_settings >/dev/null 2>&1; then
  say "  hooks merged -> $SETTINGS"
else
  say "  ERROR: $SETTINGS is not valid JSON — left untouched."
  say "         Fix it, or merge $gen by hand, then re-run."
fi

# 7) @import the policy from CLAUDE.md
backup "$CLAUDE_MD"
upsert_block "$CLAUDE_MD" \
  "<!-- claude-tmux-compact:begin (managed by install.sh — do not edit) -->" \
  "<!-- claude-tmux-compact:end -->" \
  "@$POLICY_GEN" >/dev/null
say "  policy @imported -> $CLAUDE_MD"

# 8) source cc.sh from the shell rc
case "${SHELL##*/}" in
  zsh)  RC="$HOME/.zshrc" ;;
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="" ;;
esac
if [ -n "$RC" ]; then
  backup "$RC"
  upsert_block "$RC" \
    "# claude-tmux-compact:begin (managed by install.sh)" \
    "# claude-tmux-compact:end" \
    "source $REPO/shell/cc.sh" >/dev/null
  say "  cc launcher sourced -> $RC"
else
  say "  NOTE: unknown shell ($SHELL) — add manually: source $REPO/shell/cc.sh"
fi

bar
say "DONE. Open a new terminal (or: source $RC), then launch Claude with:  cc"
say "Verify:  tail -f $CTC_HOME_DEFAULT/compaction-log.jsonl"
say "Uninstall: delete the marked blocks from $SETTINGS, $CLAUDE_MD, $RC (backups: *.ctc-bak.*)"
bar
