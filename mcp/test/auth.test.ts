import assert from "node:assert/strict";
import { request as httpRequest } from "node:http";
import type { AuthInfo } from "@modelcontextprotocol/sdk/server/auth/types.js";
import { LaterBenderApi } from "../src/api.js";
import { test } from "node:test";
import { createApp } from "../src/server.js";

async function withApp(
  run: (baseUrl: string) => Promise<void>,
  tokenVerifier?: (token: string) => Promise<AuthInfo>,
) {
  const server = createApp(
    (token) => new LaterBenderApi("https://example.test", token),
    tokenVerifier,
  ).listen(0);
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  try {
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    server.close();
  }
}

test("MCP requires bearer auth and advertises protected-resource metadata", async () => {
  await withApp(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/mcp`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });
    assert.equal(response.status, 401);
    assert.match(
      response.headers.get("www-authenticate") || "",
      /resource_metadata=/,
    );
    const metadata = await fetch(
      `${baseUrl}/.well-known/oauth-protected-resource/mcp`,
    );
    assert.equal(metadata.status, 200);
    const body = await metadata.json();
    assert.deepEqual(body.authorization_servers, [
      "https://laterbender-api.felixworks.v6.rocks",
    ]);
    assert.deepEqual(body.scopes_supported, ["mcp"]);
  });
});

test("temporary MCP request diagnostic returns verbatim headers and request bytes", async () => {
  const token = "diagnostic-token-must-not-be-redacted";
  const authInfo: AuthInfo = {
    token,
    clientId: "diagnostic-client",
    scopes: ["mcp"],
    expiresAt: 2_000_000_000,
    extra: { userId: 17, marker: "parsed auth metadata" },
  };
  const verifier = async (received: string): Promise<AuthInfo> => {
    assert.equal(received, token);
    return authInfo;
  };

  await withApp(async (baseUrl) => {
    const rawBody =
      '{ "jsonrpc" : "2.0", "id" : 11, "method" : "tools/call", "params" : { "name" : "__TEMP_mcp_request_diagnostic", "arguments" : {} } }\n';
    const parsedUrl = new URL(baseUrl);
    const response = await new Promise<{
      statusCode: number | undefined;
      body: string;
    }>((resolve, reject) => {
      const req = httpRequest(
        {
          hostname: parsedUrl.hostname,
          port: Number(parsedUrl.port),
          path: "/mcp?diagnostic=query-value",
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
            "X-ChatGPT-Diagnostic": "case-Preserving-Value",
            Accept: "application/json, text/event-stream",
            "Mcp-Protocol-Version": "2025-06-18",
            "Content-Length": String(Buffer.byteLength(rawBody)),
          },
        },
        (res) => {
          let body = "";
          res.setEncoding("utf8");
          res.on("data", (chunk: string) => {
            body += chunk;
          });
          res.on("end", () => resolve({ statusCode: res.statusCode, body }));
        },
      );
      req.on("error", reject);
      req.end(rawBody);
    });

    if (response.statusCode !== 200)
      throw new Error(
        `Diagnostic HTTP ${response.statusCode}: ${response.body}`,
      );
    const envelope = JSON.parse(response.body);
    assert.equal(
      envelope.result.structuredContent.request.originalUrl,
      "/mcp?diagnostic=query-value",
    );
    assert.equal(envelope.result.structuredContent.request.bodyUtf8, rawBody);
    assert.equal(
      envelope.result.structuredContent.request.bodyBase64,
      Buffer.from(rawBody).toString("base64"),
    );
    assert.equal(
      envelope.result.structuredContent.request.headers.authorization,
      `Bearer ${token}`,
    );
    assert.equal(
      envelope.result.structuredContent.request.authInfo.token,
      token,
    );
    assert.deepEqual(
      envelope.result.structuredContent.request.parsedBody.params,
      {
        name: "__TEMP_mcp_request_diagnostic",
        arguments: {},
      },
    );
    const rawHeaders = envelope.result.structuredContent.request
      .rawHeaders as string[];
    assert.ok(rawHeaders.includes("Authorization"));
    assert.ok(rawHeaders.includes(`Bearer ${token}`));
    assert.ok(rawHeaders.includes("X-ChatGPT-Diagnostic"));
    assert.ok(rawHeaders.includes("case-Preserving-Value"));
  }, verifier);
});
