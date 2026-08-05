package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

func handleStatusChange(cfg *config) error {
	eventJSON := os.Getenv("HERDR_PLUGIN_EVENT_JSON")
	if eventJSON == "" {
		return nil
	}

	var event struct {
		Data struct {
			PaneID      string `json:"pane_id"`
			AgentStatus string `json:"agent_status"`
			Agent       string `json:"agent"`
		} `json:"data"`
	}
	if json.Unmarshal([]byte(eventJSON), &event) != nil {
		return nil
	}
	if event.Data.PaneID == "" || event.Data.AgentStatus == "" {
		return nil
	}

	agent := event.Data.Agent
	if agent == "" {
		if ctxJSON := os.Getenv("HERDR_PLUGIN_CONTEXT_JSON"); ctxJSON != "" {
			var ctx struct {
				FocusedPaneAgent string `json:"focused_pane_agent"`
			}
			json.Unmarshal([]byte(ctxJSON), &ctx)
			agent = ctx.FocusedPaneAgent
		}
	}

	if agent != "" {
		tracked := false
		for _, a := range cfg.TrackedAgents {
			if agent == a {
				tracked = true
				break
			}
		}
		if !tracked {
			return nil
		}
	}

	st := newState(cfg)
	if err := st.init(); err != nil {
		return err
	}

	return st.setTimerAndClearNotification(event.Data.PaneID, timerEntry{
		LastTurn:   time.Now().Unix(),
		TTLSeconds: cfg.TTLSeconds,
	})
}

func handlePaneClosed(cfg *config) error {
	eventJSON := os.Getenv("HERDR_PLUGIN_EVENT_JSON")
	if eventJSON == "" {
		return nil
	}

	var event struct {
		Data struct {
			PaneID string `json:"pane_id"`
		} `json:"data"`
	}
	if json.Unmarshal([]byte(eventJSON), &event) != nil || event.Data.PaneID == "" {
		return nil
	}

	return newState(cfg).deleteTimerAndNotification(event.Data.PaneID)
}

func handleResetTimer(cfg *config) error {
	paneID := os.Getenv("HERDR_PANE_ID")
	if paneID == "" {
		return fmt.Errorf("no pane in context")
	}

	st := newState(cfg)
	if err := st.init(); err != nil {
		return err
	}

	if err := st.setTimerAndClearNotification(paneID, timerEntry{
		LastTurn:   time.Now().Unix(),
		TTLSeconds: cfg.TTLSeconds,
	}); err != nil {
		return err
	}

	fmt.Printf("Timer reset for %s\n", paneID)
	return nil
}

func handleShowTimers(cfg *config) error {
	st := newState(cfg)
	t := st.readTimers()
	if len(t) == 0 {
		fmt.Println("No active timers")
		return nil
	}

	now := time.Now().Unix()

	ids := make([]string, 0, len(t))
	for id := range t {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	fmt.Printf("%-12s  %-8s  %s\n", "PANE", "TTL", "TITLE")
	fmt.Printf("%-12s  %-8s  %s\n", "----", "---", "-----")

	for _, paneID := range ids {
		entry := t[paneID]
		remaining := entry.TTLSeconds - int(now-entry.LastTurn)

		var label string
		if remaining <= 0 {
			label = "expired"
		} else if remaining <= 300 {
			label = fmt.Sprintf("%d:%02d", remaining/60, remaining%60)
		} else {
			label = fmt.Sprintf("%dm", remaining/60)
		}

		title := herdrAgentGetTitle(paneID)

		fmt.Printf("%-12s  %-8s  %s\n", paneID, label, title)
	}
	return nil
}

func handleToggleSort(cfg *config) error {
	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		return fmt.Errorf("HERDR_SOCKET_PATH not set")
	}

	sortFile := filepath.Join(cfg.StateDir, "sort_active")

	if _, err := os.Stat(sortFile); err == nil {
		msg := `{"id":"off","method":"agent.view.clear","params":{"source":"plugin:cache-ttl"}}`
		if err := herdrSocketSend(socketPath, msg); err != nil {
			return fmt.Errorf("failed to clear sort view: %w", err)
		}
		os.Remove(sortFile)
		fmt.Println("Cache sort off")
	} else {
		msg := `{"id":"on","method":"agent.view.set","params":{"source":"plugin:cache-ttl","label":"cache","sort":[{"field":{"token":"cache_sort"},"order":"desc"},{"field":"attention","order":"desc"},{"field":"state_change_seq","order":"desc"}]}}`
		if err := herdrSocketSend(socketPath, msg); err != nil {
			return fmt.Errorf("failed to set sort view: %w", err)
		}
		os.WriteFile(sortFile, []byte{}, 0644)
		fmt.Println("Cache sort on")
	}
	return nil
}
