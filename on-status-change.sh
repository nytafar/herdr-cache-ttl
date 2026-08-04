#!/usr/bin/env bash
# Event hook: pane.agent_status_changed
# Stamps the current time as "last turn" when an agent completes a turn.
# Conservative: only stamp on transitions that prove API activity happened.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_user_config

event_json="${HERDR_PLUGIN_EVENT_JSON:-}"
[[ -z "$event_json" ]] && exit 0

pane_id=$(printf '%s' "$event_json" | jq -r '.data.pane_id // empty')
agent_status=$(printf '%s' "$event_json" | jq -r '.data.agent_status // empty')

[[ -z "$pane_id" ]] && exit 0
[[ -z "$agent_status" ]] && exit 0

# Get agent type from event data, fall back to plugin context
agent=$(printf '%s' "$event_json" | jq -r '.data.agent // empty')
if [[ -z "$agent" ]]; then
    context_json="${HERDR_PLUGIN_CONTEXT_JSON:-}"
    if [[ -n "$context_json" ]]; then
        agent=$(printf '%s' "$context_json" | jq -r '.focused_pane_agent // empty')
    fi
fi

# MVP: only track configured agent types
if [[ -n "$agent" ]]; then
    tracked=false
    for a in $TRACKED_AGENTS; do
        [[ "$agent" == "$a" ]] && tracked=true && break
    done
    $tracked || exit 0
fi

# Conservative cache invalidation:
# The prompt cache TTL resets on every API call. The observable signal
# is agent status transitions — any transition involving "working"
# proves the model API was called.
#
# We stamp on ALL status transitions because:
# - working: a turn is in progress right now (API active)
# - idle/done: a turn just finished (API was active moments ago)
# - blocked: agent hit a permission prompt (API was active to get here)
#
# This is slightly aggressive — an idle→idle transition wouldn't mean
# anything, but herdr only fires status_changed on actual transitions.

now=$(date +%s)

mkdir -p "$STATE_DIR"
[[ -f "$TIMERS_FILE" ]] || printf '{}' > "$TIMERS_FILE"

tmp_file="${TIMERS_FILE}.tmp.$$"
jq --arg pid "$pane_id" \
   --argjson ts "$now" \
   --argjson ttl "$DEFAULT_TTL_SECONDS" \
   '.[$pid] = { last_turn: $ts, ttl_seconds: $ttl }' \
   "$TIMERS_FILE" > "$tmp_file" && mv "$tmp_file" "$TIMERS_FILE"

# Clear notification state for this pane (countdown was reset)
if [[ -f "$NOTIFIED_FILE" ]]; then
    tmp_file="${NOTIFIED_FILE}.tmp.$$"
    jq --arg pid "$pane_id" 'del(.[$pid])' \
       "$NOTIFIED_FILE" > "$tmp_file" && mv "$tmp_file" "$NOTIFIED_FILE"
fi
