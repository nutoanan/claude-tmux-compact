# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

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
