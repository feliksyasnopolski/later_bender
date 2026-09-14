# Production deployment

Later, Bender runs on `ubuntu@193.123.38.157` as a Rails container managed by
Kamal. Host Caddy remains the only public owner of ports 80 and 443 and routes
the temporary external base URL
`https://193.123.38.157/laterbender` to the application's loopback Kamal proxy.
Caddy strips `/laterbender` before proxying, so Rails continues to receive
`/api/...` and `/up`.

The host's shared Kamal proxy publishes only on loopback ports 8080 (HTTP) and
8443 (HTTPS); Later, Bender has its own route in that proxy. PostgreSQL remains
host-managed and non-public, with the dedicated `later_bender` role and
`backend_production` database.

From `backend/`, provide an ignored `.kamal/secrets` file containing:

```
RAILS_MASTER_KEY=...
BACKEND_DATABASE_PASSWORD=...
```

GitHub Actions publishes the ARM64 immutable image to public GHCR. Pull the
published version anonymously on the host, then boot that exact version with
Kamal:

```
docker pull ghcr.io/feliksyasnopolski/later_bender:sha-<commit>
docker tag ghcr.io/feliksyasnopolski/later_bender:sha-<commit> \
  localhost:5555/ghcr.io/feliksyasnopolski/later_bender:sha-<commit>
kamal app boot --version sha-<commit>
```

The local tag is a Kamal 2 configuration compatibility shim; it does not
require registry credentials or a local registry. The entrypoint runs
`db:prepare` before boot. Create the first user
and a bearer token without storing either raw credential in the repository:

```
kamal app exec -r web --reuse 'bin/rails users:create USERNAME=name PASSWORD=password'
kamal app exec -r web --reuse 'bin/rails api_tokens:create USERNAME=name NAME=initial-client'
```

The health endpoint is `https://193.123.38.157/laterbender/up`. CORS permits
the future frontend origin `https://laterbender.pages.dev` for `/api/*` and
uses bearer-token authentication. The `/laterbender` prefix is temporary until
a dedicated hostname is available.
