# Later, Bender agent guide

## Start here

This repository contains the Rails API, the Vue frontend, and the TypeScript
MCP adapter. Read [`OPERATIONS.md`](OPERATIONS.md) before deployment,
production inspection, or model-facing acceptance. It is the authoritative
repo-local description of validation, GitOps, MicroK8s, release, and live
acceptance boundaries.

## Repository layout and canonical checks

- `backend/`: Rails application, JSON API, search, canonical Files, and RSpec/OpenAPI contracts.
- `mcp/`: TypeScript Streamable HTTP adapter and MCP contract tests.
- `frontend/`: Vue/Vite application and Playwright browser acceptance.
- `.github/workflows/`: immutable backend and MCP GHCR image publication on `master`.

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
```

`backend/bin/ci` is the repository's canonical continuous-integration runner
and includes RSpec, OpenAPI drift, RuboCop, MCP tests/build, bundler-audit, and
Brakeman. The `.github/workflows/` files currently publish images; they do not
run the test gate. Frontend Playwright is not CI-gated by this repository and
requires authenticated local credentials; use it for rendered frontend
changes.

Hard boundaries: keep Rails as the canonical state boundary; preserve
user/project ownership and OAuth authentication; do not weaken strict MCP
schemas to accept Rails internals; do not deploy with old Kamal, Caddy,
host-global systemd, or standalone MCP service paths; and do not put secrets or
transient credentials in source, documentation, or test output.

Later, Bender is personal project and task management software. It supports multiple users, but every project has exactly one owner. Projects are not collaborative: there are no shared owners, memberships, invitations, or role matrices. Adding collaboration is a product decision, not a missing implementation detail.

The human UI and JSON API are equal control surfaces over the same canonical backend state. External clients, including AI assistants, must be able to inspect, create, update, classify, search, and filter the same projects and tasks shown in the UI. AI is an important client, not the product definition; do not reduce Later, Bender to an "AI backlog."

## Domain invariants

- A `User` owns projects and authentication credentials.
- A `Project` belongs to one user and contains tasks.
- A `Task` belongs to one project and has tags through task-tag associations.
- Tags are cheap, reusable, global classification where the implementation permits, and can be created on use through the task API.
- Scope projects to the authenticated user and reach tasks through owned projects. Never leak cross-user data or resource existence.
- The backend is canonical. The API uses JSON; nested project/task routes are the natural task mutation surface. Cross-project retrieval and search are first-class operations.
- Task prose, including context and intended direction, may contain Markdown.

Treat the code as the source of truth for exact fields and implemented scoping. Do not turn incidental fields into permanent doctrine.

## Engineering principles

- Use ordinary Rails conventions in `backend/`. Prefer the framework's conventional solution to repository, command, service, or use-case layers invented without a concrete readability or reuse need.
- Keep `frontend/` a separate, Vue-based application. Use mature libraries when they solve a real problem; do not reimplement established framework or library behavior merely to minimize dependency count. Dependencies must earn their value, but dependency avoidance is not an ideology.
- Keep code straightforward: obvious control flow, conventional placement, few moving parts, and easy diagnosis from shell and runtime evidence. Avoid clever metaprogramming and ornamental infrastructure.
- Prefer normal REST resources, explicit JSON fields, predictable status codes, and structured validation errors. Treat UI-only support for an operation that naturally belongs in the API with suspicion.
- Preserve the current authentication model unless a task deliberately changes it: Devise username/password without assuming email identity, opaque bearer credentials rather than JWTs, user-scoped access, and optional TOTP recovery where implemented. Do not casually redesign authentication.

### No perdoling

Do not spend prolonged effort forcing a route after its expected value has collapsed. Do not reinvent mature functionality, add impressive-looking abstractions or infrastructure, or cargo-cult tests, architecture, dependencies, or deployment practices. Almost any route can be made to work with enough effort; that does not make it worthwhile. Prefer a simpler proven tool when it solves the problem. When evidence shows the chosen path is wrong, change the path instead of polishing around it indefinitely.

## Product restraint

Build features for concrete, recurring problems observed in actual use—not competitor parity, hypothetical demand, implementation convenience, generic task-manager expectations, or AI-agent convenience alone.

Do not casually add collaboration, roles, invitations, comments, sprints, boards, milestones, assignees, notifications, attachments, or complex workflow engines. Any may be added later when real use justifies it.

Keep search simple until stronger retrieval is demonstrably valuable. Elasticsearch or OpenSearch may become appropriate for useful fuzzy or relevance-ranked corpus search, or when PostgreSQL is proven insufficient; do not add search infrastructure because task trackers are expected to have it.

## Agent workflow

- Read the applicable code, documentation, and repository guidance before changing anything. If evidence contradicts the task's assumptions, adapt and report it; do not reinterpret settled product or architecture decisions without a concrete blocker.
- Keep scope literal. Do not mix requested work with speculative features, cleanup, dependency changes, or redesigns.
- Task specifications should state the goal, invariants, constraints, required evidence, and acceptance criteria. Within those boundaries, use normal framework and tooling choices without needless line-by-line ceremony.
- Validate the changed surface: relevant Rails tests and direct API acceptance for backend behavior; relevant frontend/browser checks for UI behavior; runtime acceptance for deployment work; documentation/static checks for documentation-only work. Do not run unrelated full suites as ceremony. Runtime evidence outranks a contradictory green test suite.
- Preserve unrelated work already present in the tree.

Keep this guide durable. Do not turn it into a version inventory or record temporary hosts, routes, deployment details, or incidental implementation choices.
