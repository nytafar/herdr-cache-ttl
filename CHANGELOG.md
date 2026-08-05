# Changelog

## 0.3.1

- Ship prebuilt binaries in `dist/` and select one via a `[[build]]` hook —
  installing from GitHub previously left no binary at all, so the daemon and
  every event hook failed with "No such file or directory"
- Remove the pre-rewrite shell implementation (`daemon.sh` and friends), unused
  since 0.3.0
- Deploy script: pass `--yes` to `plugin install` (after the repo arg, which the
  server-side handler requires) and stop swallowing install failures

## 0.3.0

- Rewrite in Rust — 396KB static binary, no jq/bash runtime dependency
- flock(2)-based file locking replaces mkdir hack, eliminating shared-state races
- Fix 5m and 1m notifications never firing (only 10m worked)
- Fix sort toggle targeting wrong socket (HERDR_SOCKET → HERDR_SOCKET_PATH)
- Sort toggle now fails loudly instead of flipping state on API error
- Handle pane.closed event alongside pane.exited
- PID guard prevents duplicate daemons on server reload
- Sort view reapplied automatically after server restart
- Validate user config values (reject non-positive integers)
- Deploy script no longer creates invalid duplicate TOML tables
- Bump min_herdr_version to 0.7.5

## 0.2.0

- Add cache sort mode — toggle via `herdr plugin action invoke sort --plugin cache-ttl` to sort the agent panel by cache TTL urgency (warmest first), using herdr's agent view API
- Fix timers showing 0m for actively working agents — the daemon now refreshes timers for agents in `working` status, not only on status transitions
- Emit `cache_sort` token (zero-padded seconds remaining) for sortable ordering

## 0.1.0

- Initial release
- Live prompt-cache countdown per agent pane
- Color-coded sidebar tokens (green/amber/red)
- Notifications at 10m, 5m, and 1m remaining
- Configurable TTL, tick interval, and thresholds
- Stale pane cleanup and pane close handling
