#!/usr/bin/env bash
# Shared configuration — sourced by all plugin scripts.

DEFAULT_TTL_SECONDS=3600   # 60 minutes
TICK_INTERVAL=15           # seconds between countdown updates
SECONDS_DISPLAY_THRESHOLD=300  # show m:ss below 5 minutes

# Color tier thresholds (seconds remaining)
WARN_AT=600    # amber below 10 minutes
CRIT_AT=300    # red below 5 minutes

# Notification thresholds in seconds remaining (descending order)
WARN_THRESHOLDS=(600 300 60)

# Token auto-expiry — if the daemon dies, tokens self-clear after this many ms
TOKEN_TTL_MS=45000

# Source identifier for report-metadata sequencing
METADATA_SOURCE="plugin:cache-ttl"

# Only track these agent types in MVP
TRACKED_AGENTS="claude"

# Paths (set by herdr runtime env)
STATE_DIR="${HERDR_PLUGIN_STATE_DIR:?}"
CONFIG_DIR="${HERDR_PLUGIN_CONFIG_DIR:?}"
TIMERS_FILE="${STATE_DIR}/timers.json"
NOTIFIED_FILE="${STATE_DIR}/notified.json"
PID_FILE="${STATE_DIR}/daemon.pid"

# Locking — serializes read-modify-write on shared JSON state
_LOCK_DIR="${STATE_DIR}/.state_lock"

acquire_lock() {
    local attempts=0
    while ! mkdir "$_LOCK_DIR" 2>/dev/null; do
        attempts=$((attempts + 1))
        if (( attempts > 50 )); then
            rm -rf "$_LOCK_DIR"
            mkdir "$_LOCK_DIR" 2>/dev/null || return 1
            return 0
        fi
        sleep 0.1
    done
}

release_lock() {
    rm -rf "$_LOCK_DIR" 2>/dev/null || true
}

# Atomically read-modify-write a JSON file under lock.
# Usage: atomic_jq <file> [jq-args...] <jq-filter>
atomic_jq() {
    local file=$1; shift
    local tmp_file="${file}.tmp.$$"
    acquire_lock
    if jq "$@" "$file" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$file"
        release_lock
        return 0
    else
        rm -f "$tmp_file"
        release_lock
        return 1
    fi
}

# User config overlay
USER_CONFIG="${CONFIG_DIR}/config.json"

_validate_positive_int() {
    local name=$1 val=$2
    if ! [[ "$val" =~ ^[0-9]+$ ]] || (( val <= 0 )); then
        printf 'config: ignoring invalid %s=%s (must be a positive integer)\n' "$name" "$val" >&2
        return 1
    fi
}

load_user_config() {
    if [[ -f "$USER_CONFIG" ]]; then
        local val
        val=$(jq -r '.ttl_seconds // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && _validate_positive_int ttl_seconds "$val" && DEFAULT_TTL_SECONDS="$val"
        val=$(jq -r '.tick_interval // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && _validate_positive_int tick_interval "$val" && TICK_INTERVAL="$val"
        val=$(jq -r '.seconds_threshold // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && _validate_positive_int seconds_threshold "$val" && SECONDS_DISPLAY_THRESHOLD="$val"
        val=$(jq -r '.warn_at // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && _validate_positive_int warn_at "$val" && WARN_AT="$val"
        val=$(jq -r '.crit_at // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && _validate_positive_int crit_at "$val" && CRIT_AT="$val"
    fi
}
