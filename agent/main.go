package main

import (
	"context"
	"crypto"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

const protocolVersion = "later-bender-agent-auth-v1"

type Identity struct {
	Name       string `json:"name"`
	Ref        string `json:"ref"`
	ServerURL  string `json:"server_url"`
	PrivateKey string `json:"private_key"`
}

type Workspace struct {
	Workspace  string    `json:"workspace"`
	Executor   string    `json:"executor"`
	Operation  string    `json:"operation_id"`
	SpecHash   string    `json:"spec_hash"`
	Root       string    `json:"root"`
	PreparedAt time.Time `json:"prepared_at"`
}

type Store struct{ Dir string }

type LocalExecution struct {
	Execution         string     `json:"execution"`
	Workspace         string     `json:"workspace"`
	SpecHash          string     `json:"spec_hash"`
	State             string     `json:"state"`
	PID               int        `json:"pid"`
	ProcessGroup      int        `json:"process_group"`
	StartedAt         time.Time  `json:"started_at"`
	FinishedAt        *time.Time `json:"finished_at,omitempty"`
	ExitCode          *int       `json:"exit_code,omitempty"`
	TerminatingSignal string     `json:"terminating_signal,omitempty"`
	Stdout            string     `json:"stdout"`
	Stderr            string     `json:"stderr"`
	mu                sync.Mutex
	cmd               *exec.Cmd
	timedOut          bool
	cancelled         bool
}

type boundedOutput struct {
	file    *os.File
	written int
}

func (w *boundedOutput) Write(p []byte) (int, error) {
	original := len(p)
	if w.written >= 1024*1024 {
		return original, nil
	}
	limit := 1024*1024 - w.written
	if len(p) > limit {
		p = p[:limit]
	}
	n, err := w.file.Write(p)
	w.written += n
	if n < len(p) {
		return n, err
	}
	return original, err
}

var executionMu sync.Mutex
var executions = map[string]*LocalExecution{}

func (s Store) identityPath() string           { return filepath.Join(s.Dir, "identity.json") }
func (s Store) workspaceDir(ref string) string { return filepath.Join(s.Dir, "workspaces", ref) }
func (s Store) executionDir(ref string) string { return filepath.Join(s.Dir, "executions", ref) }

func (s Store) load() (*Identity, error) {
	b, err := os.ReadFile(s.identityPath())
	if err != nil {
		return nil, err
	}
	var id Identity
	if err := json.Unmarshal(b, &id); err != nil {
		return nil, fmt.Errorf("invalid identity state: %w", err)
	}
	if id.Ref == "" || id.ServerURL == "" || id.PrivateKey == "" {
		return nil, errors.New("invalid identity state: incomplete identity")
	}
	key, err := base64.StdEncoding.DecodeString(id.PrivateKey)
	if err != nil || len(key) != ed25519.PrivateKeySize {
		return nil, errors.New("invalid identity state: private key")
	}
	return &id, nil
}

func atomicJSON(path string, value any, mode os.FileMode) error {
	b, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".state-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err = tmp.Chmod(mode); err == nil {
		_, err = tmp.Write(append(b, '\n'))
	}
	if closeErr := tmp.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}

func (s Store) saveIdentity(id *Identity) error {
	if err := os.MkdirAll(s.Dir, 0700); err != nil {
		return err
	}
	return atomicJSON(s.identityPath(), id, 0600)
}

func (s Store) loadWorkspace(ref string) (*Workspace, error) {
	if !validWorkspaceRef(ref) {
		return nil, errors.New("invalid Workspace ref")
	}
	b, err := os.ReadFile(filepath.Join(s.workspaceDir(ref), "metadata.json"))
	if err != nil {
		return nil, err
	}
	var w Workspace
	if err := json.Unmarshal(b, &w); err != nil {
		return nil, fmt.Errorf("invalid Workspace state: %w", err)
	}
	if w.Workspace != ref || w.Root != s.workspaceDir(ref) || w.SpecHash == "" {
		return nil, errors.New("invalid Workspace state: inconsistent metadata")
	}
	return &w, nil
}

