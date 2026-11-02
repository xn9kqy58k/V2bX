//go:build linux

package main

import (
	"context"
	"net"
	"os"
	"syscall"
	"testing"

	"github.com/xtls/xray-core/transport/internet"
	"golang.org/x/sys/unix"
)

func listenerProtocol(t *testing.T, listener net.Listener) int {
	t.Helper()
	t.Cleanup(func() { listener.Close() })
	raw, err := listener.(syscall.Conn).SyscallConn()
	if err != nil {
		t.Fatal(err)
	}
	var protocol int
	var socketErr error
	err = raw.Control(func(fd uintptr) {
		protocol, socketErr = unix.GetsockoptInt(int(fd), unix.SOL_SOCKET, unix.SO_PROTOCOL)
	})
	if err != nil {
		t.Fatal(err)
	}
	if socketErr != nil {
		t.Fatal(socketErr)
	}
	return protocol
}

func TestMPTCPDisabledByDefault(t *testing.T) {
	// Check the compiled go.mod default, independently of the test environment.
	t.Setenv("GODEBUG", "")
	var config net.ListenConfig
	if config.MultipathTCP() {
		t.Fatal("default listeners enable MPTCP; check the main module's godebug directive")
	}
	var dialer net.Dialer
	if dialer.MultipathTCP() {
		t.Fatal("default dialers enable MPTCP")
	}
	listener, err := config.Listen(context.Background(), "tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	if protocol := listenerProtocol(t, listener); protocol != unix.IPPROTO_TCP {
		t.Fatalf("listener protocol = %d, want TCP (%d)", protocol, unix.IPPROTO_TCP)
	}
}

func TestXrayDisablesMPTCPByDefault(t *testing.T) {
	// Xray must explicitly opt out even if the environment enables Go's MPTCP default.
	t.Setenv("GODEBUG", "multipathtcp=1")
	var defaultConfig net.ListenConfig
	if !defaultConfig.MultipathTCP() {
		t.Fatal("GODEBUG did not enable the MPTCP default required by this regression test")
	}
	var probeConfig net.ListenConfig
	probeConfig.SetMultipathTCP(true)
	probe, err := probeConfig.Listen(context.Background(), "tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	if listenerProtocol(t, probe) != unix.IPPROTO_MPTCP {
		if os.Getenv("V2BX_REQUIRE_MPTCP") == "1" {
			t.Fatal("kernel MPTCP unavailable on the required regression runner")
		}
		t.Skip("kernel MPTCP unavailable; run on an MPTCP-enabled Linux host to check the Xray override")
	}
	for _, tc := range []struct {
		name    string
		options *internet.SocketConfig
	}{
		{name: "no_socket_options"},
		{name: "default_socket_options", options: &internet.SocketConfig{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			listener, err := (&internet.DefaultListener{}).Listen(context.Background(), &net.TCPAddr{
				IP: net.IPv4(127, 0, 0, 1),
			}, tc.options)
			if err != nil {
				t.Fatal(err)
			}
			if protocol := listenerProtocol(t, listener); protocol != unix.IPPROTO_TCP {
				t.Fatalf("Xray listener protocol = %d, want TCP (%d)", protocol, unix.IPPROTO_TCP)
			}
		})
	}
}
