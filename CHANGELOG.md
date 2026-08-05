# Changelog

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