func (s Store) prepare(ref, executor, op, specHash string) (*Workspace, error) {
	if !validWorkspaceRef(ref) || executor != "native" || op == "" || specHash == "" {
		return nil, errors.New("invalid prepare request")
	}
	if old, err := s.loadWorkspace(ref); err == nil {
		if old.SpecHash != specHash || old.Executor != executor {
			return nil, errors.New("Workspace already prepared with incompatible spec")
		}
		return old, nil
	} else if !os.IsNotExist(err) {
		return nil, err
	}
	dir := s.workspaceDir(ref)
	root := filepath.Join(dir, "root")
	if err := os.MkdirAll(root, 0700); err != nil {
		return nil, err
	}
	w := &Workspace{Workspace: ref, Executor: executor, Operation: op, SpecHash: specHash, Root: dir, PreparedAt: time.Now().UTC()}
	if err := atomicJSON(filepath.Join(dir, "metadata.json"), w, 0600); err != nil {
		return nil, err
	}
	return w, nil
}

func (s Store) destroy(ref string) error {
	if !validWorkspaceRef(ref) {
		return errors.New("invalid Workspace ref")
	}
	dir := s.workspaceDir(ref)
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		return nil
	} else if err != nil {
		return err
	}
	return os.RemoveAll(dir)
}

func validWorkspaceRef(ref string) bool {
	if !strings.HasPrefix(ref, "WS-") || len(ref) < 4 || len(ref) > 80 {
		return false
	}
	for _, r := range ref[3:] {
		if !(r >= '0' && r <= '9') {
			return false
		}
	}
	return true
}

type Client struct {
	Base    string
	HTTP    *http.Client
	Token   string
	Session string
}

func (c *Client) post(ctx context.Context, path string, body any, auth bool, out any) error {
	b, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.Base+path, strings.NewReader(string(b)))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if auth {
		req.Header.Set("Authorization", "Bearer "+c.Session)
	}
	return c.do(req, out)
}
func (c *Client) get(ctx context.Context, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.Base+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.Session)
	return c.do(req, out)
}
func (c *Client) do(req *http.Request, out any) error {
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("server returned %s: %s", resp.Status, strings.TrimSpace(string(b)))
	}
	if out != nil && len(b) > 0 {
		return json.Unmarshal(b, out)
	}
	return nil
}

type Advertisement struct {
	Name               string         `json:"name"`
	Platform           string         `json:"platform"`
	Architecture       string         `json:"architecture"`
	SupportedExecutors []string       `json:"supported_executors"`
	Capabilities       map[string]any `json:"capabilities"`
}

func advertise(name string) Advertisement {
	return Advertisement{Name: name, Platform: runtime.GOOS, Architecture: runtime.GOARCH, SupportedExecutors: []string{"native"}, Capabilities: map[string]any{"process_control": "process_group", "isolation": "none", "hardware_access": "host"}}
}

func enroll(ctx context.Context, c *Client, store Store, name, token string) error {
	if _, err := os.Stat(store.identityPath()); err == nil {
		return errors.New("identity already exists; refusing to enroll a second identity")
	} else if !os.IsNotExist(err) {
		return err
	}
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	adv := advertise(name)
	payload := map[string]any{"enrollment_token": token, "public_key": base64.StdEncoding.EncodeToString(pub), "name": adv.Name, "platform": adv.Platform, "architecture": adv.Architecture, "supported_executors": adv.SupportedExecutors, "capabilities": adv.Capabilities}
	var result struct {
		Ref string `json:"ref"`
	}
	if err := c.post(ctx, "/api/remote-agent/enroll", payload, false, &result); err != nil {
		return err
	}
	if result.Ref == "" {
		return errors.New("enrollment response omitted agent ref")
	}
	id := &Identity{Name: name, Ref: result.Ref, ServerURL: c.Base, PrivateKey: base64.StdEncoding.EncodeToString(priv)}
	if err := store.saveIdentity(id); err != nil {
		return fmt.Errorf("persist enrollment: %w", err)
	}
	log.Printf("enrolled Agent %s", result.Ref)
	return nil
}

