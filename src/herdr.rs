use serde::Deserialize;
use std::io::{self, Write};
use std::os::unix::net::UnixStream;
use std::process::Command;
use std::sync::OnceLock;
use std::time::Duration;

use crate::config::Config;

/// The herdr binary is not always on the plugin process's PATH — a server
/// started from a non-login shell inherits none of the shell profile, so an
/// install under ~/.local/bin is invisible. herdr hands us the absolute path
/// in the environment; use it, and fall back to PATH lookup.
fn herdr_bin() -> &'static str {
    static BIN: OnceLock<String> = OnceLock::new();
    BIN.get_or_init(|| {
        std::env::var("HERDR_BIN_PATH")
            .ok()
            .filter(|p| !p.is_empty())
            .unwrap_or_else(|| "herdr".to_string())
    })
}

#[derive(Deserialize)]
pub struct AgentInfo {
    pub pane_id: String,
    #[serde(default)]
    pub agent_status: String,
    #[serde(default)]
    pub terminal_title_stripped: String,
}

pub fn set_pane_tokens(pane_id: &str, remaining: i64, cfg: &Config) -> io::Result<()> {
    let label = format_remaining(remaining, cfg.seconds_threshold);
    let sort_val = if remaining <= 0 {
        "000000".to_string()
    } else {
        format!("{:06}", remaining)
    };

    let mut args = vec![
        "pane",
        "report-metadata",
        pane_id,
        "--source",
        cfg.metadata_source,
        "--ttl-ms",
    ];
    let ttl_str = cfg.token_ttl_ms.to_string();
    args.push(&ttl_str);
    args.push("--token");
    let sort_token = format!("cache_sort={sort_val}");
    args.push(&sort_token);

    let tier_token;
    if remaining <= cfg.crit_at {
        tier_token = format!("cache_crit={label}");
        args.extend(["--token", &tier_token, "--clear-token", "cache_ok", "--clear-token", "cache_warn"]);
    } else if remaining <= cfg.warn_at {
        tier_token = format!("cache_warn={label}");
        args.extend(["--token", &tier_token, "--clear-token", "cache_ok", "--clear-token", "cache_crit"]);
    } else {
        tier_token = format!("cache_ok={label}");
        args.extend(["--token", &tier_token, "--clear-token", "cache_warn", "--clear-token", "cache_crit"]);
    }

    let out = Command::new(herdr_bin()).args(&args).output()?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        return Err(io::Error::other(format!(
            "{} pane report-metadata failed: {}",
            herdr_bin(),
            stderr.trim()
        )));
    }
    Ok(())
}

pub fn agent_list() -> io::Result<Vec<AgentInfo>> {
    let out = Command::new(herdr_bin()).args(["agent", "list"]).output()?;
    let resp: AgentListResp =
        serde_json::from_slice(&out.stdout).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    Ok(resp.result.agents)
}

pub fn agent_get_title(pane_id: &str) -> String {
    let Ok(out) = Command::new(herdr_bin()).args(["agent", "get", pane_id]).output() else {
        return pane_id.to_string();
    };
    let Ok(resp) = serde_json::from_slice::<AgentGetResp>(&out.stdout) else {
        return pane_id.to_string();
    };
    let title = &resp.result.agent.terminal_title_stripped;
    if title.is_empty() {
        pane_id.to_string()
    } else {
        title.clone()
    }
}

pub fn notify(title: &str, body: &str, sound: &str) {
    let _ = Command::new(herdr_bin())
        .args(["notification", "show", title, "--body", body, "--sound", sound])
        .output();
}

pub fn socket_send(socket_path: &str, msg: &str) -> io::Result<()> {
    let mut stream = UnixStream::connect(socket_path)?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    writeln!(stream, "{msg}")?;
    Ok(())
}

pub fn format_remaining(remaining: i64, threshold: i64) -> String {
    if remaining <= 0 {
        "0m".into()
    } else if remaining <= threshold {
        format!("{}:{:02}", remaining / 60, remaining % 60)
    } else {
        format!("{}m", remaining / 60)
    }
}

#[derive(Deserialize)]
struct AgentListResp {
    result: AgentListResult,
}

#[derive(Deserialize)]
struct AgentListResult {
    #[serde(default)]
    agents: Vec<AgentInfo>,
}

#[derive(Deserialize)]
struct AgentGetResp {
    result: AgentGetResult,
}

#[derive(Deserialize)]
struct AgentGetResult {
    agent: AgentInfo,
}
