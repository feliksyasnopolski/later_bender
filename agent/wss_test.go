package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestWSSHeartbeatsContinueDuringLongOperation(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	var releaseOnce sync.Once
	var calls atomic.Int32
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	dispatcher := newOperationDispatcherWithExecutor(ctx, &Client{}, Store{}, func(op Operation) map[string]any {
		calls.Add(1)
		close(started)
		<-release
		return map[string]any{"type": "result", "operation_id": op.OperationID, "workspace": op.Workspace, "spec_hash": op.SpecHash, "status": "succeeded"}
	})
	defer releaseOnce.Do(func() { close(release) })

	upgrader := websocket.Upgrader{}
	heartbeats := make(chan struct{}, 4)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		if err := conn.WriteJSON(map[string]any{"type": "operation", "operation": map[string]any{"type": "promote_file", "workspace": "WS-1", "operation_id": "WSOP-slow", "spec_hash": "hash"}}); err != nil {
			return
		}
		deadline := time.Now().Add(26 * time.Second)
		for time.Now().Before(deadline) {
			_ = conn.SetReadDeadline(time.Now().Add(12 * time.Second))
			var message map[string]any
			if err := conn.ReadJSON(&message); err != nil {
				return
			}
			if message["type"] == "heartbeat" {
				heartbeats <- struct{}{}
			}
			if message["type"] == "ping" {
				_ = conn.WriteJSON(map[string]any{"type": "pong", "id": message["id"]})
			}
			if message["type"] == "result" {
				return
			}
		}
	}))
	defer server.Close()

	client := &Client{Base: server.URL, Session: "session", HTTP: server.Client()}
	runDone := make(chan error, 1)
	go func() { runDone <- runWSS(ctx, client, Store{}, &Identity{Name: "agent"}, dispatcher) }()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("operation worker did not start")
	}
	for range 2 {
		select {
		case <-heartbeats:
		case <-time.After(12 * time.Second):
			t.Fatal("heartbeat was starved by the running operation")
		}
	}
	releaseOnce.Do(func() { close(release) })
	select {
	case err := <-runDone:
		if err == nil {
			t.Fatal("WebSocket unexpectedly returned without a result or disconnect")
		}
	case <-time.After(12 * time.Second):
		t.Fatal("operation result was not sent")
	}
	if got := calls.Load(); got != 1 {
		t.Fatalf("operation executed %d times; want once", got)
	}
}

func TestOperationDispatcherDeduplicatesAndKeepsCompletionForReconnect(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started, finish := make(chan struct{}), make(chan struct{})
	var calls atomic.Int32
	d := newOperationDispatcherWithExecutor(ctx, &Client{}, Store{}, func(op Operation) map[string]any {
		calls.Add(1)
		close(started)
		<-finish
		return map[string]any{"type": "result", "operation_id": op.OperationID, "status": "succeeded"}
	})
	op := Operation{Type: "promote_file", Workspace: "WS-2", OperationID: "WSOP-replay", SpecHash: "hash"}
	if err := d.submit(op); err != nil {
		t.Fatal(err)
	}
	<-started
	if err := d.submit(op); err != nil {
		t.Fatal(err)
	}
	close(finish)
	deadline := time.Now().Add(time.Second)
	for len(d.completed()) == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	completed := d.completed()
	if len(completed) != 1 || completed[0].payload["operation_id"] != op.OperationID {
		t.Fatalf("cached completion = %#v", completed)
	}
	if err := d.submit(op); err != nil {
		t.Fatal(err)
	}
	if got := calls.Load(); got != 1 {
		t.Fatalf("duplicate operation executed %d times; want once", got)
	}
	if len(d.completed()) != 1 {
		t.Fatal("completion was not retained for reconnect replay")
	}
	d.acknowledge(op.OperationID)
	if len(d.completed()) != 0 {
		t.Fatal("acknowledged result was retained")
	}
}

