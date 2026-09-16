import assert from "node:assert/strict";
import { test } from "node:test";
import { createApp } from "../src/server.js";

async function withApp(run: (baseUrl: string) => Promise<void>) {
  const server = createApp(() => { throw new Error("API must not be called"); }).listen(0);
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
