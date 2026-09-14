import express from "express";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { LaterBenderApi } from "./api.js";
import { registerTools } from "./tools.js";

export function createApp(api = new LaterBenderApi()) {
  const app = express();
  app.use(express.json());
  app.all("/mcp", async (request, response) => {
    const server = new McpServer({ name: "later-bender", version: "0.1.0" });
    registerTools(server, api);
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
    response.on("close", () => transport.close());
    try { await server.connect(transport); await transport.handleRequest(request, response, request.body); }
    catch (error) { if (!response.headersSent) response.status(500).json({ error: "MCP server error", message: error instanceof Error ? error.message : String(error) }); }
  });
  app.get("/health", (_request, response) => response.json({ ok: true }));
  return app;
}

if (process.env.NODE_ENV !== "test") {
  const port = Number(process.env.PORT || 3000);
  createApp().listen(port, "0.0.0.0", () => console.log(`Later, Bender MCP listening on ${port}`));
}
