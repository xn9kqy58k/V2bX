package conf

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fsnotify/fsnotify"
)

func TestReloadFromPathSkipsInvalidConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{"Log":{"Level":"error"},"Nodes":[`), 0600); err != nil {
		t.Fatal(err)
	}
	c := New()
	c.LogConfig.Level = "debug"
	called := false
	reload := func() {
		called = true
		if c.LogConfig.Level != "warn" {
			t.Errorf("reload saw stale config: %+v", c.LogConfig)
		}
	}
	if err := c.reloadFromPath(path, reload); err == nil {
		t.Fatal("invalid config was accepted")
	}
	if called || c.LogConfig.Level != "debug" {
		t.Fatal("invalid config triggered reload or changed active config")
	}
	if err := os.WriteFile(path, []byte(`{"Log":{"Level":"warn"}}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := c.reloadFromPath(path, reload); err != nil {
		t.Fatal(err)
	}
	if !called {
		t.Fatal("valid replacement did not trigger reload")
	}
}

func TestWatchRejectsMissingPaths(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{}`), 0600); err != nil {
		t.Fatal(err)
	}
	missing := filepath.Join(t.TempDir(), "missing.json")
	for _, paths := range [][3]string{
		{missing, "", ""},
		{path, missing, ""},
		{path, "", missing},
	} {
		if err := New().Watch(paths[0], paths[1], paths[2], func() {
			t.Error("failed watcher setup triggered reload")
		}); err == nil {
			t.Fatalf("watching missing path succeeded: %v", paths)
		}
	}
}

func TestWatchStopsWithPendingReload(t *testing.T) {
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { watcher.Close() })
	done := make(chan struct{})
	called := make(chan struct{}, 1)
	go func() {
		New().watch(watcher, "config.json", "", "", func() { called <- struct{}{} })
		close(done)
	}()
	select {
	case watcher.Events <- fsnotify.Event{Name: "config.json", Op: fsnotify.Write}:
	case <-time.After(time.Second):
		t.Fatal("watcher did not receive event")
	}
	if err := watcher.Close(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("watcher did not exit after channels closed")
	}
	select {
	case <-called:
		t.Fatal("closed watcher ran a pending reload")
	default:
	}
}
