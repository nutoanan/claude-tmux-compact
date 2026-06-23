#!/usr/bin/env bash
# PreCompact / PostCompact audit logger. Writes one JSONL row per event so you
# can verify the system fired at the right moments (and tune thresholds).
#
# Usage: log-compaction.sh <pre|post> <manual|auto>
#
# IMPORTANT: PreCompact is a BLOCKING hook — a non-zero exit ABORTS the
# compaction. This script must always exit 0.
#
# Registered in settings.json under PreCompact and PostCompact (manual + auto).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

phase="${1:-pre}"
trigger="${2:-unknown}"
payload="$(ctc_read_payload)"

sid="$(ctc_json_field "$payload" session_id)"
cwd="$(ctc_json_field "$payload" cwd)"

ctc_log "{\"ts\":\"$(date -u +%FT%TZ)\",\"event\":\"compaction\",\"phase\":\"$phase\",\"trigger\":\"$trigger\",\"session_id\":\"$sid\",\"cwd\":\"$cwd\"}"
exit 0
