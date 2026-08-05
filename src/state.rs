use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

use crate::config::Config;

#[derive(Serialize, Deserialize, Clone)]
pub struct TimerEntry {
    pub last_turn: i64,
    pub ttl_seconds: i64,
}

pub type Timers = HashMap<String, TimerEntry>;
pub type Notified = HashMap<String, Vec<i64>>;

pub struct State {
    lock_path: PathBuf,
    timers_path: PathBuf,
    notified_path: PathBuf,
}

struct Lock {
    file: fs::File,
}

impl Lock {
    fn acquire(path: &Path) -> io::Result<Self> {
        let file = fs::OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(path)?;
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX) } != 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(Lock { file })
    }
}

impl Drop for Lock {
    fn drop(&mut self) {
        unsafe {
            libc::flock(self.file.as_raw_fd(), libc::LOCK_UN);
        }
    }
}

impl State {
    pub fn new(cfg: &Config) -> Self {
        State {
            lock_path: cfg.state_dir.join(".state.lock"),
            timers_path: cfg.timers_file.clone(),
            notified_path: cfg.notified_file.clone(),
        }
    }

    pub fn init(&self) -> io::Result<()> {
        if let Some(dir) = self.timers_path.parent() {
            fs::create_dir_all(dir)?;
        }
        for p in [&self.timers_path, &self.notified_path] {
            if !p.exists() {
                fs::write(p, b"{}")?;
            }
        }
        Ok(())
    }

    fn lock(&self) -> io::Result<Lock> {
        Lock::acquire(&self.lock_path)
    }

    pub fn read_timers(&self) -> Timers {
        read_json(&self.timers_path).unwrap_or_default()
    }

    pub fn read_notified(&self) -> Notified {
        read_json(&self.notified_path).unwrap_or_default()
    }

    pub fn set_timer(&self, pane_id: &str, entry: TimerEntry) -> io::Result<()> {
        let _lock = self.lock()?;
        let mut t: Timers = read_json(&self.timers_path).unwrap_or_default();
        t.insert(pane_id.into(), entry);
        atomic_write_json(&self.timers_path, &t)
    }

    pub fn clear_all_timers(&self) -> io::Result<()> {
        let _lock = self.lock()?;
        atomic_write_json(&self.timers_path, &Timers::new())
    }

    pub fn prune_timers(&self, keep: &HashSet<String>) -> io::Result<()> {
        let _lock = self.lock()?;
        let mut t: Timers = read_json(&self.timers_path).unwrap_or_default();
        t.retain(|id, _| keep.contains(id));
        atomic_write_json(&self.timers_path, &t)
    }

    pub fn add_notification(&self, pane_id: &str, threshold: i64) -> io::Result<()> {
        let _lock = self.lock()?;
        let mut n: Notified = read_json(&self.notified_path).unwrap_or_default();
        n.entry(pane_id.into()).or_default().push(threshold);
        atomic_write_json(&self.notified_path, &n)
    }

    pub fn set_timer_and_clear_notification(
        &self,
        pane_id: &str,
        entry: TimerEntry,
    ) -> io::Result<()> {
        let _lock = self.lock()?;
        let mut t: Timers = read_json(&self.timers_path).unwrap_or_default();
        t.insert(pane_id.into(), entry);
        atomic_write_json(&self.timers_path, &t)?;
        let mut n: Notified = read_json(&self.notified_path).unwrap_or_default();
        n.remove(pane_id);
        atomic_write_json(&self.notified_path, &n)
    }

    pub fn delete_timer_and_notification(&self, pane_id: &str) -> io::Result<()> {
        let _lock = self.lock()?;
        let mut t: Timers = read_json(&self.timers_path).unwrap_or_default();
        t.remove(pane_id);
        atomic_write_json(&self.timers_path, &t)?;
        let mut n: Notified = read_json(&self.notified_path).unwrap_or_default();
        n.remove(pane_id);
        atomic_write_json(&self.notified_path, &n)
    }
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Option<T> {
    serde_json::from_slice(&fs::read(path).ok()?).ok()
}

fn atomic_write_json<T: Serialize>(path: &Path, value: &T) -> io::Result<()> {
    let data =
        serde_json::to_vec(value).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    fs::write(&tmp, &data)?;
    fs::rename(&tmp, path)
}
