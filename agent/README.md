# Later Bender Remote Agent

This is the minimal native Remote Agent runtime. It implements enrollment,
Ed25519 session authentication, heartbeat, operation polling, native Workspace
preparation/destruction, and native command execution. Native commands run as
the Agent OS user in the prepared Workspace root. Process-group cancellation
and timeout are best-effort; native execution is not a sandbox and daemonized
or escaped descendants are not universally controlled.

Build and run manually:

```sh
go build -o later-bender-agent .
later-bender-agent enroll -server https://later-bender.example -token TOKEN -name "My Mac"
later-bender-agent run -server https://later-bender.example
```

The default state directory is the user config directory under
`later-bender-agent`; tests and dogfood can override it with `-state`. The
private key and metadata use mode `0600`, and Workspace state is stored below
`workspaces/WS-N/` with a durable `metadata.json` and `root/` directory.

The current Rails protocol is HTTPS polling: `/api/remote-agent/operations`
is polled after authentication and operation results are posted to the
corresponding `/result` endpoint.
