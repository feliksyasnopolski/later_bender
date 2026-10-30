//go:build !windows

package main

import (
	"os"
	"os/exec"
	"strings"
	"syscall"

	"github.com/creack/pty"
)

const (
	ptySupported             = true
	processControlCapability = "process_group"
)

func shellInvocation(command, root string, externalRoot bool) []string {
	return []string{"/bin/bash", "-lc", nativeShellCommand(command, root, externalRoot)}
}

func nativeShellCommand(command, root string, externalRoot bool) string {
	if externalRoot {
		return command
	}
	return rewriteShellNativePaths(command, root)
}

func startNativeCommand(cmd *exec.Cmd, usePTY bool) (*os.File, error) {
	if usePTY {
		return pty.Start(cmd)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	return nil, cmd.Start()
}

func processIsAlive(pid int) bool {
	return pid > 0 && syscall.Kill(pid, 0) == nil
}

func terminateProcess(pid int, force bool) error {
	signal := syscall.SIGTERM
	if force {
		signal = syscall.SIGKILL
	}
	return syscall.Kill(-pid, signal)
}

func credentialOpenFlags() int { return syscall.O_NOFOLLOW }

func rewriteShellNativePaths(value, root string) string {
	quotedRoot := "'" + strings.ReplaceAll(root, "'", "'\\''") + "'"
	return strings.ReplaceAll(value, "/workspace", quotedRoot)
}
