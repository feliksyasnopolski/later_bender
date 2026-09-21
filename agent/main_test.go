package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestNativeExecutionCapturesOutputAndUsesStableIdentity(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	if _, err := s.prepare("WS-8", "native", "WSOP-prepare", "hash"); err != nil {
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

func TestStorePrepareIsIdempotentAndRejectsChangedSpec(t *testing.T) {
	s := Store{Dir: t.TempDir()}
	a, err := s.prepare("WS-7", "native", "WSOP-1", "abc")
	if err != nil {
		t.Fatal(err)
	}
	b, err := s.prepare("WS-7", "native", "WSOP-2", "abc")
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
	if _, err := s.prepare("WS-7", "native", "WSOP-3", "different"); err == nil {
		t.Fatal("changed spec unexpectedly succeeded")
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
