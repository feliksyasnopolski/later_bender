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
	"path/filepath"
	"runtime"
	"strings"
	"time"
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

func (s Store) identityPath() string           { return filepath.Join(s.Dir, "identity.json") }
func (s Store) workspaceDir(ref string) string { return filepath.Join(s.Dir, "workspaces", ref) }

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
}

func (c *Client) result(ctx context.Context, op Operation, status string, extra map[string]string) error {
	p := map[string]any{"operation_id": op.OperationID, "workspace": op.Workspace, "spec_hash": op.SpecHash, "status": status}
	for k, v := range extra {
		p[k] = v
	}
	return c.post(ctx, "/api/remote-agent/operations/"+url.PathEscape(op.OperationID)+"/result", p, true, &struct{}{})
}

func run(ctx context.Context, c *Client, store Store, id *Identity) error {
	for {
		hb, err := authenticate(ctx, c, id)
		if err != nil {
			log.Printf("authentication failed: %v; reconnecting", err)
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(2 * time.Second):
				continue
			}
		}
		log.Printf("Agent %s authenticated", id.Ref)
		ticker := time.NewTicker(time.Duration(hb) * time.Second)
		poll := time.NewTicker(time.Second)
		for connected := true; connected; {
			select {
			case <-ctx.Done():
				ticker.Stop()
				poll.Stop()
				return ctx.Err()
			case <-ticker.C:
				adv := advertise(id.Name)
				var ignored map[string]any
				if err := c.post(ctx, "/api/remote-agent/heartbeat", adv, true, &ignored); err != nil {
					log.Printf("heartbeat failed: %v", err)
					connected = false
				}
			case <-poll.C:
				var response struct {
					Operations []Operation `json:"operations"`
				}
				if err := c.get(ctx, "/api/remote-agent/operations", &response); err != nil {
					log.Printf("operation poll failed: %v", err)
					connected = false
					continue
				}
				for _, op := range response.Operations {
					if err := handleOperation(ctx, c, store, op); err != nil {
						log.Printf("operation %s failed: %v", op.OperationID, err)
						_ = c.result(ctx, op, "failed", map[string]string{"message": err.Error()})
					}
				}
			}
		}
		ticker.Stop()
		poll.Stop()
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}

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
