package cmd

import (
	"bytes"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	log "github.com/sirupsen/logrus"
)

func TestConfigureLogOutputInvalidPathFallsBackToStdout(t *testing.T) {
	logger := log.StandardLogger()
	previousOutput, previousLevel := logger.Out, logger.GetLevel()
	defer logger.SetOutput(previousOutput)
	defer logger.SetLevel(previousLevel)
	logger.SetOutput(&bytes.Buffer{})
	logger.SetLevel(log.InfoLevel)

	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	defer writer.Close()
	previousStdout := os.Stdout
	os.Stdout = writer
	defer func() { os.Stdout = previousStdout }()

	outputBeforeSetup := logger.Out
	func() {
		cleanup := configureLogOutput(filepath.Join(t.TempDir(), "missing", "server.log"))
		defer cleanup()
		logger.Info("server continues after log open failure")
	}()
	if logger.Out != outputBeforeSetup {
		t.Fatal("previous log output was not restored")
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	logged, err := io.ReadAll(reader)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logged), "server continues after log open failure") {
		t.Fatalf("log output was lost after an invalid log path: %s", logged)
	}
}

func TestConfigureLogOutputClosesFileAndRestoresOutput(t *testing.T) {
	logger := log.StandardLogger()
	previousOutput, previousLevel := logger.Out, logger.GetLevel()
	defer logger.SetOutput(previousOutput)
	defer logger.SetLevel(previousLevel)
	previousBuffer := &bytes.Buffer{}
	logger.SetOutput(previousBuffer)
	logger.SetLevel(log.InfoLevel)

	path := filepath.Join(t.TempDir(), "server.log")
	var outputFile *os.File
	func() {
		cleanup := configureLogOutput(path)
		defer cleanup()
		var ok bool
		outputFile, ok = logger.Out.(*os.File)
		if !ok {
			t.Fatal("log output is not a file")
		}
		logger.Info("message written to configured file")
	}()
	if logger.Out != previousBuffer {
		t.Fatal("previous log output was not restored")
	}
	if _, err := outputFile.WriteString("must not be written"); !errors.Is(err, os.ErrClosed) {
		t.Fatalf("log file is still open after cleanup: %v", err)
	}
	logged, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(logged), "message written to configured file") {
		t.Fatalf("configured file did not receive logs: %s", logged)
	}
	logger.Info("message written after cleanup")
	if !strings.Contains(previousBuffer.String(), "message written after cleanup") {
		t.Fatal("logging did not return to the previous output after cleanup")
	}
}
