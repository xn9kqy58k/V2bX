package cmd

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	osExec "os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/InazumaV/V2bX/common/exec"
	"github.com/spf13/cobra"
)

const (
	updateInstallerURL     = "https://raw.githubusercontent.com/xn9kqy58k/V2bX/dev_new/scripts/install.sh"
	updateDownloadTimeout  = 30 * time.Second
	updateInstallerMaxSize = 1024 * 1024
)

var (
	targetVersion   string
	updateConfigDir string
	updateNoService bool
)

var (
	updateCommand = cobra.Command{
		Use:   "update",
		Short: "Update V2bX version",
		RunE: func(cmd *cobra.Command, _ []string) error {
			executable, err := os.Executable()
			if err != nil {
				return fmt.Errorf("locate current executable: %w", err)
			}
			executable, err = filepath.EvalSymlinks(executable)
			if err != nil {
				return fmt.Errorf("resolve current executable: %w", err)
			}
			return runUpdateInstaller(cmd.Context(), http.DefaultClient, runInstallerCommand, updateInstallerOptions{
				Version:    targetVersion,
				InstallDir: filepath.Dir(executable),
				ConfigDir:  updateConfigDir,
				NoService:  updateNoService,
			})
		},
		Args: cobra.NoArgs,
	}
	uninstallCommand = cobra.Command{
		Use:   "uninstall",
		Short: "Uninstall V2bX",
		Run:   uninstallHandle,
	}
)

func init() {
	updateCommand.PersistentFlags().StringVar(&targetVersion, "version", "", "update target version")
	updateCommand.PersistentFlags().StringVar(&updateConfigDir, "config-dir", "/etc/V2bX", "configuration directory to preserve")
	updateCommand.PersistentFlags().BoolVar(&updateNoService, "no-service", false, "update files without managing the systemd service")
	command.AddCommand(&updateCommand)
	command.AddCommand(&uninstallCommand)
}

type installerHTTPClient interface {
	Do(*http.Request) (*http.Response, error)
}

type installerCommandRunner func(context.Context, string, ...string) error

type updateInstallerOptions struct {
	Version    string
	InstallDir string
	ConfigDir  string
	NoService  bool
}

func runUpdateInstaller(ctx context.Context, client installerHTTPClient, run installerCommandRunner, options updateInstallerOptions) error {
	downloadCtx, cancel := context.WithTimeout(ctx, updateDownloadTimeout)
	defer cancel()
	request, err := http.NewRequestWithContext(downloadCtx, http.MethodGet, updateInstallerURL, nil)
	if err != nil {
		return fmt.Errorf("create installer request: %w", err)
	}
	response, err := client.Do(request)
	if err != nil {
		return fmt.Errorf("download update installer: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("download update installer: HTTP status %d", response.StatusCode)
	}
	if response.ContentLength > updateInstallerMaxSize {
		return fmt.Errorf("update installer exceeds %d bytes", updateInstallerMaxSize)
	}
	file, err := os.CreateTemp("", "v2bx-install-*.sh")
	if err != nil {
		return fmt.Errorf("create temporary installer: %w", err)
	}
	defer os.Remove(file.Name())
	written, copyErr := io.Copy(file, io.LimitReader(response.Body, updateInstallerMaxSize+1))
	closeErr := file.Close()
	if copyErr != nil {
		return fmt.Errorf("save update installer: %w", copyErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close temporary installer: %w", closeErr)
	}
	if written == 0 || written > updateInstallerMaxSize {
		return fmt.Errorf("invalid update installer size: %d bytes", written)
	}
	args := []string{file.Name(), "update", "--install-dir", options.InstallDir, "--config-dir", options.ConfigDir, "--yes"}
	if options.Version != "" {
		args = append(args, "--version", options.Version)
	}
	if options.NoService {
		args = append(args, "--no-service")
	}
	if err := run(ctx, "bash", args...); err != nil {
		return fmt.Errorf("run update installer: %w", err)
	}
	return nil
}

func runInstallerCommand(ctx context.Context, name string, args ...string) error {
	command := osExec.CommandContext(ctx, name, args...)
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command.Run()
}

func uninstallHandle(_ *cobra.Command, _ []string) {
	var yes string
	fmt.Println(Warn("确定要卸载 V2bX 吗?(Y/n)"))
	fmt.Scan(&yes)
	if strings.ToLower(yes) != "y" {
		fmt.Println("已取消卸载")
		return
	}
	_, err := exec.RunCommandByShell("systemctl stop V2bX&&systemctl disable V2bX")
	if err != nil {
		fmt.Println(Err("exec cmd error: ", err))
		fmt.Println(Err("卸载失败"))
		return
	}
	_ = os.RemoveAll("/etc/systemd/system/V2bX.service")
	_ = os.RemoveAll("/etc/V2bX/")
	_ = os.RemoveAll("/usr/local/V2bX/")
	_ = os.RemoveAll("/bin/V2bX")
	_, err = exec.RunCommandByShell("systemctl daemon-reload&&systemctl reset-failed")
	if err != nil {
		fmt.Println(Err("exec cmd error: ", err))
		fmt.Println(Err("卸载失败"))
		return
	}
	fmt.Println(Ok("卸载成功"))
}
