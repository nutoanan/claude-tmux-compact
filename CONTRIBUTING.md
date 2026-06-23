# Contributing

Thanks for your interest! This is a small, focused toolkit — contributions that
keep it simple and dependency-light are very welcome.

## Ground rules

- **No new runtime dependencies.** bash + tmux + python3 (stdlib only). If you
  need JSON, use the helpers in `lib/common.sh`.
- **Hooks must fail safe.** Any parse/IO error exits 0 — a hook must never break a
  turn. `log-compaction.sh` (PreCompact) must *always* exit 0.
- **The model decides; hooks act.** Don't add anything that compacts on its own.
- **Portability.** Target macOS bash 3.2 and Linux bash. Use the BSD/GNU
  fallbacks already in `lib/common.sh` (`ctc_mtime`, etc.).

## Developing

1. `./install.sh` and point a `~/.claude/settings.json` at your working copy.
2. Run Claude under `cc` and watch the log:
   `tail -f ~/.cache/claude-tmux-compact/compaction-log.jsonl`.
3. For isolated tests, set `CTC_FLAG_DIR` / `CTC_LOG` to a temp dir and feed a
   script its JSON payload on stdin, e.g.:

   ```bash
   echo '{"transcript_path":"/tmp/t.jsonl","session_id":"x"}' \
     | CTX_HARD=10 bash hooks/context-guard.sh stop
   ```

## Style

- Shell: 2-space indent, `set -u` in entry scripts, quote expansions.
- Keep functions in `lib/common.sh` rather than duplicating across hooks.
- Run `shellcheck` if you have it; fix what's reasonable.

## Pull requests

- One focused change per PR. Update the relevant doc and `CHANGELOG.md`.
- Describe how you verified the behavior (log lines, a smoke test).