func authenticate(ctx context.Context, c *Client, id *Identity) (int, error) {
	var ch struct {
		ChallengeID string `json:"challenge_id"`
		Nonce       string `json:"nonce"`
		SignedBytes string `json:"signed_bytes"`
	}
	if err := c.post(ctx, "/api/remote-agent/challenge", map[string]string{"agent": id.Ref}, false, &ch); err != nil {
		return 0, err
	}
	keyBytes, _ := base64.StdEncoding.DecodeString(id.PrivateKey)
	sig, err := ed25519.PrivateKey(keyBytes).Sign(rand.Reader, []byte(ch.SignedBytes), crypto.Hash(0))
	if err != nil {
		return 0, fmt.Errorf("sign challenge: %w", err)
	}
	var result struct {
		SessionToken string `json:"session_token"`
		Heartbeat    int    `json:"heartbeat_interval_seconds"`
	}
	payload := map[string]string{"agent": id.Ref, "challenge_id": ch.ChallengeID, "nonce": ch.Nonce, "signature": base64.StdEncoding.EncodeToString(sig)}
	if err := c.post(ctx, "/api/remote-agent/authenticate", payload, false, &result); err != nil {
		return 0, err
	}
	if result.SessionToken == "" {
		return 0, errors.New("authentication response omitted session token")
	}
	c.Session = result.SessionToken
	if result.Heartbeat < 1 {
		result.Heartbeat = 30
	}
	return result.Heartbeat, nil
}

type Operation struct {
	Type        string         `json:"type"`
	Workspace   string         `json:"workspace"`
	OperationID string         `json:"operation_id"`
	Executor    string         `json:"executor"`
	SpecHash    string         `json:"spec_hash"`
	Spec        map[string]any `json:"spec"`
	Execution   string         `json:"execution"`
}

func (c *Client) result(ctx context.Context, op Operation, status string, extra map[string]string) error {
	p := map[string]any{"operation_id": op.OperationID, "workspace": op.Workspace, "spec_hash": op.SpecHash, "status": status}
	for k, v := range extra {
		p[k] = v
	}
	return c.post(ctx, "/api/remote-agent/operations/"+url.PathEscape(op.OperationID)+"/result", p, true, &struct{}{})
}

func localExecution(op Operation) (*LocalExecution, bool) {
	executionMu.Lock()
	defer executionMu.Unlock()
	e, ok := executions[op.Execution]
	return e, ok
}

