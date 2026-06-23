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

`install.sh` is non-destructive. It:

- checks `tmux` / `python3` / `bash`,
- makes `bin/` and `hooks/` scripts executable,
- creates the state dir (`~/.cache/claude-tmux-compact/flags`),
- writes `examples/settings.generated.json` with this repo's absolute path
  already filled in.

## 3. Register the hooks

Open `examples/settings.generated.json` and merge its `hooks` block into
`~/.claude/settings.json`.

If you have no hooks yet, you can copy the whole `hooks` object. If you already
have some, **combine the arrays** per event — e.g. append this repo's two `Stop`
entries to your existing `Stop[0].hooks` array. Order matters for `Stop`:
`context-guard.sh` must come **before** `fire-compact.sh`.

Minimal result inside `~/.claude/settings.json`:

```jsonc
{
  "hooks": {
    "SessionStart": [
      { "matcher": "compact",
        "hooks": [ { "type": "command", "command": "bash /abs/path/hooks/rehydrate.sh" } ] }
    ],
    "Stop": [
      { "hooks": [
          { "type": "command", "command": "bash /abs/path/hooks/context-guard.sh stop" },
          { "type": "command", "command": "bash /abs/path/hooks/fire-compact.sh" }
      ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash /abs/path/hooks/context-guard.sh prompt" } ] }
    ],
    "PreCompact":  [ /* manual + auto -> log-compaction.sh pre  ... */ ],
    "PostCompact": [ /* manual + auto -> log-compaction.sh post ... */ ]
  }
}
```

(The full PreCompact/PostCompact entries are in the generated file.)

## 4. Launch Claude inside tmux

Add to `~/.zshrc` or `~/.bashrc`:

```bash
source /abs/path/claude-tmux-compact/shell/cc.sh
```

Reload your shell, then start Claude with:

```bash
cc
```

Self-compaction **only works inside tmux** — `cc` guarantees that.

## 5. Teach the model when/how to compact

The hooks provide the *mechanism*; the *policy* lives in your `~/.claude/CLAUDE.md`.
Copy the rules from [RULES.md](RULES.md) there, and make sure the model knows the
trigger path:

```
/abs/path/claude-tmux-compact/bin/request-compact.sh "<state + next action>"
```

(Optionally add `bin/` to your `PATH` so it's just `request-compact.sh`.)

## 6. (Optional) resume file

Maintain `<project>/.claude/resume.md` (see `examples/resume.md`). After every
compaction, `rehydrate.sh` injects it as context. Override the path with
`CTC_STATE`.

## 7. Verify

```bash
# watch the audit log while you work
tail -f ~/.cache/claude-tmux-compact/compaction-log.jsonl
```

Run a quick smoke test:

```bash
# from inside a `cc` session, in another pane:
/abs/path/bin/request-compact.sh "smoke test - keep this"
# end the current turn in Claude; the Stop hook should fire /compact.
```

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if nothing happens.
