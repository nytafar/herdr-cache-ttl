package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

func runDaemon(cfg *config) error {
	st := newState(cfg)
	if err := st.init(); err != nil {
		return err
	}

	if isRunning(cfg.PIDFile) {
		logf("daemon already running, exiting")
		return nil
	}
	os.WriteFile(cfg.PIDFile, []byte(strconv.Itoa(os.Getpid())), 0644)
	defer os.Remove(cfg.PIDFile)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	reapplySort(cfg)

	logf("daemon started, pid=%d, tick=%ds", os.Getpid(), cfg.TickInterval)

	ticker := time.NewTicker(time.Duration(cfg.TickInterval) * time.Second)
	defer ticker.Stop()

	const cleanupInterval = 10
	tickCount := 0
	consecutiveFailures := 0

	for {
		select {
		case <-ctx.Done():
			logf("daemon shutting down")
			return nil
		case <-ticker.C:
		}

		tickCount++

		t := st.readTimers()
		if len(t) == 0 {
			continue
		}
		now := time.Now().Unix()

		if tickCount%cleanupInterval == 0 {
			pruneStale(st)
			t = st.readTimers()
			if len(t) == 0 {
				continue
			}
		}

		if refreshWorkingAgents(st, cfg, now) {
			t = st.readTimers()
		}

		updated, failed := 0, 0
		for paneID, entry := range t {
			remaining := entry.TTLSeconds - int(now-entry.LastTurn)

			if err := setPaneTokens(paneID, remaining, cfg); err != nil {
				failed++
			} else {
				updated++
			}

			checkNotifications(st, cfg, paneID, remaining)
		}

		if failed > 0 && updated == 0 {
			consecutiveFailures++
			if consecutiveFailures >= 3 {
				logf("all updates failing (%d consecutive), backing off", consecutiveFailures)
				time.Sleep(60 * time.Second)
			}
		} else {
			consecutiveFailures = 0
		}
	}
}

func refreshWorkingAgents(st *state, cfg *config, now int64) bool {
	agents, err := herdrAgentList()
	if err != nil {
		return false
	}

	t := st.readTimers()
	changed := false

	for _, agent := range agents {
		if agent.AgentStatus != "working" {
			continue
		}
		lastTurn := int64(0)
		if entry, ok := t[agent.PaneID]; ok {
			lastTurn = entry.LastTurn
		}
		if now-lastTurn > int64(cfg.TickInterval) {
			st.setTimer(agent.PaneID, timerEntry{
				LastTurn:   now,
				TTLSeconds: cfg.TTLSeconds,
			})
			changed = true
		}
	}
	return changed
}

func pruneStale(st *state) {
	agents, err := herdrAgentList()
	if err != nil {
		return
	}
	if len(agents) == 0 {
		st.clearAllTimers()
		return
	}
	keep := make(map[string]bool, len(agents))
	for _, a := range agents {
		keep[a.PaneID] = true
	}
	st.pruneTimers(keep)
}

func checkNotifications(st *state, cfg *config, paneID string, remaining int) {
	if remaining <= 0 {
		return
	}

	n := st.readNotified()
	seen := n[paneID]

	for _, threshold := range cfg.WarnThresholds {
		if remaining <= threshold {
			if !intSliceContains(seen, threshold) {
				label := formatRemaining(threshold, cfg.SecondsThreshold)
				title := herdrAgentGetTitle(paneID)
				herdrNotify(fmt.Sprintf("Cache expires in %s", label), title, "request")
				st.addNotification(paneID, threshold)
				seen = append(seen, threshold)
			}
		}
	}
}

func reapplySort(cfg *config) {
	sortFile := filepath.Join(cfg.StateDir, "sort_active")
	if _, err := os.Stat(sortFile); err != nil {
		return
	}
	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		return
	}
	msg := `{"id":"on","method":"agent.view.set","params":{"source":"plugin:cache-ttl","label":"cache","sort":[{"field":{"token":"cache_sort"},"order":"desc"},{"field":"attention","order":"desc"},{"field":"state_change_seq","order":"desc"}]}}`
	if err := herdrSocketSend(socketPath, msg); err != nil {
		logf("failed to reapply sort view: %v", err)
	}
}

func isRunning(pidFile string) bool {
	data, err := os.ReadFile(pidFile)
	if err != nil {
		return false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	return proc.Signal(syscall.Signal(0)) == nil
}

func intSliceContains(s []int, v int) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "[%s] %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
}
