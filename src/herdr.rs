use serde::Deserialize;
use std::io::{self, Write};
use std::os::unix::net::UnixStream;
use std::process::Command;
use std::time::Duration;

use crate::config::Config;

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

    Command::new("herdr").args(&args).output().map(|_| ())
}

pub fn agent_list() -> io::Result<Vec<AgentInfo>> {
    let out = Command::new("herdr").args(["agent", "list"]).output()?;
    let resp: AgentListResp =
        serde_json::from_slice(&out.stdout).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    Ok(resp.result.agents)
}

pub fn agent_get_title(pane_id: &str) -> String {
    let Ok(out) = Command::new("herdr").args(["agent", "get", pane_id]).output() else {
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
    let _ = Command::new("herdr")
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
