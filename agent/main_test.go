package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

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
