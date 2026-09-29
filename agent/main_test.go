package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestNativeExecutionCapturesOutputAndUsesStableIdentity(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	if _, err := s.prepare("WS-8", "native", "WSOP-prepare", "hash"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.prepare("WS-9", "native", "WSOP-prepare-9", "hash-9"); err != nil {
		t.Fatal(err)
	}
	op := Operation{Type: "start_execution", Workspace: "WS-8", Execution: "WSE-8", OperationID: "WSOP-exec", Executor: "native", SpecHash: "exec-hash", Spec: map[string]any{
		"invocation": map[string]any{"kind": "argv", "argv": []any{"/bin/sh", "-c", "printf native-output"}},
		"cwd":        "/workspace", "env": map[string]any{},
	}}
	e, err := startNative(s, op)
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		e.mu.Lock()
		state := e.State
		e.mu.Unlock()
		if state != "running" {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	e.mu.Lock()
	state := e.State
	e.mu.Unlock()
	if state != "exited" {
		t.Fatalf("state = %s", state)
	}
	output, err := os.ReadFile(e.Stdout)
	if err != nil {
		t.Fatal(err)
	}
	if string(output) != "native-output" {
		t.Fatalf("output = %q", output)
	}
	if again, ok := localExecution(op); !ok || again != e {
		t.Fatal("execution identity was not reused")
	}
}

func TestSecondWorkspacePreparationDoesNotBreakFirstWorkspaceExecution(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	first, err := s.prepare("WS-1", "native", "WSOP-1", "hash-1")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.prepare("WS-2", "native", "WSOP-2", "hash-2"); err != nil {
		t.Fatal(err)
	}
	op := Operation{Type: "start_execution", Workspace: "WS-1", Execution: "WSE-2", OperationID: "WSOP-exec-2", Executor: "native", SpecHash: "exec-hash", Spec: map[string]any{
		"invocation": map[string]any{"kind": "argv", "argv": []any{"/bin/pwd"}}, "cwd": "/workspace", "env": map[string]any{},
	}}
	e, err := startNative(s, op)
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		e.mu.Lock()
		state := e.State
		e.mu.Unlock()
		if state != "running" {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if e.State != "exited" {
		t.Fatalf("execution state = %s", e.State)
	}
	output, err := os.ReadFile(e.Stdout)
	expected, evalErr := filepath.EvalSymlinks(filepath.Join(first.Root, "root"))
	if err != nil || evalErr != nil || string(output) != expected+"\n" {
		t.Fatalf("pwd output = %q, error = %v", output, err)
	}
}

func TestFailedSecondWorkspacePreparationDoesNotBreakFirstWorkspaceExecution(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	if _, err := s.prepare("WS-1", "native", "WSOP-1", "hash-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.prepare("WS-2", "native", "WSOP-2", "hash-2"); err != nil {
		t.Fatal(err)
	}
	failed := false
	prepare := Operation{Type: "prepare_workspace", Workspace: "WS-2", OperationID: "WSOP-2", Executor: "native", SpecHash: "wrong-hash"}
	if err := handleOperationWithResult(context.Background(), &Client{}, s, prepare, func(status string, extra map[string]string) error {
		failed = status == "failed" && extra["code"] == "workspace_prepare_failed" && extra["stage"] == "prepare" && strings.Contains(extra["message"], "incompatible spec")
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if !failed {
		t.Fatal("incompatible prepare did not return structured failure details")
	}
	op := Operation{Type: "start_execution", Workspace: "WS-1", Execution: "WSE-1", OperationID: "WSOP-exec-1", Executor: "native", SpecHash: "exec-hash", Spec: map[string]any{
		"invocation": map[string]any{"kind": "argv", "argv": []any{"/bin/pwd"}}, "cwd": "/workspace", "env": map[string]any{},
	}}
	e, err := startNative(s, op)
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		e.mu.Lock()
		state := e.State
		e.mu.Unlock()
		if state != "running" {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if e.State != "exited" {
		t.Fatalf("execution state = %s", e.State)
	}
}

func TestNativeExecutionRejectsWorkingDirectoryOutsideWorkspace(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	if _, err := s.prepare("WS-10", "native", "WSOP-10", "hash-10"); err != nil {
		t.Fatal(err)
	}
	op := Operation{Type: "start_execution", Workspace: "WS-10", Execution: "WSE-outside-cwd", OperationID: "WSOP-outside-cwd", Executor: "native", SpecHash: "exec-hash", Spec: map[string]any{
		"invocation": map[string]any{"kind": "argv", "argv": []any{"/bin/pwd"}}, "cwd": "/Users/felix", "env": map[string]any{},
	}}
	if _, err := startNative(s, op); err == nil || !strings.Contains(err.Error(), "cwd escapes Workspace root") {
		t.Fatalf("out-of-Workspace cwd error = %v", err)
	}
}

func TestCredentialFilesAreCreateOnlyAndWorkspaceScoped(t *testing.T) {
	root := t.TempDir()
	w := &Workspace{Root: root}
	workspaceRoot := filepath.Join(root, "root")
	if err := os.MkdirAll(workspaceRoot, 0700); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(workspaceRoot, "root", "id_ed25519")
	if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
		t.Fatal(err)
	}
	sentinel := []byte("pre-existing sentinel")
	if err := os.WriteFile(target, sentinel, 0600); err != nil {
		t.Fatal(err)
	}
	before, err := os.Lstat(target)
	if err != nil {
		t.Fatal(err)
	}
	if err := ensureCredentialPathAvailable(w, target); err == nil {
		t.Fatal("accepted an existing credential target")
	}
	after, err := os.Lstat(target)
	if err != nil {
		t.Fatal(err)
	}
	if before.Sys().(*syscall.Stat_t).Ino != after.Sys().(*syscall.Stat_t).Ino {
		t.Fatal("existing credential inode changed")
	}
	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(sentinel) || after.Mode().Perm() != 0600 {
		t.Fatal("existing credential file changed")
	}

	symlink := filepath.Join(workspaceRoot, "root", "linked")
	if err := os.Symlink(target, symlink); err != nil {
		t.Fatal(err)
	}
	if err := ensureCredentialPathAvailable(w, symlink); err == nil {
		t.Fatal("accepted a symlink credential target")
	}
	if _, err := os.Lstat(symlink); err != nil {
		t.Fatal(err)
	}
}

func TestRewriteNativePathsKeepsLogicalWorkspacePathsAgentOwned(t *testing.T) {
	root := "/private/var/felix/workspaces/WS-1/root"
	got := rewriteNativePaths("cat /workspace/input && test -f /root/id_ed25519", root)
	want := "cat /private/var/felix/workspaces/WS-1/root/input && test -f /private/var/felix/workspaces/WS-1/root/root/id_ed25519"
	if got != want {
		t.Fatalf("rewritten command = %q, want %q", got, want)
	}
	shell := rewriteShellNativePaths("sha256sum /workspace/input", root)
	if shell != "sha256sum '/private/var/felix/workspaces/WS-1/root'/input" {
		t.Fatalf("shell rewrite = %q", shell)
	}
}

func TestStorePrepareIsIdempotentAndRejectsChangedSpec(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	a, err := s.prepare("WS-7", "native", "WSOP-1", "abc")
	if err != nil {
		t.Fatal(err)
	}
	b, err := s.prepare("WS-7", "native", "WSOP-1", "abc")
	if err != nil {
		t.Fatal(err)
	}
	if a.Root != b.Root {
		t.Fatalf("duplicate prepare changed root: %q != %q", a.Root, b.Root)
	}
	entries, err := os.ReadDir(filepath.Join(s.Dir, "workspaces"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("got %d workspace directories, want 1", len(entries))
	}
	if _, err := s.prepare("WS-7", "native", "WSOP-1", "different"); err == nil {
		t.Fatal("changed spec unexpectedly succeeded for same operation")
	}
	if err := os.WriteFile(filepath.Join(a.Root, "root", "retained.txt"), []byte("old data"), 0600); err != nil {
		t.Fatal(err)
	}
	c, err := s.prepare("WS-7", "native", "WSOP-2", "different")
	if err != nil {
		t.Fatal(err)
	}
	if c.Root != a.Root {
		t.Fatalf("new incarnation changed active workspace root: %q != %q", c.Root, a.Root)
	}
	archived := s.retiredWorkspaceDir("WS-7", "WSOP-1")
	if got, err := os.ReadFile(filepath.Join(archived, "root", "retained.txt")); err != nil || string(got) != "old data" {
		t.Fatalf("prior Workspace data was not retained: %q, %v", got, err)
	}
	if _, err := os.Stat(filepath.Join(c.Root, "root", "retained.txt")); !os.IsNotExist(err) {
		t.Fatalf("new Workspace inherited prior filesystem data: %v", err)
	}
	if err := s.destroy("WS-7"); err != nil {
		t.Fatal(err)
	}
	if err := s.destroy("WS-7"); err != nil {
		t.Fatal(err)
	}
}

func TestWorkspaceRefCannotEscapeState(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	for _, ref := range []string{"../x", "WS-../x", "WS-1/root", "WS-abc"} {
		if _, err := s.prepare(ref, "native", "op", "hash"); err == nil {
			t.Errorf("accepted malformed ref %q", ref)
		}
	}
}

func TestIdentityRoundTripAndRestrictiveMode(t *testing.T) {
	_, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	s := Store{Dir: t.TempDir()}
	id := &Identity{Ref: "RA-1", ServerURL: "https://example.test", PrivateKey: base64.StdEncoding.EncodeToString(private)}
	if err := s.saveIdentity(id); err != nil {
		t.Fatal(err)
	}
	got, err := s.load()
	if err != nil {
		t.Fatal(err)
	}
	if got.Ref != id.Ref || got.PrivateKey != id.PrivateKey {
		t.Fatal("identity did not round trip")
	}
	info, err := os.Stat(s.identityPath())
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0077 != 0 {
		t.Fatalf("identity mode %o is not private", info.Mode().Perm())
	}
}
