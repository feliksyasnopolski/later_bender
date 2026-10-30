# Later Bender Remote Agent

This is the minimal native Remote Agent runtime. It implements enrollment,
Ed25519 session authentication, outbound WSS heartbeat/dispatch, native Workspace
preparation/destruction, and native command execution. Native commands run as
the Agent OS user in the prepared Workspace root. Process-group cancellation
and timeout are best-effort; native execution is not a sandbox and daemonized
or escaped descendants are not universally controlled.

Build and run manually:

```sh
go build -o later-bender-agent .
later-bender-agent version
later-bender-agent enroll -server https://later-bender.example -token TOKEN -name "My Mac"
later-bender-agent run -server https://later-bender.example
```

Prebuilt releases are published at
`https://github.com/feliksyasnopolski/later_bender/releases`. Select a version
and download its platform binary, for example:
`https://github.com/feliksyasnopolski/later_bender/releases/download/v0.1.0/later-bender-agent-linux-amd64`.
Each release includes `manifest.json` with versioned download URLs, byte sizes,
and SHA-256 digests, plus a conventional `checksums.txt`. Verify the downloaded
binary against either file before running it. Release assets use version-tagged
URLs and are not replaced by a moving `latest` asset.

The default state directory is the user config directory under
`later-bender-agent`; tests and dogfood can override it with `-state`. The
private key and metadata use mode `0600`, and Workspace state is stored below
`workspaces/WS-N/` with a durable `metadata.json` and `root/` directory.

Enrollment and challenge authentication remain HTTPS. After authentication,
the Agent opens `wss://.../api/remote-agent/stream`. Rails sends provider
operations over that connection and the Agent returns receipts/results over
the same connection. Canonical state and reconciliation remain in Rails and
PostgreSQL; bulk File and Credential paths remain HTTPS.
