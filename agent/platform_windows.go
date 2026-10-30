//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

const (
	ptySupported             = false
	processControlCapability = "taskkill_tree"
)

func shellInvocation(command, root string, externalRoot bool) []string {
	return []string{"cmd.exe", "/D", "/S", "/C", nativeShellCommand(command, root, externalRoot)}
}

func nativeShellCommand(command, root string, externalRoot bool) string {
	if externalRoot {
		return command
	}
	return rewriteWindowsShellPaths(command, root)
}

func startNativeCommand(cmd *exec.Cmd, usePTY bool) (*os.File, error) {
	if usePTY {
		return nil, fmt.Errorf("PTY execution is not supported on Windows")
	}
	return nil, cmd.Start()
}

func processIsAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	out, err := exec.Command("tasklist.exe", "/FO", "CSV", "/NH", "/FI", fmt.Sprintf("PID eq %d", pid)).Output()
	return err == nil && strings.Contains(string(out), fmt.Sprintf(",\"%d\",", pid))
}

func terminateProcess(pid int, force bool) error {
	if pid <= 0 {
		return fmt.Errorf("invalid process id")
	}
	args := []string{"/T", "/PID", strconv.Itoa(pid)}
	if force {
		args = append(args, "/F")
	}
	return exec.Command("taskkill.exe", args...).Run()
}

func credentialOpenFlags() int { return 0 }

func rewriteWindowsShellPaths(value, root string) string {
	quote := func(path string) string { return `"` + strings.ReplaceAll(path, `"`, `\"`) + `"` }
	return strings.ReplaceAll(value, "/workspace", quote(root))
}
