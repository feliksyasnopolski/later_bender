# Production deployment

Later, Bender's Rails API is deployed from its immutable GHCR image through
the Kubernetes chart in the `later-bender` GitOps repository at
`https://laterbender-api.felixworks.v6.rocks`. PostgreSQL remains host-managed
and non-public. The chart also deploys the MCP adapter at
`https://laterbender-mcp.felixworks.v6.rocks/mcp`.

Create the runtime Secret out of band; never commit its values:

```sh
kubectl -n later-bender create secret generic later-bender-runtime \
  --from-literal=rails-master-key="$RAILS_MASTER_KEY" \
  --from-literal=database-password="$BACKEND_DATABASE_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install later-bender apps/later-bender --namespace later-bender
```

Doorkeeper provides `/oauth/authorize` and `/oauth/token`; authorization-server
metadata is at `/.well-known/oauth-authorization-server`. The MCP adapter
advertises protected-resource metadata at
`/.well-known/oauth-protected-resource/mcp`. OAuth uses public dynamic client
registration, mandatory PKCE S256, the single `mcp` scope, 30-day access tokens,
and refresh tokens.