func TestWSSReconnectReplaysCompletedOperationWithoutReexecuting(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started, finish := make(chan struct{}), make(chan struct{})
	var finishOnce sync.Once
	var calls atomic.Int32
	d := newOperationDispatcherWithExecutor(ctx, &Client{}, Store{}, func(op Operation) map[string]any {
		calls.Add(1)
		close(started)
		<-finish
		return map[string]any{"type": "result", "operation_id": op.OperationID, "workspace": op.Workspace, "spec_hash": op.SpecHash, "status": "succeeded"}
	})
	defer finishOnce.Do(func() { close(finish) })
	var connections atomic.Int32
	secondResult := make(chan map[string]any, 1)
	secondConnected := make(chan struct{})
	upgrader := websocket.Upgrader{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()
		if connections.Add(1) == 1 {
			_ = conn.WriteJSON(map[string]any{"type": "operation", "operation": map[string]any{"type": "promote_file", "workspace": "WS-3", "operation_id": "WSOP-reconnect", "spec_hash": "hash"}})
			select {
			case <-started:
			case <-time.After(2 * time.Second):
			}
			return
		}
		close(secondConnected)
		_ = conn.WriteJSON(map[string]any{"type": "operation", "operation": map[string]any{"type": "promote_file", "workspace": "WS-3", "operation_id": "WSOP-reconnect", "spec_hash": "hash"}})
		_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		var message map[string]any
		if conn.ReadJSON(&message) == nil {
			secondResult <- message
		}
	}))
	defer server.Close()
	client := &Client{Base: server.URL, Session: "session", HTTP: server.Client()}
	firstDone := make(chan error, 1)
	go func() { firstDone <- runWSS(ctx, client, Store{}, &Identity{Name: "agent"}, d) }()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("operation did not start on first connection")
	}
	select {
	case <-firstDone:
	case <-time.After(2 * time.Second):
		t.Fatal("first WebSocket did not disconnect")
	}
	secondDone := make(chan error, 1)
	go func() { secondDone <- runWSS(ctx, client, Store{}, &Identity{Name: "agent"}, d) }()
	select {
	case <-secondConnected:
		finishOnce.Do(func() { close(finish) })
	case <-time.After(2 * time.Second):
		t.Fatal("second WebSocket did not connect")
	}
	select {
	case result := <-secondResult:
		if result["operation_id"] != "WSOP-reconnect" || result["status"] != "succeeded" {
			t.Fatalf("replayed result = %#v", result)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("completed operation was not replayed after reconnect")
	}
	if got := calls.Load(); got != 1 {
		t.Fatalf("operation executed %d times across reconnect; want once", got)
	}
	select {
	case <-secondDone:
	case <-time.After(2 * time.Second):
		t.Fatal("second WebSocket did not close after replay")
	}
}

func TestOperationDispatcherRejectsOperationIDReuse(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	d := newOperationDispatcherWithExecutor(ctx, &Client{}, Store{}, func(op Operation) map[string]any {
		return map[string]any{"operation_id": op.OperationID}
	})
	if err := d.submit(Operation{Type: "read_file", Workspace: "WS-1", OperationID: "WSOP-same", SpecHash: "one"}); err != nil {
		t.Fatal(err)
	}
	if err := d.submit(Operation{Type: "read_file", Workspace: "WS-1", OperationID: "WSOP-same", SpecHash: "two"}); err == nil {
		t.Fatal("reused operation ID with conflicting spec was accepted")
	}
}

func TestUploadFileReturnsCanonicalFileAcknowledgement(t *testing.T) {
	var requested atomic.Bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requested.Store(r.Header.Get("X-Remote-Operation-Id") == "WSOP-upload")
		_ = json.NewEncoder(w).Encode(map[string]any{"ref": "LB-F1", "filename": "artifact.bin", "media_type": "application/octet-stream", "byte_size": 3, "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"})
	}))
	defer server.Close()
	client := &Client{Base: server.URL, Session: "session", HTTP: server.Client()}
	ack, err := client.uploadFile(context.Background(), "WS-1", "WSOP-upload", []byte("abc"))
	if err != nil {
		t.Fatal(err)
	}
	if !requested.Load() || ack["ref"] != "LB-F1" || ack["byte_size"] != "3" {
		t.Fatalf("upload acknowledgement = %#v, request operation ID applied=%v", ack, requested.Load())
	}
}

func TestFileTransfersUseTimeoutLongerThanDefaultAgentRequestTimeout(t *testing.T) {
	client := &Client{HTTP: &http.Client{Timeout: 20 * time.Second}}
	transfer := client.fileTransferHTTP()
	if transfer.Timeout < 20*time.Second || transfer.Timeout != fileTransferTimeout {
		t.Fatalf("file transfer timeout = %s, want %s", transfer.Timeout, fileTransferTimeout)
	}
	if client.HTTP.Timeout != 20*time.Second {
		t.Fatal("file transfer timeout mutation leaked into ordinary API client")
	}
}
