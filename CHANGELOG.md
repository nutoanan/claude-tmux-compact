# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- `install.sh` is now a **one-shot installer**: it merges the hooks into
  `~/.claude/settings.json`, `@imports` the generated policy from
  `~/.claude/CLAUDE.md`, and sources `shell/cc.sh` from the shell rc — each edit
  idempotent + marked, with a timestamped backup of every touched file. The old
  non-destructive "generate + print steps" behaviour is preserved under
  `install.sh --print`.

### Added
- Model-facing policy file (`share/compaction-policy.md`) resolved at install
  time to `compaction-policy.generated.md` and loaded via a CLAUDE.md `@import`,
  so the policy is no longer hand-pasted and can't silently drift out.
- Loud-fail guard in every hook + `request-compact.sh`: a missing
  `lib/common.sh` now prints a clear error instead of silently no-op'ing (the
  "copied only the hooks/ dir" pitfall).

### Fixed
- Onboarding gap where merging only the `hooks` block (without the policy) left
  the model never calling the trigger — "it doesn't compact by itself". The
  one-shot installer wires both halves.

## [1.0.0] - 2026-06-24

### Added
- Model-side compaction trigger (`bin/request-compact.sh`) with auto-continue
  marker (opt-out via `no-continue`).
- Mechanical context-pressure floor (`hooks/context-guard.sh`) with SOFT/HARD/
  CRITICAL tiers, re-fire every `+CTX_STEP`, and a non-blocking prompt nudge.
- Stop-hook compaction firing via `tmux send-keys` (`hooks/fire-compact.sh`)
  with stale-flag TTL, consume-first, and safe literal send.
- Post-compaction re-injection + auto-continue (`hooks/rehydrate.sh`) on
  `SessionStart(source=compact)`.
- Pre/PostCompact JSONL audit logging (`hooks/log-compaction.sh`).
- Shared library (`lib/common.sh`): tty→pane resolution, portable mtime, JSON
  helpers, capped logger.
- tmux launcher (`shell/cc.sh`), settings template, example resume file,
  non-destructive `install.sh`.
- Documentation: README + INSTALL, ARCHITECTURE, CONFIGURATION, RULES,
  TROUBLESHOOTING.
- Portable end-to-end test harness (`test/e2e.sh`): 21 checks covering the
  context-guard tiers, logging, installer, and the real tmux path (pane
  resolution, `/compact` send-keys, stale-flag discard, auto-continue).
  Verified on macOS bash 3.2/5.2 + tmux.
