package cmd

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
)

type installerHTTPClientFunc func(*http.Request) (*http.Response, error)

func (f installerHTTPClientFunc) Do(request *http.Request) (*http.Response, error) {
	return f(request)
}

type installerReadError struct {
	err error
}

func (r installerReadError) Read([]byte) (int, error) { return 0, r.err }

func TestUpdateInstallerRejectsFailedDownload(t *testing.T) {
	downloadErr := errors.New("download failed")
	readErr := errors.New("truncated download")
	for _, test := range []struct {
		name          string
		status        int
		body          io.Reader
		contentLength int64
		err           error
		wantErr       error
	}{
		{name: "transport", err: downloadErr, wantErr: downloadErr},
		{name: "http_error", status: http.StatusNotFound, body: strings.NewReader("missing")},
		{name: "oversized_header", status: http.StatusOK, body: strings.NewReader("script"), contentLength: updateInstallerMaxSize + 1},
		{name: "oversized_body", status: http.StatusOK, body: strings.NewReader(strings.Repeat("x", updateInstallerMaxSize+1)), contentLength: -1},
		{name: "incomplete_body", status: http.StatusOK, body: installerReadError{err: readErr}, wantErr: readErr},
		{name: "empty_body", status: http.StatusOK, body: strings.NewReader("")},
	} {
		t.Run(test.name, func(t *testing.T) {
			client := installerHTTPClientFunc(func(*http.Request) (*http.Response, error) {
				if test.err != nil {
					return nil, test.err
				}
				return &http.Response{StatusCode: test.status, Body: io.NopCloser(test.body), ContentLength: test.contentLength}, nil
			})
			called := false
			err := runUpdateInstaller(context.Background(), client, func(context.Context, string, ...string) error {
				called = true
				return nil
			}, updateInstallerOptions{InstallDir: "/usr/local/bin", ConfigDir: "/etc/V2bX"})
			if err == nil {
				t.Fatal("failed download was accepted")
			}
			if test.wantErr != nil && !errors.Is(err, test.wantErr) {
				t.Fatalf("download error was not preserved: %v", err)
			}
			if called {
				t.Fatal("installer ran after a failed download")
			}
		})
	}
}

func TestUpdateInstallerPassesIndependentArguments(t *testing.T) {
	for _, withOptions := range []bool{false, true} {
		t.Run(map[bool]string{false: "default", true: "version_and_no_service"}[withOptions], func(t *testing.T) {
			const script = "#!/usr/bin/env bash\nexit 0\n"
			client := installerHTTPClientFunc(func(request *http.Request) (*http.Response, error) {
				if request.URL.String() != updateInstallerURL || request.Method != http.MethodGet {
					t.Fatalf("unexpected installer request: %s %s", request.Method, request.URL)
				}
				deadline, ok := request.Context().Deadline()
				if !ok || time.Until(deadline) > updateDownloadTimeout || time.Until(deadline) <= 0 {
					t.Fatal("installer request does not have the download timeout")
				}
				return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(script))}, nil
			})
			options := updateInstallerOptions{InstallDir: "/opt/path with spaces; touch ignored", ConfigDir: "/etc/custom config"}
			wantArgs := []string{"update", "--install-dir", options.InstallDir, "--config-dir", options.ConfigDir, "--yes"}
			if withOptions {
				options.Version = "v1.2.3; touch ignored"
				options.NoService = true
				wantArgs = append(wantArgs, "--version", options.Version, "--no-service")
			}
			var scriptPath string
			called := false
			err := runUpdateInstaller(context.Background(), client, func(_ context.Context, name string, args ...string) error {
				called = true
				if name != "bash" || len(args) == 0 {
					t.Fatalf("unexpected command: %s %v", name, args)
				}
				scriptPath = args[0]
				if !reflect.DeepEqual(args[1:], wantArgs) {
					t.Fatalf("installer arguments = %q, want %q", args[1:], wantArgs)
				}
				content, err := os.ReadFile(scriptPath)
				if err != nil || string(content) != script {
					t.Fatalf("temporary installer = %q, error: %v", content, err)
				}
				return nil
			}, options)
			if err != nil {
				t.Fatal(err)
			}
			if !called {
				t.Fatal("downloaded installer did not run")
			}
			if _, err := os.Stat(scriptPath); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("temporary installer was not removed: %v", err)
			}
		})
	}
}

func TestUpdateInstallerPreservesRunnerError(t *testing.T) {
	client := installerHTTPClientFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader("exit 1\n"))}, nil
	})
	runErr := errors.New("installer failed")
	var scriptPath string
	err := runUpdateInstaller(context.Background(), client, func(_ context.Context, _ string, args ...string) error {
		scriptPath = args[0]
		return runErr
	}, updateInstallerOptions{InstallDir: "/usr/local/bin", ConfigDir: "/etc/V2bX"})
	if !errors.Is(err, runErr) {
		t.Fatalf("installer error was not preserved: %v", err)
	}
	if _, err := os.Stat(scriptPath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("failed installer was not removed: %v", err)
	}
}
