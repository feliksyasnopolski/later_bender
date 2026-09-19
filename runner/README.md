# Later Bender Workspace runner

This is the privileged host-side service for LB-80. It is intentionally not a
Rails or Kubernetes workload. Rails calls it over a narrow authenticated HTTP
API; only this process invokes Docker and owns `/var/lib/later-bender/workspaces`.

Run locally:

```sh
WORKSPACE_RUNNER_TOKEN=... python3 runner/server.py
```

Required production settings are `WORKSPACE_STORAGE`, `WORKSPACE_IMAGE`,
`WORKSPACE_RUNNER_TOKEN`, `WORKSPACE_RUNNER_HOST`, and
`WORKSPACE_RUNNER_PORT`. The service persists its metadata in SQLite and its
stdout/stderr byte streams in runner-owned files, so a process restart does not
turn a still-running Docker execution into a false terminal state.

The current first slice enforces CPU, memory, and PID limits and uses Docker's
configured network. Its default capability advertisement is conservative
(`internet: false`); production must supply and validate the intended isolated
network before advertising public internet access. Disk is currently a soft
limit. Host/private/MicroK8s network isolation and hard disk quotas remain
explicit production acceptance gates, not claims made by this local prototype.
