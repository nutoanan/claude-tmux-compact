# Configuration

Everything is configured through environment variables with sensible defaults
(set in `lib/common.sh`). Override them by exporting in your shell rc, or per-hook
in `settings.json` (e.g. `CTX_HARD=180000 bash /path/hooks/context-guard.sh stop`).

## Context thresholds (tokens)

| Variable | Default | Meaning |
| --- | --- | --- |
| `CTX_SOFT` | `130000` | Arm a non-blocking nudge (shown at the next prompt). |
| `CTX_HARD` | `160000` | Force a Worth-It checkpoint (`Stop` block). |
| `CTX_CRIT` | `200000` | Classify-the-boundary checkpoint (`Stop` block). |
| `CTX_STEP` | `25000` | Re-fire the block every +this many tokens of growth. |

These are measured as `input_tokens + cache_read_input_tokens +
cache_creation_input_tokens` of the last assistant turn. The effective window the
in-app meter calls "100%" is ~200k, which is why CRITICAL sits there — even on a
1M-token model, quality degrades past that line, so the defaults hold context
well under it. Raise them if you genuinely want to use more of the window.

## Paths

| Variable | Default | Meaning |
| --- | --- | --- |
| `CTC_HOME` | `~/.cache/claude-tmux-compact` | Base dir for state + logs. |
| `CTC_FLAG_DIR` | `$CTC_HOME/flags` | Flag and marker files (per pane). |
| `CTC_LOG` | `$CTC_HOME/compaction-log.jsonl` | JSONL audit log. |
| `CTC_LOG_MAX` | `500` | Max log rows (older rows trimmed). |
| `CTC_STATE` | `<cwd>/.claude/resume.md` | Resume file injected after compaction. |
| `CTC_STATE_MAX` | `4000` | Max chars of the resume file injected. |

## Timings (seconds)

| Variable | Default | Meaning |
| --- | --- | --- |
| `CTC_FLAG_TTL` | `180` | A queued compact older than this is discarded (stale). |
| `CTC_CONTINUE_TTL` | `600` | An auto-continue marker older than this is ignored. |
| `CTC_SETTLE` | `4` | Wait before sending the auto-continue prompt. |

## Common tweaks

**Use more of the window** (compact later):

```bash
export CTX_SOFT=180000 CTX_HARD=220000 CTX_CRIT=280000
```

**Disable auto-continue by default** — pass `no-continue` when triggering:

```bash
request-compact.sh "wrap up and stop here" no-continue
```

**Project-specific resume file:**

```bash
export CTC_STATE="$PWD/NOTES/next.md"
```

**Slower terminal / large session** — give the prompt more time to settle before
auto-continue:

```bash
export CTC_SETTLE=8
```
