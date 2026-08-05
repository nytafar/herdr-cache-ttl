#!/usr/bin/env bash
# Deploy cache-ttl plugin to a remote herdr host.
# Usage: ./deploy.sh <ssh-target> [herdr-bin-path]
#
# Examples:
#   ./deploy.sh root@xl
#   ./deploy.sh root@asher /root/.local/bin/herdr

set -eo pipefail

TARGET="${1:?Usage: ./deploy.sh <ssh-target> [herdr-bin-path]}"
HERDR="${2:-herdr}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SIDEBAR_CONFIG='rows = [["state_icon", "workspace", "tab"], ["agent", { token = "$cache_ok", fg = "#4ade80" }, { token = "$cache_warn", fg = "#f59e0b" }, { token = "$cache_crit", fg = "#ef4444" }]]'

echo "==> Deploying cache-ttl plugin to ${TARGET}"

# 1. Install plugin from GitHub (clones into ~/.config/herdr/plugins/github/)
echo "--- Installing plugin from GitHub..."
ssh "$TARGET" "
# --yes must come AFTER the repo arg: when a server is running, the CLI
# forwards to a server-side handler that parses args positionally.
if ${HERDR} plugin install nytafar/herdr-cache-ttl --yes 2>&1; then
    echo 'installed'
elif ${HERDR} plugin list 2>&1 | grep -q cache-ttl; then
    echo 'already installed'
else
    echo 'ERROR: plugin install failed' >&2
    exit 1
fi
"

# 2. Ensure jq is available
echo "--- Checking jq..."
ssh "$TARGET" "command -v jq >/dev/null 2>&1 && echo 'jq ok' || echo 'WARNING: jq not found — install it for the daemon to work'"

# 3. Add sidebar config if not already present
echo "--- Configuring sidebar tokens..."
ssh "$TARGET" "
CONFIG_DIR=\"\${XDG_CONFIG_HOME:-\$HOME/.config}/herdr\"
CONFIG_FILE=\"\$CONFIG_DIR/config.toml\"

if [[ ! -f \"\$CONFIG_FILE\" ]]; then
    mkdir -p \"\$CONFIG_DIR\"
    printf '[ui.sidebar.agents]\n${SIDEBAR_CONFIG}\n' > \"\$CONFIG_FILE\"
    echo 'created config.toml with sidebar tokens'
elif grep -q 'cache_ok' \"\$CONFIG_FILE\"; then
    echo 'sidebar tokens already configured'
elif grep -q '\\[ui\\.sidebar\\.agents\\]' \"\$CONFIG_FILE\"; then
    echo 'WARNING: [ui.sidebar.agents] already exists but is missing cache tokens.'
    echo 'Please add this row manually inside that section:'
    echo '${SIDEBAR_CONFIG}'
else
    printf '\n[ui.sidebar.agents]\n${SIDEBAR_CONFIG}\n' >> \"\$CONFIG_FILE\"
    echo 'appended sidebar tokens to config.toml'
fi
"

# 4. Reload config and report
echo "--- Reloading config..."
ssh "$TARGET" "${HERDR} server reload-config 2>&1 || echo 'server not running — config will apply on next start'"

echo "--- Checking plugin status..."
ssh "$TARGET" "${HERDR} plugin list 2>&1 || echo 'server not running'"

echo ""
echo "==> Done. The daemon starts on next server restart."
echo "    To start it now: ssh ${TARGET} '${HERDR} server stop && ${HERDR}'"