func startNative(s Store, op Operation) (*LocalExecution, error) {
	if op.Execution == "" || op.SpecHash == "" || op.Executor != "native" {
		return nil, errors.New("invalid execution request")
	}
	if e, ok := localExecution(op); ok {
		if e.SpecHash != op.SpecHash || e.Workspace != op.Workspace {
			return nil, errors.New("execution identity conflicts with existing spec")
		}
		return e, nil
	}
	if secretNames, _ := op.Spec["secret_env_names"].([]any); len(secretNames) > 0 {
		return nil, errors.New("remote secret_env is not supported")
	}
	w, err := s.loadWorkspace(op.Workspace)
	if err != nil {
		return nil, err
	}
	if b, readErr := os.ReadFile(filepath.Join(s.executionDir(op.Execution), "metadata.json")); readErr == nil {
		var existing LocalExecution
		if jsonErr := json.Unmarshal(b, &existing); jsonErr == nil {
			if existing.SpecHash != op.SpecHash || existing.Workspace != op.Workspace {
				return nil, errors.New("execution identity conflicts with existing spec")
			}
			executionMu.Lock()
			executions[op.Execution] = &existing
			executionMu.Unlock()
			return &existing, nil
		}
	}
	invocation, ok := op.Spec["invocation"].(map[string]any)
	if !ok {
		return nil, errors.New("missing invocation")
	}
	var argv []string
	switch invocation["kind"] {
	case "shell":
		command, ok := invocation["command"].(string)
		if !ok {
			return nil, errors.New("invalid shell invocation")
		}
		argv = []string{"/bin/bash", "-lc", command}
	case "argv":
		values, ok := invocation["argv"].([]any)
		if !ok || len(values) == 0 {
			return nil, errors.New("invalid argv invocation")
		}
		for _, value := range values {
			item, ok := value.(string)
			if !ok {
				return nil, errors.New("invalid argv value")
			}
			argv = append(argv, item)
		}
	default:
		return nil, errors.New("invalid invocation kind")
	}
	cwd, _ := op.Spec["cwd"].(string)
	root := filepath.Join(w.Root, "root")
	if cwd == "" || cwd == "/workspace" {
		cwd = root
	} else {
		if strings.HasPrefix(cwd, "/workspace/") {
			cwd = filepath.Join(root, strings.TrimPrefix(cwd, "/workspace/"))
		} else if !filepath.IsAbs(cwd) {
			cwd = filepath.Join(root, cwd)
		} else {
			return nil, errors.New("cwd escapes Workspace root")
		}
		clean, err := filepath.Abs(cwd)
		if err != nil {
			return nil, err
		}
		if clean != root && !strings.HasPrefix(clean, root+string(filepath.Separator)) {
			return nil, errors.New("cwd escapes Workspace root")
		}
		cwd = clean
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Dir = cwd
	cmd.Env = os.Environ()
	if env, ok := op.Spec["env"].(map[string]any); ok {
		for key, value := range env {
			val, ok := value.(string)
			if !ok {
				return nil, errors.New("invalid environment")
			}
			cmd.Env = append(cmd.Env, key+"="+val)
		}
	}
	if stdin, ok := op.Spec["stdin"].(string); ok {
		cmd.Stdin = strings.NewReader(stdin)
	}
	if err := os.MkdirAll(s.executionDir(op.Execution), 0700); err != nil {
		return nil, err
	}
	out, err := os.OpenFile(filepath.Join(s.executionDir(op.Execution), "stdout"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return nil, err
	}
	errout, err := os.OpenFile(filepath.Join(s.executionDir(op.Execution), "stderr"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		_ = out.Close()
		return nil, err
	}
	cmd.Stdout, cmd.Stderr = &boundedOutput{file: out}, &boundedOutput{file: errout}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		_ = out.Close()
		_ = errout.Close()
		return nil, err
	}
	e := &LocalExecution{Execution: op.Execution, Workspace: op.Workspace, SpecHash: op.SpecHash, State: "running", PID: cmd.Process.Pid, ProcessGroup: cmd.Process.Pid, StartedAt: time.Now().UTC(), Stdout: filepath.Join(s.executionDir(op.Execution), "stdout"), Stderr: filepath.Join(s.executionDir(op.Execution), "stderr"), cmd: cmd}
	executionMu.Lock()
	executions[op.Execution] = e
	executionMu.Unlock()
	_ = atomicJSON(filepath.Join(s.executionDir(op.Execution), "metadata.json"), e, 0600)
	go func() {
		timeout := 0.0
		if raw, ok := op.Spec["timeout_seconds"].(float64); ok {
			timeout = raw
		}
		var timer *time.Timer
		var timeoutC <-chan time.Time
		if timeout > 0 {
			timer = time.NewTimer(time.Duration(timeout * float64(time.Second)))
			timeoutC = timer.C
			defer timer.Stop()
		}
		done := make(chan error, 1)
		go func() { done <- cmd.Wait() }()
		select {
		case <-done:
		case <-timeoutC:
			e.mu.Lock()
			e.timedOut = true
			e.mu.Unlock()
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
			select {
			case <-done:
			case <-time.After(2 * time.Second):
				_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
				<-done
			}
		}
		_ = out.Close()
		_ = errout.Close()
		now := time.Now().UTC()
		code := cmd.ProcessState.ExitCode()
		state := "exited"
		if e.timedOut {
			state = "timed_out"
		}
		if e.cancelled && !e.timedOut {
			state = "cancelled"
		}
		e.mu.Lock()
		e.State, e.FinishedAt, e.ExitCode = state, &now, &code
		e.mu.Unlock()
		_ = atomicJSON(filepath.Join(s.executionDir(op.Execution), "metadata.json"), e, 0600)
	}()
	return e, nil
}

func signalNative(e *LocalExecution) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.State != "running" {
		return nil
	}
	e.cancelled = true
	return syscall.Kill(-e.ProcessGroup, syscall.SIGTERM)
}

func executionReport(e *LocalExecution) map[string]string {
	e.mu.Lock()
	defer e.mu.Unlock()
	read := func(path string) string {
		b, err := os.ReadFile(path)
		if err != nil {
			return ""
		}
		if len(b) > 1024*1024 {
			b = b[:1024*1024]
		}
		return base64.StdEncoding.EncodeToString(b)
	}
	result := map[string]string{"execution": e.Execution, "status": e.State, "stdout_base64": read(e.Stdout), "stderr_base64": read(e.Stderr)}
	if e.ExitCode != nil {
		result["exit_code"] = strconv.Itoa(*e.ExitCode)
	}
	if e.TerminatingSignal != "" {
		result["terminating_signal"] = e.TerminatingSignal
	}
	return result
}

const (
	wsHeartbeatInterval = 10 * time.Second
	wsHeartbeatDeadline = 5 * time.Second
	wsMaxRTTSamples     = 8
)

type wsMessage struct {
	Type        string         `json:"type"`
	ID          string         `json:"id,omitempty"`
	Operation   map[string]any `json:"operation,omitempty"`
	OperationID string         `json:"operation_id,omitempty"`
	Payload     map[string]any `json:"-"`
	Interval    int            `json:"heartbeat_interval_seconds,omitempty"`
}

type rttHealth struct {
	samples  []time.Duration
	degraded int
}

func (h *rttHealth) observe(sample time.Duration) bool {
	baseline := sample
	if len(h.samples) > 0 {
		var total time.Duration
		for _, value := range h.samples {
			total += value
		}
		baseline = total / time.Duration(len(h.samples))
	}
	if len(h.samples) < 2 || sample <= 2*baseline+250*time.Millisecond {
		h.degraded = 0
	} else {
		h.degraded++
	}
	if h.degraded == 0 {
		if len(h.samples) >= wsMaxRTTSamples {
			h.samples = h.samples[1:]
		}
		h.samples = append(h.samples, sample)
	}
	return h.degraded >= 2
}

func websocketURL(base string) string {
	u, err := url.Parse(base)
	if err != nil {
		return base
	}
	if u.Scheme == "https" {
		u.Scheme = "wss"
	} else {
		u.Scheme = "ws"
	}
	u.Path = "/api/remote-agent/stream"
	u.RawQuery = ""
	return u.String()
}

func run(ctx context.Context, c *Client, store Store, id *Identity) error {
	backoff := time.Second
	for {
		if _, err := authenticate(ctx, c, id); err != nil {
			log.Printf("authentication failed: %v; reconnecting", err)
			if err := waitBackoff(ctx, backoff); err != nil {
				return err
			}
			backoff = minDuration(backoff*2, 30*time.Second)
			continue
		}
		if err := runWSS(ctx, c, store, id); err != nil && !errors.Is(err, context.Canceled) {
			log.Printf("WSS disconnected: %v", err)
		}
		if err := waitBackoff(ctx, backoff); err != nil {
			return err
		}
		backoff = minDuration(backoff*2, 30*time.Second)
		if backoff >= 4*time.Second {
			backoff = 2 * time.Second
		}
	}
}

func runWSS(ctx context.Context, c *Client, store Store, id *Identity) error {
	dialer := websocket.Dialer{HandshakeTimeout: 10 * time.Second}
	header := http.Header{"Authorization": []string{"Bearer " + c.Session}}
	conn, _, err := dialer.DialContext(ctx, websocketURL(c.Base), header)
	if err != nil {
		return err
	}
	defer conn.Close()
	writeMu := sync.Mutex{}
	send := func(value any) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		return conn.WriteJSON(value)
	}
	readCh := make(chan wsMessage, 16)
	errCh := make(chan error, 1)
	go func() {
		for {
			var raw map[string]any
			if err := conn.ReadJSON(&raw); err != nil {
				errCh <- err
				return
			}
			message := wsMessage{Type: stringValue(raw["type"]), ID: stringValue(raw["id"]), OperationID: stringValue(raw["operation_id"]), Interval: intValue(raw["heartbeat_interval_seconds"]), Operation: mapValue(raw["operation"])}
			message.Payload = raw
			readCh <- message
		}
	}()
	heartbeat := time.NewTicker(wsHeartbeatInterval)
	defer heartbeat.Stop()
	lastPong := time.Now()
	lastPing := map[string]time.Time{}
	var health rttHealth
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case err := <-errCh:
			return err
		case <-heartbeat.C:
			if time.Since(lastPong) > wsHeartbeatInterval+wsHeartbeatDeadline {
				return errors.New("WSS heartbeat deadline exceeded")
			}
			pingID := fmt.Sprintf("%d", time.Now().UnixNano())
			lastPing[pingID] = time.Now()
			if err := send(map[string]string{"type": "ping", "id": pingID}); err != nil {
				return err
			}
			if err := send(map[string]any{"type": "heartbeat", "name": id.Name, "platform": runtime.GOOS, "architecture": runtime.GOARCH, "supported_executors": []string{"native"}, "capabilities": advertise(id.Name).Capabilities}); err != nil {
				return err
			}
		case message := <-readCh:
			switch message.Type {
			case "ready":
			case "ping":
				if err := send(map[string]string{"type": "pong", "id": message.ID}); err != nil {
					return err
				}
			case "ack":
			case "operation":
				b, _ := json.Marshal(message.Operation)
				var op Operation
				if err := json.Unmarshal(b, &op); err != nil {
					return err
				}
				if err := handleOperationWithResult(ctx, store, op, func(status string, extra map[string]string) error {
					payload := map[string]any{"type": "result", "operation_id": op.OperationID, "workspace": op.Workspace, "spec_hash": op.SpecHash, "status": status}
					for key, value := range extra {
						payload[key] = value
					}
					return send(payload)
				}); err != nil {
					_ = send(map[string]any{"type": "result", "operation_id": op.OperationID, "workspace": op.Workspace, "spec_hash": op.SpecHash, "status": "failed", "message": err.Error()})
				}
			case "pong":
				lastPong = time.Now()
				if sent, ok := lastPing[message.ID]; ok {
					delete(lastPing, message.ID)
					if health.observe(time.Since(sent)) {
						return errors.New("sustained degraded WSS RTT")
					}
				}
			}
		}
	}
}

