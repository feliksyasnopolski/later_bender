import assert from "node:assert/strict";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { test } from "node:test";
import { LaterBenderApi } from "../src/api.js";
import { createApp } from "../src/server.js";

async function withApp(
  run: (baseUrl: string) => Promise<void>,
  tokenVerifier?: (token: string) => Promise<AuthInfo>,
  apiFactory: (token: string, conversationId?: string) => LaterBenderApi = (token) => new LaterBenderApi("https://example.test", token),
) {
  const server = createApp(apiFactory, tokenVerifier).listen(0);
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  try { await run(`http://127.0.0.1:${address.port}`); } finally { server.close(); }
}

test("MCP requires bearer auth and advertises protected-resource metadata", async () => {
  await withApp(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/mcp`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
    assert.equal(response.status, 401);
    assert.match(response.headers.get("www-authenticate") || "", /resource_metadata=/);
    const metadata = await fetch(`${baseUrl}/.well-known/oauth-protected-resource/mcp`);
    assert.equal(metadata.status, 200);
    const body = await metadata.json();
    assert.deepEqual(body.authorization_servers, ["https://laterbender-api.felixworks.v6.rocks"]);
    assert.deepEqual(body.scopes_supported, ["mcp"]);
  });
});

test("MCP passes openai/session from each request into the API client and omits the temporary probe", async () => {
  const token = "test-token";
  const authInfo: AuthInfo = { token, clientId: "test-client", scopes: ["mcp"], expiresAt: 2_000_000_000 };
  const seen: Array<string | undefined> = [];
  const verifier = async (received: string): Promise<AuthInfo> => { assert.equal(received, token); return authInfo; };
  const apiFactory = (receivedToken: string, conversationId?: string) => {
    assert.equal(receivedToken, token);
    seen.push(conversationId);
    return new LaterBenderApi("https://example.test", receivedToken);
  };
  await withApp(async (baseUrl) => {
    const call = (session: string | undefined, id: number) => fetch(`${baseUrl}/mcp`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json", accept: "application/json, text/event-stream", "mcp-protocol-version": "2025-06-18" },
      body: JSON.stringify({ jsonrpc: "2.0", id, method: "tools/list", params: session ? { _meta: { "openai/session": session } } : {} }),
    });
    for (const [session, id] of [["v1/chat-A", 1], ["v1/chat-B", 2], ["v1/chat-A", 3], [undefined, 4]] as const) {
      const response = await call(session, id);
      assert.equal(response.status, 200);
      const json = await response.json();
      assert.ok(!JSON.stringify(json).includes("__TEMP_mcp_request_diagnostic"));
    }
  }, verifier, apiFactory);
  assert.deepEqual(seen, ["v1/chat-A", "v1/chat-B", "v1/chat-A", undefined]);
});
