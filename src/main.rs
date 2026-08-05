mod config;
mod daemon;
mod handlers;
mod herdr;
mod state;

use std::process;

pub fn now_unix() -> i64 {
    unsafe { libc::time(std::ptr::null_mut()) as i64 }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: cache-ttl <command>");
        eprintln!("commands: daemon, on-status-change, on-pane-closed, reset-timer, show-timers, toggle-sort");
        process::exit(1);
    }

    let cfg = match config::load() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            process::exit(1);
        }
    };

    let result = match args[1].as_str() {
        "daemon" => daemon::run(&cfg),
        "on-status-change" => handlers::status_change(&cfg),
        "on-pane-closed" => handlers::pane_closed(&cfg),
        "reset-timer" => handlers::reset_timer(&cfg),
        "show-timers" => handlers::show_timers(&cfg),
        "toggle-sort" => handlers::toggle_sort(&cfg),
        cmd => {
            eprintln!("unknown command: {cmd}");
            process::exit(1);
        }
    };

    if let Err(e) = result {
        eprintln!("{e}");
        process::exit(1);
    }
}
