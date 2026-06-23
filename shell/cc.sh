# claude-tmux-compact — shell launcher.
# Self-compaction only works when Claude Code runs INSIDE tmux (the hooks drive
# `/compact` and the auto-continue via `tmux send-keys`). This wrapper guarantees
# that. Source it from your ~/.zshrc or ~/.bashrc:
#
#   source /path/to/claude-tmux-compact/shell/cc.sh
#
# Then launch Claude Code with:  cc [args...]
cc() {
  # already inside tmux — just run claude
  if [ -n "${TMUX:-}" ]; then
    command claude "$@"
    return $?
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    echo "cc: tmux not installed — running claude without self-compaction" >&2
    command claude "$@"
    return $?
  fi
  # create (or attach to) a dedicated tmux session running claude
  local session="claude-$$"
  tmux new-session -A -s "$session" "claude $*"
}
