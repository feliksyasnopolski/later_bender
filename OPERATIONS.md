# Later, Bender operations

This is the authoritative operational guide for this repository. It describes
the current deployment system, not the historical files that remain in the
tree for application/build context.

## Validation

The complete backend gate is run from `backend/`:

```sh
bin/ci
```

It runs setup, RSpec, generated OpenAPI drift validation, RuboCop, MCP tests,
the MCP TypeScript build, bundler-audit, and Brakeman. The individual commands
are:

```sh
bundle exec rspec
bundle exec rake openapi:check
bin/rubocop
bin/bundler-audit
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
npm --prefix ../mcp test
npm --prefix ../mcp run build
```

This runner is the repository's CI command, but the current GitHub Actions
workflows only publish backend and MCP images; they do not invoke `bin/ci`.
Treat `bin/ci` as a required pre-push gate. Frontend Playwright is likewise
not part of the current GitHub Actions workflows.

The MCP component can also be checked directly from `mcp/`:

```sh
npm test
npm run build
```

The frontend is a separate Vue/Vite component. From `frontend/`:

```sh
npm ci
npm run build
PLAYWRIGHT_USERNAME=... PLAYWRIGHT_PASSWORD=... npm run test:e2e
```

Use `npm run test:e2e:headed` when visual diagnosis is needed. Playwright
starts a local Rails API on port 3100 and Vite on port 5173; credentials are
local operator inputs and must not be committed.

## Production ownership and access

Production is a single-node ARM64 MicroK8s cluster. Application deployment
configuration belongs to the sibling GitOps checkout at:

```text
/Users/felix/rails/gitops/apps/later-bender
```

The source repository owns application code and image publication. The GitOps
checkout owns Helm values and cluster deployment state. There is no automatic
GitOps reconciler in this path: authorized operators apply the chart directly
from the GitOps checkout.

Use the dedicated kubeconfig; do not rely on the default Kubernetes context:

```sh
export KUBECONFIG="$HOME/.kube/oracle-microk8s"
kubectl get nodes
kubectl -n later-bender get pods
helm -n later-bender status later-bender
```

The cluster API is the Oracle host at `193.123.38.157:16443`. PostgreSQL is
host-managed and private. Elasticsearch is a private, disposable derived
index; canonical PostgreSQL and Active Storage File bytes are not disposable.

## Image publication and deployment

Push application changes to `master` only after the relevant local checks
pass. These workflows build ARM64 immutable full-SHA images and publish them
to GHCR:

- `.github/workflows/publish-backend.yml` publishes `ghcr.io/feliksyasnopolski/later_bender:sha-<full-commit-sha>` from `backend/`.
- `.github/workflows/publish-mcp.yml` publishes `ghcr.io/feliksyasnopolski/later-bender-mcp:sha-<full-commit-sha>` from `mcp/`.

Verify the workflow completed and the exact tag exists before changing GitOps
values. If an authorized operator must publish manually, use an approved GHCR
credential without recording it:

```sh
docker login ghcr.io
docker build --platform linux/arm64 -t ghcr.io/feliksyasnopolski/later_bender:sha-<full-sha> backend
docker push ghcr.io/feliksyasnopolski/later_bender:sha-<full-sha>
docker build --platform linux/arm64 -t ghcr.io/feliksyasnopolski/later-bender-mcp:sha-<full-sha> mcp
docker push ghcr.io/feliksyasnopolski/later-bender-mcp:sha-<full-sha>
```

Update only the corresponding immutable tags in
`/Users/felix/rails/gitops/apps/later-bender/values.yaml`, review the GitOps
diff, then apply from the GitOps checkout:

```sh
cd /Users/felix/rails/gitops
export KUBECONFIG="$HOME/.kube/oracle-microk8s"
helm upgrade --install later-bender apps/later-bender --namespace later-bender --wait --timeout 5m
kubectl -n later-bender rollout status deployment/later-bender-later-bender --timeout=120s
kubectl -n later-bender rollout status deployment/later-bender-later-bender-mcp --timeout=120s
```

The runtime Secret `later-bender-runtime` and the private image pull Secret
`later-bender-ghcr` are created out of band. Never commit their values. The
chart owns the backend, MCP adapter, Traefik ingress/certificates,
Elasticsearch, and retained Active Storage volumes.

## Deployment verification

Confirm the deployed images and health endpoints, not just Helm success:

```sh
kubectl -n later-bender get deploy later-bender-later-bender later-bender-later-bender-mcp \
  -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.spec.template.spec.containers[0].image}{"\\n"}{end}'
curl -fsS https://laterbender-api.felixworks.v6.rocks/up
curl -fsS https://laterbender-mcp.felixworks.v6.rocks/health
```

Canonical production endpoints are:

- API: `https://laterbender-api.felixworks.v6.rocks`
- MCP: `https://laterbender-mcp.felixworks.v6.rocks/mcp`
- Frontend: `https://laterbender.pages.dev`

The frontend is hosted by Cloudflare Pages. This repository contains its
source and build configuration but no Pages deployment workflow or credentials.
The Pages build uses `npm run build` in `frontend/`, emits `frontend/dist`,
and must set `VITE_API_BASE_URL` to the public Rails API origin. Use the
authorized Cloudflare Pages project/deployment mechanism; do not add hosting
credentials to this repository.

## Live MCP acceptance

Health checks do not prove authenticated MCP behavior. After MCP schema,
adapter, File, or search changes, use the configured authenticated Later
Bender MCP connector and a fresh tool-surface refresh when required. Verify a
representative `search_memory` call through the connector, including expected
Task/Note/File kinds, compact projects without Rails IDs, plain-text snippets
and highlights, and usable File representation/locator values.

Connector metadata can be stale after deployment. A stale `tools/list` result
is not evidence that the new image is running; correlate the fresh connector
call with the deployed pod image and backend/MCP logs. Do not create production
test data merely to make an acceptance query return a desired kind, and do not
use credentials, signed URLs, or connector tokens in repository artifacts.

## Retired deployment paths

The following are not current production deployment mechanisms and must not be
resurrected because old files or history mention them:

- Kamal and `backend/config/deploy.yml`.
- The old Caddy/public-host routing path.
- Host-global systemd deployment of the MCP adapter in `mcp/deploy/`.

Current production is MicroK8s plus the sibling Helm chart, Traefik ingress,
cert-manager, host PostgreSQL, and the chart-managed private Elasticsearch
and Active Storage volumes.
