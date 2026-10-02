# Changelog

## 0.3.4

- Release workflow: build x86_64 macOS on `macos-14` (cross-compiled) — the
  `macos-13` runner is retired, so the v0.3.3 release never completed. 0.3.4
  carries the 0.3.3 fix below and is the first release with refreshed
  binaries for every platform

## 0.3.3

- Fix the daemon aborting (SIGABRT) when herdr closes the read end of its
  stderr pipe: `logf` used `eprintln!`, which panics on a write error, and the
  release profile's `panic = "abort"` turned that into a crash. Log writes now
  ignore errors. Seen on herdr 0.9.3, where a restarted server left the daemon
  with an unreadable stderr
- Verified against herdr 0.9.3: event hooks, `agent list`/`agent get`, and
  `pane report-metadata` token pushes all work
- Add GitHub Actions: build and clippy on every push and PR; on `v*` tags,
  build all four platform binaries, refresh `dist/` on main and attach them to
  the release

## 0.3.2

- Resolve the herdr binary via `HERDR_BIN_PATH` instead of bare `herdr` on
  `PATH` — a server started from a non-login shell (an install under
  `~/.local/bin`, say) left every CLI call failing to exec, so no tokens were
  ever pushed and the sidebar stayed empty on that host
- `set_pane_tokens` now treats a non-zero herdr exit as an error rather than
  success, and the daemon's back-off log includes the underlying error

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