func handleOperationWithResult(ctx context.Context, s Store, op Operation, result func(string, map[string]string) error) error {
	log.Printf("handling %s for %s", op.Type, op.Workspace)
	switch op.Type {
	case "prepare_workspace":
		w, err := s.prepare(op.Workspace, op.Executor, op.OperationID, op.SpecHash)
		if err != nil {
			return err
		}
		return result("prepared", map[string]string{"provider_workspace_ref": w.Root})
	case "destroy_workspace":
		if err := s.destroy(op.Workspace); err != nil {
			return err
		}
		return result("destroyed", nil)
	case "start_execution":
		e, err := startNative(s, op)
		if err != nil {
			return result("failed", map[string]string{"execution": op.Execution, "message": err.Error()})
		}
		report := executionReport(e)
		return result(report["status"], report)
	case "cancel_execution":
		e, ok := localExecution(op)
		if !ok {
			return errors.New("execution is not known locally")
		}
		if err := signalNative(e); err != nil {
			return err
		}
		e.mu.Lock()
		e.State = "cancelled"
		e.mu.Unlock()
		return result("cancelled", executionReport(e))
	default:
		return fmt.Errorf("unknown operation type %q", op.Type)
	}
}

func waitBackoff(ctx context.Context, duration time.Duration) error {
	timer := time.NewTimer(duration/2 + time.Duration(time.Now().UnixNano()%int64(duration/2)))
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func minDuration(a, b time.Duration) time.Duration {
	if a < b {
		return a
	}
	return b
}
func stringValue(v any) string      { value, _ := v.(string); return value }
func intValue(v any) int            { value, _ := v.(float64); return int(value) }
func mapValue(v any) map[string]any { value, _ := v.(map[string]any); return value }

func handleOperation(ctx context.Context, c *Client, s Store, op Operation) error {
	log.Printf("handling %s for %s", op.Type, op.Workspace)
	switch op.Type {
	case "prepare_workspace":
		w, err := s.prepare(op.Workspace, op.Executor, op.OperationID, op.SpecHash)
		if err != nil {
			return err
		}
		return c.result(ctx, op, "prepared", map[string]string{"provider_workspace_ref": w.Root})
	case "destroy_workspace":
		if err := s.destroy(op.Workspace); err != nil {
			return err
		}
		return c.result(ctx, op, "destroyed", nil)
	case "start_execution":
		e, err := startNative(s, op)
		if err != nil {
			return c.result(ctx, op, "failed", map[string]string{"execution": op.Execution, "message": err.Error()})
		}
		extra := executionReport(e)
		status := extra["status"]
		return c.result(ctx, op, status, extra)
	case "cancel_execution":
		e, ok := localExecution(op)
		if !ok {
			return errors.New("execution is not known locally")
		}
		if err := signalNative(e); err != nil {
			return err
		}
		e.mu.Lock()
		e.State = "cancelled"
		e.mu.Unlock()
		return c.result(ctx, op, "cancelled", executionReport(e))
	default:
		return fmt.Errorf("unknown operation type %q", op.Type)
	}
}

func defaultState() string {
	d, err := os.UserConfigDir()
	if err != nil || d == "" {
		return ".later-bender-agent"
	}
	return filepath.Join(d, "later-bender-agent")
}
func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: later-bender-agent enroll|run [flags]")
	}
	ctx := context.Background()
	cmd := os.Args[1]
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	server := fs.String("server", "http://127.0.0.1:3000", "Later Bender API URL")
	state := fs.String("state", defaultState(), "Agent state directory")
	name := fs.String("name", "Later Bender Agent", "Agent name")
	token := fs.String("token", "", "one-use enrollment token")
	_ = fs.Parse(os.Args[2:])
	c := &Client{Base: strings.TrimRight(*server, "/"), HTTP: &http.Client{Timeout: 20 * time.Second}}
	s := Store{Dir: *state}
	if cmd == "enroll" {
		if *token == "" {
			log.Fatal("-token is required")
		}
		if err := enroll(ctx, c, s, *name, *token); err != nil {
			log.Fatal(err)
		}
		return
	}
	if cmd != "run" {
		log.Fatal("unknown command " + cmd)
	}
	id, err := s.load()
	if err != nil {
		log.Fatal(err)
	}
	if id.ServerURL != c.Base {
		log.Fatalf("state belongs to server %s", id.ServerURL)
	}
	if err := run(ctx, c, s, id); err != nil && !errors.Is(err, context.Canceled) {
		log.Fatal(err)
	}
}
