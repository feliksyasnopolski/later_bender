# Later, Bender MCP adapter

This is a thin remote MCP Streamable HTTP adapter. Rails remains the canonical
API and OAuth authentication boundary; each request forwards its bearer token
and returns Rails response data or structured error codes.

## Local development

```sh
LATER_BENDER_API_BASE_URL=http://localhost:3000 \
LATER_BENDER_OAUTH_ISSUER=http://localhost:3000 \
MCP_RESOURCE_URL=http://localhost:3001/mcp \
MCP_DANGEROUSLY_ALLOW_INSECURE_ISSUER_URL=true \
npm run build && npm start
```

The MCP endpoint is `/mcp` and the health check is `/health`.

## Production shape

The canonical endpoint is `https://laterbender-mcp.felixworks.v6.rocks/mcp`.
Protected-resource metadata advertises the Rails Doorkeeper authorization and
token endpoints. Clients register through standard OAuth dynamic client
registration, use authorization code with mandatory PKCE S256, and receive the
single `mcp` protocol scope. Access tokens last 30 days and refresh tokens are
supported.
