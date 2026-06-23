#!/usr/bin/env bash
# claude-tmux-compact installer.
# Non-destructive: checks prerequisites, makes scripts executable, creates the
# state dir, and generates a ready-to-merge settings snippet. It does NOT touch
# your ~/.claude/settings.json automatically — you merge the hooks block yourself
# (see the printed instructions).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTC_HOME_DEFAULT="${CTC_HOME:-$HOME/.cache/claude-tmux-compact}"

say() { printf '%s\n' "$*"; }
bar() { printf '%s\n' "------------------------------------------------------------"; }

bar; say "claude-tmux-compact installer"; say "repo: $REPO"; bar

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

# 4) generate the settings snippet with the real absolute path
gen="$REPO/examples/settings.generated.json"
sed "s|REPO_DIR|$REPO|g" "$REPO/examples/settings.json" > "$gen"
say "  wrote merge-ready hooks: $gen"

bar
say "NEXT STEPS"
say "  1) Merge the \"hooks\" block from:"
say "       $gen"
say "     into your ~/.claude/settings.json (combine arrays if hooks already exist)."
say "  2) Add to your shell rc (~/.zshrc or ~/.bashrc):"
say "       source $REPO/shell/cc.sh"
say "     then launch Claude with:  cc"
say "  3) Tell Claude WHEN/HOW to compact. Add the rules from docs/RULES.md to"
say "     your global ~/.claude/CLAUDE.md, and reference the trigger:"
say "       $REPO/bin/request-compact.sh \"<state + next action>\""
say "  4) (optional) Maintain a resume file at <project>/.claude/resume.md"
say "     (see examples/resume.md) for richer post-compaction context."
bar
say "Verify anytime:   tail -f $CTC_HOME_DEFAULT/compaction-log.jsonl"
