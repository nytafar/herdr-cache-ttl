#!/usr/bin/env bash
# Action: print all active cache TTL timers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_user_config

[[ -f "$TIMERS_FILE" ]] || { echo "No active timers"; exit 0; }

timers=$(cat "$TIMERS_FILE" 2>/dev/null) || { echo "No active timers"; exit 0; }
[[ "$timers" == "{}" ]] && { echo "No active timers"; exit 0; }

now=$(date +%s)

printf '%-12s  %-8s  %s\n' "PANE" "TTL" "TITLE"
printf '%-12s  %-8s  %s\n' "----" "---" "-----"

while IFS= read -r pane_id; do
    [[ -z "$pane_id" ]] && continue

    last_turn=$(printf '%s' "$timers" | jq -r --arg pid "$pane_id" '.[$pid].last_turn // 0')
    ttl=$(printf '%s' "$timers" | jq -r --arg pid "$pane_id" '.[$pid].ttl_seconds // 3600')

    elapsed=$(( now - last_turn ))
    remaining=$(( ttl - elapsed ))

    if (( remaining <= 0 )); then
        label="expired"
    elif (( remaining <= 300 )); then
        mins=$(( remaining / 60 ))
        secs=$(( remaining % 60 ))
        label=$(printf '%d:%02d' "$mins" "$secs")
    else
        mins=$(( remaining / 60 ))
        label="${mins}m"
    fi

    title=$(herdr agent get "$pane_id" 2>/dev/null | jq -r '.result.agent.terminal_title_stripped // ""' 2>/dev/null || true)
    [[ -z "$title" ]] && title="(unknown)"

    printf '%-12s  %-8s  %s\n' "$pane_id" "$label" "$title"
done < <(printf '%s' "$timers" | jq -r 'keys[]')
