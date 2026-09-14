# Later, Bender MCP adapter

This is a thin remote MCP Streamable HTTP adapter. Rails remains the canonical
API and authentication boundary; the adapter forwards the bearer token and
returns Rails response data or structured error codes.

## Local development

```sh
LATER_BENDER_API_BASE_URL=https://193.123.38.157/laterbender \
LATER_BENDER_API_TOKEN=$(tr -d '\\r\\n' </tmp/token) \
npm run build && npm start
```

The MCP endpoint is `/mcp` and the health check is `/health`.

## Production shape

The adapter listens only on loopback port 3001 through a Docker container. The
host Caddy configuration routes `/laterbender/mcp` to that port before the
existing `/laterbender/*` Rails route. The production environment file is
outside the repository at `/etc/later-bender-mcp.env` with mode 600.
