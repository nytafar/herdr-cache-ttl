package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	log.SetFlags(0)

	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: cache-ttl <command>")
		fmt.Fprintln(os.Stderr, "commands: daemon, on-status-change, on-pane-closed, reset-timer, show-timers, toggle-sort")
		os.Exit(1)
	}

	cfg, err := loadConfig()
	if err != nil {
		log.Fatal(err)
	}

	switch os.Args[1] {
	case "daemon":
		err = runDaemon(cfg)
	case "on-status-change":
		err = handleStatusChange(cfg)
	case "on-pane-closed":
		err = handlePaneClosed(cfg)
	case "reset-timer":
		err = handleResetTimer(cfg)
	case "show-timers":
		err = handleShowTimers(cfg)
	case "toggle-sort":
		err = handleToggleSort(cfg)
	default:
		log.Fatalf("unknown command: %s", os.Args[1])
	}
	if err != nil {
		log.Fatal(err)
	}
}
