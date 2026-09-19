import express, { type RequestHandler } from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import {
  getOAuthProtectedResourceMetadataUrl,
  mcpAuthMetadataRouter,
} from "@modelcontextprotocol/sdk/server/auth/router.js";
import { requireBearerAuth } from "@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js";
import { InvalidTokenError } from "@modelcontextprotocol/sdk/server/auth/errors.js";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { LaterBenderApi } from "./api.js";
import { registerTools } from "./tools.js";

const resourceUrl = new URL(
  process.env.MCP_RESOURCE_URL ||
    "https://laterbender-mcp.felixworks.v6.rocks/mcp",
);
const issuerUrl = new URL(
  process.env.LATER_BENDER_OAUTH_ISSUER ||
    "https://laterbender-api.felixworks.v6.rocks",
);
const issuerOrigin = issuerUrl.origin;
const apiBaseUrl = process.env.LATER_BENDER_API_BASE_URL;

async function verifyAccessToken(token: string): Promise<AuthInfo> {
  if (!apiBaseUrl)
    throw new InvalidTokenError("Token verification is not configured");
  const response = await fetch(
    `${apiBaseUrl.replace(/\/$/, "")}/api/oauth/token_info`,
    {
      headers: { Accept: "application/json", Authorization: `Bearer ${token}` },
    },
  );
  if (!response.ok) throw new InvalidTokenError("Invalid or expired token");
  const info = (await response.json()) as {
    active: boolean;
    user_id: number;
    client_id: string;
    scope: string;
    exp: number;
  };
  if (!info.active || !info.user_id || !info.exp)
    throw new InvalidTokenError("Invalid or expired token");
  return {
    token,
    clientId: info.client_id,
    scopes: info.scope.split(" ").filter(Boolean),
    expiresAt: info.exp,
    extra: { userId: info.user_id },
  };
}

export function createApp(
  apiFactory: (token: string) => LaterBenderApi = (token) =>
    new LaterBenderApi(apiBaseUrl, token),
) {
  const app = express();
  app.use(express.json());
  const metadata = {
    issuer: issuerOrigin,
    authorization_endpoint: new URL("/oauth/authorize", issuerOrigin).href,
    token_endpoint: new URL("/oauth/token", issuerOrigin).href,
    registration_endpoint: new URL("/oauth/register", issuerOrigin).href,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
    scopes_supported: ["mcp"],
  };
  app.use(
    mcpAuthMetadataRouter({
      oauthMetadata: metadata,
      resourceServerUrl: resourceUrl,
      scopesSupported: ["mcp"],
      resourceName: "Later, Bender",
    }),
  );
  const auth = requireBearerAuth({
    verifier: { verifyAccessToken },
    resourceMetadataUrl: getOAuthProtectedResourceMetadataUrl(resourceUrl),
  }) as RequestHandler;
  app.all("/mcp", auth, async (request, response) => {
    const server = new McpServer(
      { name: "later-bender", version: "0.1.0" },
      {
        instructions:
          "Later Bender stores explicit durable user state. Tasks are actionable work. Notes are durable non-actionable context such as ideas, decisions, findings, hypotheses, possible directions, constraints, observations, and discussion results. Projectless Notes are user-level durable memory; Project Notes belong to one project. Use search_memory for recall when the location is unknown or may be either a Task or Note. Use list_tasks/list_notes to browse a known scope with structured filters. Search and list results are summaries; use get_task/get_note for complete content. When a Task synthesizes existing Notes, attach materially relevant Notes with related_note_ids.",
      },
    );
    registerTools(server, apiFactory(request.auth!.token));
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true,
    });
    response.on("close", () => transport.close());
    try {
      await server.connect(transport);
      await transport.handleRequest(request, response, request.body);
    } catch (error) {
      if (!response.headersSent)
        response.status(500).json({
          error: "MCP server error",
          message: error instanceof Error ? error.message : String(error),
        });
    }
  });
  app.get("/health", (_request, response) => response.json({ ok: true }));
  return app;
}

if (process.env.NODE_ENV !== "test")
  createApp().listen(Number(process.env.PORT || 3000), "0.0.0.0", () =>
    console.log("Later, Bender MCP listening"),
  );
