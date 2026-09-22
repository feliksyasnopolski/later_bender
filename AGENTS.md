# Later, Bender agent guide

## Start here

Later Bender is a canonical durable working-state layer shared by humans and
model clients. Tasks are actionable durable state. Notes are durable mutable
non-actionable semantic memory. Files are immutable canonical evidence and
artifacts, with readable representations and citations where applicable.
Credentials are durable secret metadata and bindings; secret values must not
leak into normal state, logs, or documentation. Workspaces are transient
execution environments, and Remote Agents are execution targets behind the
provider-neutral Workspace abstraction.

The frontend, JSON API, and MCP adapter are first-class clients of the same
canonical backend state, not separate products. Read [`OPERATIONS.md`](OPERATIONS.md)
before deployment, production inspection, or model-facing acceptance; it is the
authoritative repo-local guide for those boundaries.

## Repository layout and canonical checks

- `backend/`: Rails application, JSON API, canonical durable state, Files, and RSpec/OpenAPI contracts.
- `mcp/`: TypeScript Streamable HTTP adapter and MCP contract tests.
- `frontend/`: Vue/Vite application and Playwright browser acceptance.
- `agent/`: Go native Remote Agent runtime and protocol tests.
- `runner/`: hosted Workspace runner and its operational controls.
- `.github/workflows/`: backend and MCP image publication workflows.

Run commands from the component directory they belong to:

```sh
cd backend && bin/ci
cd backend && bundle exec rspec
cd backend && bundle exec rake openapi:check
cd backend && bin/rubocop
cd backend && bin/bundler-audit
cd backend && bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
cd mcp && npm test && npm run build
cd frontend && npm ci && npm run build
cd frontend && PLAYWRIGHT_USERNAME=... PLAYWRIGHT_PASSWORD=... npm run test:e2e
cd agent && go test ./...
cd agent && go build ./...
```

`backend/bin/ci` is the canonical backend/repository gate and includes RSpec,
OpenAPI drift, RuboCop, MCP tests/build, bundler-audit, and Brakeman. The GitHub
workflows currently publish images but do not run that gate. Frontend Playwright
requires authenticated local credentials and is not CI-gated here; use it for
rendered frontend changes. The Go Agent checks validate the standalone runtime.

## Authority and execution boundaries

- Rails/PostgreSQL is canonical for durable Later Bender state and for
  Workspace/Execution identity and lifecycle state.
- Native Remote Agent execution runs with the authority of the OS identity
  running the Agent. It is not a sandbox.
- Hosted Workspaces are containerized execution environments, but are not to be
  described as hardened sandboxes.
- Workspace creation, target selection, placement, execution,
  transcript/output interaction, and related execution operations are
  model-facing.
- Human UI should manage durable state and Remote Agent administration and
  enrollment. Do not add human Workspace-placement controls merely because
  Remote Agents exist.
- Keep provider details behind provider-neutral Workspace contracts wherever
  the current architecture does so.

Preserve authentication and ownership boundaries, strict MCP schemas, and
secret handling. Do not resurrect retired Kamal, Caddy, host-global systemd,
or standalone MCP deployment paths.

## Domain invariants

- A `User` owns Projects, Notes, Credentials, Workspaces, and Remote Agents.
- A Project is a lightweight user-owned scope for its Tasks and canonical
  Files. A Task belongs to a Project and may relate to Notes and Files.
- Notes belong to a User and may be global or scoped to that User's Project.
  They represent non-actionable semantic memory; Tasks represent actionable
  work.
- Files belong to a User-owned Project. Their canonical bytes are immutable;
  representations, citations, tags, and Task/Note relationships are derived
  or relational access paths to that evidence.
- Credentials expose metadata and bindings to authorized operations, never
  secret values in ordinary projections or diagnostics.
- Workspaces are user-scoped transient environments with durable identity,
  lifecycle, executions, and transcripts as implemented. A Workspace may be
  placed on a hosted offering or a user-owned Remote Agent.
- Remote Agents are user-owned durable administration/enrollment identities
  and execution targets. Their provider-specific runtime state must not become
  a second source of durable product truth.
- Scope every resource and relationship to the authenticated user. Never leak
  another user's data or even resource existence.

Treat the code and API as the source of truth for exact fields and current
scoping. Do not promote incidental schema fields into permanent doctrine.

## Engineering principles

- Inspect the applicable code, documentation, durable Task/Note state, and repo
  guidance before changing anything. Current task and repository evidence
  overrides stale assumptions.
- Keep scope literal. Preserve unrelated work and do not mix speculative
  features, cleanup, deployment, or redesign into a focused task.
- Use ordinary Rails, Vue, TypeScript, and Go conventions and mature mechanisms
  where they solve the problem. Avoid invented layers, infrastructure, or
  abstractions without a concrete need.
- Validate behavior at the boundary where defects can occur. Runtime evidence
  outranks contradictory green tests; do not claim deployment or live acceptance
  from local checks alone.
- Preserve the current authentication model and user/resource scoping. Keep
  model-facing contracts explicit and narrow rather than accepting Rails
  internals for convenience.

### No perdoling

Do not spend prolonged effort forcing a route after its expected value has
collapsed. Do not reinvent mature functionality or add impressive-looking
infrastructure without evidence. When the chosen path is wrong, change it
instead of polishing around it.

## Product restraint

Build for concrete recurring problems, not competitor parity or hypothetical
demand. Do not add automatic Jira or enterprise feature creep, collaboration,
RBAC, workflow machinery, or speculative infrastructure without a concrete
need. Files and other shipped surfaces are part of the current product; do not
describe them as hypothetical task-manager attachments.

Keep this guide concise and durable. It is an entry-point guide, not a feature
inventory, changelog, or temporary production handoff.
