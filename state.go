package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"syscall"
)

type timerEntry struct {
	LastTurn   int64 `json:"last_turn"`
	TTLSeconds int   `json:"ttl_seconds"`
}

type timers = map[string]timerEntry
type notified = map[string][]int

type state struct {
	lockPath     string
	timersPath   string
	notifiedPath string
}

func newState(cfg *config) *state {
	return &state{
		lockPath:     filepath.Join(cfg.StateDir, ".state.lock"),
		timersPath:   cfg.TimersFile,
		notifiedPath: cfg.NotifiedFile,
	}
}

func (s *state) init() error {
	dir := filepath.Dir(s.timersPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	for _, p := range []string{s.timersPath, s.notifiedPath} {
		if _, err := os.Stat(p); os.IsNotExist(err) {
			if err := atomicWriteJSON(p, map[string]any{}); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *state) withLock(fn func() error) error {
	f, err := os.OpenFile(s.lockPath, os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return fn()
}

func (s *state) readTimers() timers {
	var t timers
	if readJSON(s.timersPath, &t) != nil || t == nil {
		return timers{}
	}
	return t
}

func (s *state) readNotified() notified {
	var n notified
	if readJSON(s.notifiedPath, &n) != nil || n == nil {
		return notified{}
	}
	return n
}

func (s *state) setTimer(paneID string, entry timerEntry) error {
	return s.withLock(func() error {
		t := loadTimers(s.timersPath)
		t[paneID] = entry
		return atomicWriteJSON(s.timersPath, t)
	})
}

func (s *state) clearAllTimers() error {
	return s.withLock(func() error {
		return atomicWriteJSON(s.timersPath, timers{})
	})
}

func (s *state) pruneTimers(keep map[string]bool) error {
	return s.withLock(func() error {
		t := loadTimers(s.timersPath)
		for id := range t {
			if !keep[id] {
				delete(t, id)
			}
		}
		return atomicWriteJSON(s.timersPath, t)
	})
}

func (s *state) addNotification(paneID string, threshold int) error {
	return s.withLock(func() error {
		n := loadNotified(s.notifiedPath)
		n[paneID] = append(n[paneID], threshold)
		return atomicWriteJSON(s.notifiedPath, n)
	})
}

func (s *state) setTimerAndClearNotification(paneID string, entry timerEntry) error {
	return s.withLock(func() error {
		t := loadTimers(s.timersPath)
		t[paneID] = entry
		if err := atomicWriteJSON(s.timersPath, t); err != nil {
			return err
		}
		n := loadNotified(s.notifiedPath)
		delete(n, paneID)
		return atomicWriteJSON(s.notifiedPath, n)
	})
}

func (s *state) deleteTimerAndNotification(paneID string) error {
	return s.withLock(func() error {
		t := loadTimers(s.timersPath)
		delete(t, paneID)
		if err := atomicWriteJSON(s.timersPath, t); err != nil {
			return err
		}
		n := loadNotified(s.notifiedPath)
		delete(n, paneID)
		return atomicWriteJSON(s.notifiedPath, n)
	})
}

func loadTimers(path string) timers {
	var t timers
	if readJSON(path, &t) != nil || t == nil {
		return timers{}
	}
	return t
}

func loadNotified(path string) notified {
	var n notified
	if readJSON(path, &n) != nil || n == nil {
		return notified{}
	}
	return n
}

func readJSON(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

func atomicWriteJSON(path string, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".tmp.*")
	if err != nil {
		return err
	}
	name := f.Name()
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(name)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(name)
		return err
	}
	return os.Rename(name, path)
}
