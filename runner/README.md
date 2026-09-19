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

The runner creates a dedicated IPv4 bridge and installs host-side `DOCKER-USER`
and bridge-input rules. Workspaces can reach public IPv4 destinations, while
host, Docker, Kubernetes, database, Elasticsearch, link-local, reserved,
private, and other-Workspace destinations are denied. IPv6 is disabled inside
the container, so it cannot bypass the IPv4 policy. The policy is installed by
`network-policy.sh` before the service starts.

Workspaces receive a bounded TTL (one day by default, at most seven days).
The runner reaper removes expired containers and metadata, and the Rails
`workspaces:reap` task removes expired canonical Workspace records. Disk is
currently a soft limit; a hard quota is intentionally not added until it can
be done without disproportionate machinery.
