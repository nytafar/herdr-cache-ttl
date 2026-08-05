#!/usr/bin/env bash
# Event hook: pane.closed
# Clean up timer state for closed panes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
[[ -z "$event_json" ]] && exit 0

pane_id=$(printf '%s' "$event_json" | jq -r '.data.pane_id // empty')
[[ -z "$pane_id" ]] && exit 0

[[ -f "$TIMERS_FILE" ]] || exit 0

atomic_jq "$TIMERS_FILE" --arg pid "$pane_id" 'del(.[$pid])'

if [[ -f "$NOTIFIED_FILE" ]]; then
    atomic_jq "$NOTIFIED_FILE" --arg pid "$pane_id" 'del(.[$pid])'
fi
