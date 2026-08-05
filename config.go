package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type config struct {
	TTLSeconds       int
	TickInterval     int
	SecondsThreshold int
	WarnAt           int
	CritAt           int
	WarnThresholds   []int
	TokenTTLMs       int
	MetadataSource   string
	TrackedAgents    []string

	StateDir     string
	ConfigDir    string
	TimersFile   string
	NotifiedFile string
	PIDFile      string
}

func loadConfig() (*config, error) {
	stateDir := os.Getenv("HERDR_PLUGIN_STATE_DIR")
	if stateDir == "" {
		return nil, fmt.Errorf("HERDR_PLUGIN_STATE_DIR not set")
	}
	configDir := os.Getenv("HERDR_PLUGIN_CONFIG_DIR")
	if configDir == "" {
		return nil, fmt.Errorf("HERDR_PLUGIN_CONFIG_DIR not set")
	}

	cfg := &config{
		TTLSeconds:       3600,
		TickInterval:     15,
		SecondsThreshold: 300,
		WarnAt:           600,
		CritAt:           300,
		WarnThresholds:   []int{600, 300, 60},
		TokenTTLMs:       45000,
		MetadataSource:   "plugin:cache-ttl",
		TrackedAgents:    []string{"claude"},
		StateDir:         stateDir,
		ConfigDir:        configDir,
		TimersFile:       filepath.Join(stateDir, "timers.json"),
		NotifiedFile:     filepath.Join(stateDir, "notified.json"),
		PIDFile:          filepath.Join(stateDir, "daemon.pid"),
	}

	data, err := os.ReadFile(filepath.Join(configDir, "config.json"))
	if err != nil {
		return cfg, nil
	}
	var overlay struct {
		TTLSeconds       *int `json:"ttl_seconds"`
		TickInterval     *int `json:"tick_interval"`
		SecondsThreshold *int `json:"seconds_threshold"`
		WarnAt           *int `json:"warn_at"`
		CritAt           *int `json:"crit_at"`
	}
	if json.Unmarshal(data, &overlay) != nil {
		return cfg, nil
	}
	if overlay.TTLSeconds != nil && *overlay.TTLSeconds > 0 {
		cfg.TTLSeconds = *overlay.TTLSeconds
	}
	if overlay.TickInterval != nil && *overlay.TickInterval > 0 {
		cfg.TickInterval = *overlay.TickInterval
	}
	if overlay.SecondsThreshold != nil && *overlay.SecondsThreshold > 0 {
		cfg.SecondsThreshold = *overlay.SecondsThreshold
	}
	if overlay.WarnAt != nil && *overlay.WarnAt > 0 {
		cfg.WarnAt = *overlay.WarnAt
	}
	if overlay.CritAt != nil && *overlay.CritAt > 0 {
		cfg.CritAt = *overlay.CritAt
	}
	return cfg, nil
}
