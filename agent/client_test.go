package main

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestEnrollmentAndChallengeAuthenticationUseBackendContract(t *testing.T) {
	var enrollment map[string]any
	session := "session-token"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if r.Body != nil {
			_ = json.NewDecoder(r.Body).Decode(&body)
		}
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/api/remote-agent/enroll":
			enrollment = body
			if _, found := body["private_key"]; found {
				t.Error("private key was sent during enrollment")
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"ref": "RA-1"})
		case "/api/remote-agent/challenge":
			_ = json.NewEncoder(w).Encode(map[string]string{"challenge_id": "challenge-1", "nonce": "nonce-1", "signed_bytes": "later-bender-agent-auth-v1\nRA-1\nchallenge-1\nnonce-1\n2026-09-21T12:00:00.000000Z"})
		case "/api/remote-agent/authenticate":
			public, _ := base64.StdEncoding.DecodeString(enrollment["public_key"].(string))
			sig, _ := base64.StdEncoding.DecodeString(body["signature"].(string))
			bytes := []byte("later-bender-agent-auth-v1\nRA-1\nchallenge-1\nnonce-1\n2026-09-21T12:00:00.000000Z")
			if !ed25519.Verify(ed25519.PublicKey(public), bytes, sig) {
				t.Error("backend could not verify challenge signature")
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"session_token": session, "heartbeat_interval_seconds": 30})
		default:
			t.Fatalf("unexpected request %s", r.URL.Path)
		}
	}))
	defer server.Close()

	store := Store{Dir: t.TempDir()}
	client := &Client{Base: server.URL, HTTP: server.Client()}
	if err := enroll(context.Background(), client, store, "Test Agent", "enrollment-token"); err != nil {
		t.Fatal(err)
	}
	id, err := store.load()
	if err != nil {
		t.Fatal(err)
	}
	keyBytes, _ := base64.StdEncoding.DecodeString(id.PrivateKey)
	if enrollment["public_key"] != base64.StdEncoding.EncodeToString(ed25519.PrivateKey(keyBytes).Public().(ed25519.PublicKey)) {
		t.Fatal("enrollment public key does not match persisted private key")
	}
	if _, err := authenticate(context.Background(), client, id); err != nil {
		t.Fatal(err)
	}
	if client.Session != session {
		t.Fatalf("session = %q", client.Session)
	}
	if !strings.HasPrefix(id.ServerURL, "http") {
		t.Fatal("server URL not persisted")
	}
}

func TestWebsocketURLUsesTheAuthenticatedTransportEndpoint(t *testing.T) {
	if got := websocketURL("https://laterbender-api.example/base"); got != "wss://laterbender-api.example/api/remote-agent/stream" {
		t.Fatalf("websocket URL = %q", got)
	}
	if got := websocketURL("http://127.0.0.1:3000"); got != "ws://127.0.0.1:3000/api/remote-agent/stream" {
		t.Fatalf("websocket URL = %q", got)
	}
}

func TestRTTHealthRequiresTwoMateriallyDegradedSamples(t *testing.T) {
	var health rttHealth
	if health.observe(100 * time.Millisecond) {
		t.Fatal("baseline sample marked degraded")
	}
	if health.observe(110 * time.Millisecond) {
		t.Fatal("normal sample marked degraded")
	}
	if health.observe(500 * time.Millisecond) {
		t.Fatal("one RTT spike triggered reconnect")
	}
	if !health.observe(500 * time.Millisecond) {
		t.Fatal("sustained RTT degradation did not trigger reconnect")
	}
}
