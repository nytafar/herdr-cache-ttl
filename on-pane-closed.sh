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

tmp_file="${TIMERS_FILE}.tmp.$$"
jq --arg pid "$pane_id" 'del(.[$pid])' \
   "$TIMERS_FILE" > "$tmp_file" && mv "$tmp_file" "$TIMERS_FILE"

if [[ -f "$NOTIFIED_FILE" ]]; then
    tmp_file="${NOTIFIED_FILE}.tmp.$$"
    jq --arg pid "$pane_id" 'del(.[$pid])' \
       "$NOTIFIED_FILE" > "$tmp_file" && mv "$tmp_file" "$NOTIFIED_FILE"
fi
