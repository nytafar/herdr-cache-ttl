#!/usr/bin/env bash
# Action: reset the cache TTL countdown for the focused pane.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_user_config

pane_id="${HERDR_PANE_ID:-}"
[[ -z "$pane_id" ]] && { echo "No pane in context"; exit 1; }

now=$(date +%s)

mkdir -p "$STATE_DIR"
[[ -f "$TIMERS_FILE" ]] || printf '{}' > "$TIMERS_FILE"

atomic_jq "$TIMERS_FILE" \
    --arg pid "$pane_id" \
    --argjson ts "$now" \
    --argjson ttl "$DEFAULT_TTL_SECONDS" \
    '.[$pid] = { last_turn: $ts, ttl_seconds: $ttl }'

# Clear notification state
if [[ -f "$NOTIFIED_FILE" ]]; then
    atomic_jq "$NOTIFIED_FILE" --arg pid "$pane_id" 'del(.[$pid])'
fi

echo "Timer reset for ${pane_id}"
