package conf

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestConf_LoadFromPath(t *testing.T) {
	c := New()
	if err := c.LoadFromPath("../example/config.json"); err != nil {
		t.Fatal(err)
	}
}

func TestLoadFromPathPreservesConfigOnError(t *testing.T) {
	for _, test := range []struct {
		name string
		data string
	}{
		{name: "invalid_json", data: `{"Log":{"Level":"error"},"Nodes":[`},
		{name: "invalid_value", data: `{"Log":{"Level":"error"},"Nodes":[{"ApiConfig":{"NodeID":"bad"}}]}`},
	} {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.json")
			if err := os.WriteFile(path, []byte(test.data), 0600); err != nil {
				t.Fatal(err)
			}
			c := New()
			c.LogConfig.Level = "debug"
			c.NodeConfig = []NodeConfig{{ApiConfig: ApiConfig{NodeID: 42}}}
			before := *c
			if err := c.LoadFromPath(path); err == nil {
				t.Fatal("invalid config was accepted")
			}
			if !reflect.DeepEqual(*c, before) {
				t.Fatalf("failed load changed active config: got %+v, want %+v", *c, before)
			}
		})
	}
}

func TestLoadFromPathRestoresDefaults(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(path, []byte(`{}`), 0600); err != nil {
		t.Fatal(err)
	}
	c := New()
	c.LogConfig.Level = "debug"
	c.NodeConfig = []NodeConfig{{ApiConfig: ApiConfig{NodeID: 42}}}
	if err := c.LoadFromPath(path); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(c, New()) {
		t.Fatalf("omitted settings retained old values: %+v", *c)
	}
}
