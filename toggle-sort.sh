#!/usr/bin/env bash
# Action: toggle cache sort view on/off. Clearing restores the native sort.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

SOCKET="${HERDR_SOCKET:-${HOME}/.config/herdr/herdr.sock}"
SORT_STATE_FILE="${STATE_DIR}/sort_active"

if [[ -f "$SORT_STATE_FILE" ]]; then
    printf '{"id":"off","method":"agent.view.clear","params":{"source":"plugin:cache-ttl"}}\n' \
        | nc -U "$SOCKET" 2>/dev/null || true
    rm -f "$SORT_STATE_FILE"
    echo "Cache sort off"
else
    printf '{"id":"on","method":"agent.view.set","params":{"source":"plugin:cache-ttl","label":"cache","sort":[{"field":{"token":"cache_sort"},"order":"desc"},{"field":"attention","order":"desc"},{"field":"state_change_seq","order":"desc"}]}}\n' \
        | nc -U "$SOCKET" 2>/dev/null || true
    touch "$SORT_STATE_FILE"
    echo "Cache sort on"
fi
