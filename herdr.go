package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"strconv"
	"time"
)

type agentInfo struct {
	PaneID                string `json:"pane_id"`
	AgentStatus           string `json:"agent_status"`
	Name                  string `json:"name"`
	TerminalTitleStripped string `json:"terminal_title_stripped"`
}

func setPaneTokens(paneID string, remaining int, cfg *config) error {
	label := formatRemaining(remaining, cfg.SecondsThreshold)

	var sortVal string
	if remaining <= 0 {
		sortVal = "000000"
	} else {
		sortVal = fmt.Sprintf("%06d", remaining)
	}

	args := []string{"pane", "report-metadata", paneID,
		"--source", cfg.MetadataSource,
		"--ttl-ms", strconv.Itoa(cfg.TokenTTLMs),
		"--token", "cache_sort=" + sortVal,
	}

	if remaining <= cfg.CritAt {
		args = append(args, "--token", "cache_crit="+label, "--clear-token", "cache_ok", "--clear-token", "cache_warn")
	} else if remaining <= cfg.WarnAt {
		args = append(args, "--token", "cache_warn="+label, "--clear-token", "cache_ok", "--clear-token", "cache_crit")
	} else {
		args = append(args, "--token", "cache_ok="+label, "--clear-token", "cache_warn", "--clear-token", "cache_crit")
	}

	return exec.Command("herdr", args...).Run()
}

func herdrAgentList() ([]agentInfo, error) {
	out, err := exec.Command("herdr", "agent", "list").Output()
	if err != nil {
		return nil, err
	}
	var resp struct {
		Result struct {
			Agents []agentInfo `json:"agents"`
		} `json:"result"`
	}
	if err := json.Unmarshal(out, &resp); err != nil {
		return nil, err
	}
	return resp.Result.Agents, nil
}

func herdrAgentGetTitle(paneID string) string {
	out, err := exec.Command("herdr", "agent", "get", paneID).Output()
	if err != nil {
		return paneID
	}
	var resp struct {
		Result struct {
			Agent agentInfo `json:"agent"`
		} `json:"result"`
	}
	if err := json.Unmarshal(out, &resp); err != nil || resp.Result.Agent.TerminalTitleStripped == "" {
		return paneID
	}
	return resp.Result.Agent.TerminalTitleStripped
}

func herdrNotify(title, body, sound string) {
	exec.Command("herdr", "notification", "show", title, "--body", body, "--sound", sound).Run()
}

func herdrSocketSend(socketPath, msg string) error {
	conn, err := net.DialTimeout("unix", socketPath, 2*time.Second)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = fmt.Fprintln(conn, msg)
	return err
}

func formatRemaining(remaining, threshold int) string {
	if remaining <= 0 {
		return "0m"
	}
	if remaining <= threshold {
		return fmt.Sprintf("%d:%02d", remaining/60, remaining%60)
	}
	return fmt.Sprintf("%dm", remaining/60)
}
