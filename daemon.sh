#!/usr/bin/env bash
# Cache TTL countdown daemon.
# Launched by [[startup]], runs for the lifetime of the herdr server.
# Ticks every TICK_INTERVAL seconds, computes remaining cache time for
# each tracked pane, and pushes the countdown into sidebar tokens via
# pane.report_metadata.
#
# Uses three tokens for color-coded display:
#   cache_ok   (green)  — plenty of time
#   cache_warn (amber)  — getting low
#   cache_crit (red)    — critical or expired

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_user_config

mkdir -p "$STATE_DIR"
[[ -f "$TIMERS_FILE" ]] || printf '{}' > "$TIMERS_FILE"
[[ -f "$NOTIFIED_FILE" ]] || printf '{}' > "$NOTIFIED_FILE"

printf '%s' "$$" > "$PID_FILE"

CLEANUP_INTERVAL=10
tick_count=0
consecutive_failures=0

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

format_remaining() {
    local remaining=$1
    if (( remaining <= 0 )); then
        printf '0m'
    elif (( remaining <= SECONDS_DISPLAY_THRESHOLD )); then
        local mins=$(( remaining / 60 ))
        local secs=$(( remaining % 60 ))
        printf '%d:%02d' "$mins" "$secs"
    else
        local mins=$(( remaining / 60 ))
        printf '%dm' "$mins"
    fi
}

set_pane_tokens() {
    local pane_id=$1
    local remaining=$2
    local label
    label=$(format_remaining "$remaining")

    local args=("$pane_id" --source "$METADATA_SOURCE" --ttl-ms "$TOKEN_TTL_MS")

    if (( remaining <= CRIT_AT )); then
        args+=(--token "cache_crit=${label}" --clear-token cache_ok --clear-token cache_warn)
    elif (( remaining <= WARN_AT )); then
        args+=(--token "cache_warn=${label}" --clear-token cache_ok --clear-token cache_crit)
    else
        args+=(--token "cache_ok=${label}" --clear-token cache_warn --clear-token cache_crit)
    fi

    if herdr pane report-metadata "${args[@]}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_notification_threshold() {
    local pane_id=$1
    local remaining=$2

    [[ -f "$NOTIFIED_FILE" ]] || printf '{}' > "$NOTIFIED_FILE"
    local notified
    notified=$(jq -r --arg pid "$pane_id" '.[$pid] // "[]"' "$NOTIFIED_FILE" 2>/dev/null) || return 0
    [[ "$notified" == "null" ]] && notified="[]"

    for threshold in "${WARN_THRESHOLDS[@]}"; do
        if (( remaining <= threshold && remaining > 0 )); then
            local already
            already=$(printf '%s' "$notified" | jq --argjson t "$threshold" 'map(select(. == $t)) | length' 2>/dev/null) || return 0
            if [[ "$already" == "0" ]]; then
                local label
                label=$(format_remaining "$threshold")
                local title
                title=$(herdr agent get "$pane_id" 2>/dev/null | jq -r '.result.agent.terminal_title_stripped // empty' 2>/dev/null) || true
                [[ -z "$title" ]] && title="$pane_id"

                herdr notification show "Cache expires in ${label}" \
                    --body "$title" \
                    --sound request \
                    2>/dev/null || true

                local tmp_file="${NOTIFIED_FILE}.tmp.$$"
                if jq --arg pid "$pane_id" --argjson t "$threshold" \
                   '.[$pid] = ((.[$pid] // []) + [$t])' \
                   "$NOTIFIED_FILE" > "$tmp_file" 2>/dev/null; then
                    mv "$tmp_file" "$NOTIFIED_FILE"
                else
                    rm -f "$tmp_file"
                fi
            fi
            break
        fi
    done
}

prune_stale_panes() {
    local active_panes
    active_panes=$(herdr agent list 2>/dev/null | jq -r '.result.agents[]?.pane_id // empty' 2>/dev/null) || return 0
    [[ -z "$active_panes" ]] && return 0

    local timers
    timers=$(cat "$TIMERS_FILE" 2>/dev/null) || return 0

    local stale_ids=()
    while IFS= read -r pane_id; do
        [[ -z "$pane_id" ]] && continue
        if ! printf '%s\n' "$active_panes" | grep -qF "$pane_id"; then
            stale_ids+=("$pane_id")
        fi
    done < <(printf '%s' "$timers" | jq -r 'keys[]' 2>/dev/null)

    if (( ${#stale_ids[@]} == 0 )); then return 0; fi
    for pane_id in "${stale_ids[@]}"; do
        local tmp_file="${TIMERS_FILE}.tmp.$$"
        if jq --arg pid "$pane_id" 'del(.[$pid])' "$TIMERS_FILE" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$TIMERS_FILE"
        else
            rm -f "$tmp_file"
        fi
    done
}

log "daemon started, pid=$$, tick=${TICK_INTERVAL}s"

while true; do
    sleep "$TICK_INTERVAL"
    tick_count=$(( tick_count + 1 ))

    [[ -f "$TIMERS_FILE" ]] || continue
    timers=$(cat "$TIMERS_FILE" 2>/dev/null) || continue
    [[ "$timers" == "{}" ]] && continue

    now=$(date +%s)

    if (( tick_count % CLEANUP_INTERVAL == 0 )); then
        prune_stale_panes
        timers=$(cat "$TIMERS_FILE" 2>/dev/null) || continue
    fi

    updated=0
    failed=0
    while IFS= read -r pane_id; do
        [[ -z "$pane_id" ]] && continue

        last_turn=$(printf '%s' "$timers" | jq -r --arg pid "$pane_id" '.[$pid].last_turn // 0' 2>/dev/null) || continue
        ttl=$(printf '%s' "$timers" | jq -r --arg pid "$pane_id" '.[$pid].ttl_seconds // 3600' 2>/dev/null) || continue

        elapsed=$(( now - last_turn ))
        remaining=$(( ttl - elapsed ))

        if set_pane_tokens "$pane_id" "$remaining"; then
            updated=$(( updated + 1 ))
        else
            failed=$(( failed + 1 ))
        fi

        check_notification_threshold "$pane_id" "$remaining"

    done < <(printf '%s' "$timers" | jq -r 'keys[]' 2>/dev/null)

    if (( failed > 0 && updated == 0 )); then
        consecutive_failures=$(( consecutive_failures + 1 ))
        if (( consecutive_failures >= 3 )); then
            log "all updates failing (${consecutive_failures} consecutive), backing off"
            sleep 60
        fi
    else
        consecutive_failures=0
    fi
done
