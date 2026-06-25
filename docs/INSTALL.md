# Install

## 1. Prerequisites

- **tmux** — `brew install tmux` (macOS) / `apt install tmux` (Debian/Ubuntu)
- **python3** — usually preinstalled; no pip packages needed
- **Claude Code** with hooks enabled

## 2. Clone and run the installer

```bash
git clone https://github.com/nutoanan/claude-tmux-compact.git
cd claude-tmux-compact
./install.sh
```

That's it. `install.sh` is **one shot** — it wires up the whole thing, with a
timestamped backup of every file it touches and idempotent, marked edits (safe to
re-run; it updates in place instead of duplicating). It:

- checks `tmux` / `python3` / `bash` and makes the scripts executable,
- creates the state dir (`~/.cache/claude-tmux-compact/flags`),
- **merges the hooks** into `~/.claude/settings.json` (the *mechanism*),
- generates `compaction-policy.generated.md` (real trigger path baked in) and
  **`@imports` it from `~/.claude/CLAUDE.md`** (the *policy*),
- **sources `shell/cc.sh`** from your `~/.zshrc` / `~/.bashrc` (the tmux launcher).

Then open a new terminal (or `source ~/.zshrc`) and launch Claude with:

```bash
cc
```

Self-compaction **only works inside tmux** — `cc` guarantees that.

### Why both halves are installed

The hooks are the *mechanism* (the hand that presses `/compact`); the policy is
*when/how* the model decides to compact. **Installing only the hooks does
nothing** — the model never calls the trigger, so the Stop hook has no flag to
fire. The one-shot installer wires both, which is why dropping just the `hooks`
block into `settings.json` used to look like "it doesn't compact by itself."

## 3. Dry run / manual install

Prefer to wire it yourself? Run:

```bash
./install.sh --print
```

Nothing is modified. It only generates the resolved snippets
(`examples/settings.generated.json` + `compaction-policy.generated.md`) and prints
the three manual steps:

1. merge the `hooks` block from `examples/settings.generated.json` into
   `~/.claude/settings.json` (combine arrays per event; for `Stop`,
   `context-guard.sh` must come **before** `fire-compact.sh`),
2. add `@/abs/path/compaction-policy.generated.md` to `~/.claude/CLAUDE.md`,
3. add `source /abs/path/shell/cc.sh` to your shell rc, then launch with `cc`.

The human-readable policy (with the *why* behind each rule, EN + TH) lives in
[RULES.md](RULES.md); the model-facing version is `share/compaction-policy.md`.

## 4. (Optional) resume file

Maintain `<project>/.claude/resume.md` (see `examples/resume.md`). After every
compaction, `rehydrate.sh` injects it as context. Override the path with
`CTC_STATE`.

## 5. Verify

```bash
# watch the audit log while you work
tail -f ~/.cache/claude-tmux-compact/compaction-log.jsonl
```

Quick smoke test from inside a `cc` session (another pane):

```bash
bash /abs/path/bin/request-compact.sh "smoke test - keep this"
# end the current turn in Claude; the Stop hook should fire /compact.
```

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if nothing happens.

## Uninstall

Delete the marked blocks (`claude-tmux-compact:begin … :end`) from
`~/.claude/CLAUDE.md` and your shell rc, remove this repo's hook groups from
`~/.claude/settings.json`, and `rm -rf ~/.cache/claude-tmux-compact`. Backups
from each run are kept as `<file>.ctc-bak.<epoch>`.
