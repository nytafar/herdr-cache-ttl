use serde::Deserialize;
use std::path::PathBuf;
use std::{env, fs, io};

pub struct Config {
    pub ttl_seconds: i64,
    pub tick_interval: i64,
    pub seconds_threshold: i64,
    pub warn_at: i64,
    pub crit_at: i64,
    pub warn_thresholds: Vec<i64>,
    pub token_ttl_ms: i64,
    pub metadata_source: &'static str,
    pub tracked_agents: Vec<&'static str>,
    pub state_dir: PathBuf,
    pub timers_file: PathBuf,
    pub notified_file: PathBuf,
    pub pid_file: PathBuf,
}

#[derive(Deserialize)]
struct Overlay {
    ttl_seconds: Option<i64>,
    tick_interval: Option<i64>,
    seconds_threshold: Option<i64>,
    warn_at: Option<i64>,
    crit_at: Option<i64>,
}

pub fn load() -> io::Result<Config> {
    let state_dir = PathBuf::from(env_required("HERDR_PLUGIN_STATE_DIR")?);
    let config_dir = PathBuf::from(env_required("HERDR_PLUGIN_CONFIG_DIR")?);

    let mut cfg = Config {
        ttl_seconds: 3600,
        tick_interval: 15,
        seconds_threshold: 300,
        warn_at: 600,
        crit_at: 300,
        warn_thresholds: vec![600, 300, 60],
        token_ttl_ms: 45000,
        metadata_source: "plugin:cache-ttl",
        tracked_agents: vec!["claude"],
        timers_file: state_dir.join("timers.json"),
        notified_file: state_dir.join("notified.json"),
        pid_file: state_dir.join("daemon.pid"),
        state_dir,
    };

    if let Ok(data) = fs::read(config_dir.join("config.json")) {
        if let Ok(o) = serde_json::from_slice::<Overlay>(&data) {
            if let Some(v) = o.ttl_seconds.filter(|&v| v > 0) {
                cfg.ttl_seconds = v;
            }
            if let Some(v) = o.tick_interval.filter(|&v| v > 0) {
                cfg.tick_interval = v;
            }
            if let Some(v) = o.seconds_threshold.filter(|&v| v > 0) {
                cfg.seconds_threshold = v;
            }
            if let Some(v) = o.warn_at.filter(|&v| v > 0) {
                cfg.warn_at = v;
            }
            if let Some(v) = o.crit_at.filter(|&v| v > 0) {
                cfg.crit_at = v;
            }
        }
    }

    Ok(cfg)
}

fn env_required(key: &str) -> io::Result<String> {
    env::var(key).map_err(|_| io::Error::new(io::ErrorKind::NotFound, format!("{key} not set")))
}
