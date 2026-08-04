# herdr-cache-ttl

A [Herdr](https://herdr.dev) plugin that tracks prompt-cache TTL per agent pane. Shows a live countdown in the sidebar so you know which sessions are about to lose their cache — no more jumping between servers to check.

## How it works

The plugin watches for agent status transitions (via `pane.agent_status_changed`), stamps the time of each turn, and pushes a color-coded countdown into the sidebar:

- **Green** — plenty of time remaining
- **Amber** — under 10 minutes
- **Red** — under 5 minutes or expired (`0m`)

A background daemon ticks every 15 seconds, updating all tracked panes. Notifications fire at 10m, 5m, and 1m remaining.

## Install

```bash
herdr plugin link /path/to/herdr-cache-ttl
```

Then add the tokens to your sidebar config in `~/.config/herdr/config.toml`:

```toml
[ui.sidebar.agents]
rows = [
  ["state_icon", "workspace", "tab"],
  ["agent", { token = "$cache_ok", fg = "#4ade80" }, { token = "$cache_warn", fg = "#f59e0b" }, { token = "$cache_crit", fg = "#ef4444" }],
]
```

Reload and restart:

```bash
herdr server reload-config
herdr server stop && herdr
```

The daemon starts automatically via the `[[startup]]` hook on server start.

## Configuration

Create `config.json` in the plugin config directory (`herdr plugin config-dir cache-ttl`):

```json
{
  "ttl_seconds": 3600,
  "tick_interval": 15,
  "seconds_threshold": 300
}
```

| Key | Default | Description |
|-----|---------|-------------|
| `ttl_seconds` | `3600` | Cache TTL duration (60 min for standard, 300 for overage) |
| `tick_interval` | `15` | Seconds between countdown updates |
| `seconds_threshold` | `300` | Show `m:ss` format below this many seconds |
| `warn_at` | `600` | Amber threshold — seconds remaining |
| `crit_at` | `300` | Red threshold — seconds remaining |

## Actions

- **Reset cache timer** — reset the countdown for the focused pane
- **Show cache timers** — print all active timers as a table

## Requirements

- Herdr >= 0.6.10
- `jq`
- `bash`

## License

MIT
