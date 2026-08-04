#!/usr/bin/env bash
# Shared configuration — sourced by all plugin scripts.

DEFAULT_TTL_SECONDS=3600   # 60 minutes
TICK_INTERVAL=15           # seconds between countdown updates
SECONDS_DISPLAY_THRESHOLD=300  # show m:ss below 5 minutes

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

# User config overlay
USER_CONFIG="${CONFIG_DIR}/config.json"

load_user_config() {
    if [[ -f "$USER_CONFIG" ]]; then
        local val
        val=$(jq -r '.ttl_seconds // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && DEFAULT_TTL_SECONDS="$val"
        val=$(jq -r '.tick_interval // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && TICK_INTERVAL="$val"
        val=$(jq -r '.seconds_threshold // empty' "$USER_CONFIG" 2>/dev/null)
        [[ -n "$val" ]] && SECONDS_DISPLAY_THRESHOLD="$val"
    fi
}
