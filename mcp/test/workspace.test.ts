import assert from "node:assert/strict";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerWorkspaceTools, workspaceToolNames } from "../src/workspace.js";

function tools() {
  const server = new McpServer({ name: "test", version: "1" });
  registerWorkspaceTools(server);
  return (server as any)._registeredTools as Record<string, any>;
}

test("registers exactly the frozen Workspace tool surface", () => {
  assert.deepEqual(Object.keys(tools()).sort(), [...workspaceToolNames].sort());
});

test("Workspace schemas keep capability and resource identifiers open", () => {
  const registered = tools();
  assert.deepEqual(Object.keys(registered.get_workspace_capabilities.inputSchema.shape), []);
  assert.equal(registered.create_workspace.inputSchema.safeParse({}).success, true);
  assert.equal(registered.create_workspace.inputSchema.safeParse({ environment: "future-linux", architecture: "riscv64", resources: { min_cpus: 1.5, min_memory_bytes: 1024 } }).success, true);
  assert.equal(registered.create_workspace.outputSchema.safeParse({ workspace: {
    ref: "WS-1", label: null, state: "ready", environment: "future-linux", architecture: "riscv64",
    os: { name: "Linux", version: "1" }, shell: "/bin/bash", workspace_root: "/workspace",
    limits: { cpus: 1.5, memory_bytes: 1024, disk_bytes: 2048, pids: 128 }, capabilities: { internet: true, gpu: false, nested_virtualization: false },
    created_at: "2026-01-01T00:00:00Z", last_activity_at: "2026-01-01T00:00:00Z", expires_at: null
  } }).success, true);
  assert.equal(registered.get_workspace_capabilities.outputSchema.safeParse({
    default_environment: "linux", default_architecture: "arm64", environments: [{ environment: "linux", description: "General-purpose Linux engineering environment", architectures: [{
      architecture: "arm64", os: { name: "Linux", version: "1" }, shell: "/bin/bash",
      resources: { default: { cpus: 1.5, memory_bytes: 1024, disk_bytes: 2048, pids: 128 }, max: { cpus: 4, memory_bytes: 4096, disk_bytes: 8192, pids: 512 } },
      capabilities: { internet: true, gpu: false, nested_virtualization: false, future_accelerator: true }
    }] }], capability_definitions: { internet: "Outbound network access", gpu: "GPU acceleration" }
  }).success, true);
  assert.equal(registered.create_workspace.inputSchema.shape.required_capabilities.safeParse(["internet", "future_accelerator"]).success, true);
  assert.equal(registered.create_workspace.inputSchema.shape.resources.safeParse({ min_pids: 128 }).success, true);
  assert.equal(registered.create_workspace.inputSchema.shape.resources.safeParse({ min_pids: 1.5 }).success, false);
  assert.equal(registered.get_workspace_capabilities.outputSchema.safeParse({
    default_environment: "linux", default_architecture: "arm64", environments: [{ environment: "linux", description: "General-purpose Linux engineering environment", architectures: [] }], capability_definitions: { internet: "Outbound network access" }
  }).success, true);
  assert.equal(registered.list_workspaces.outputSchema.safeParse({ workspaces: [{ ref: "WS-1", label: null, state: "ready", environment: "linux", architecture: "arm64", created_at: "2026-01-01T00:00:00Z", last_activity_at: "2026-01-01T00:00:00Z", expires_at: null }], next_cursor: null }).success, true);
});

test("execution input requires exactly shell or direct argv", () => {
  const schema = registeredExecSchema();
  assert.equal(schema.safeParse({ workspace: "WS-1", command: "echo hi" }).success, true);
  assert.equal(schema.safeParse({ workspace: "WS-1", argv: ["printf", "hi"] }).success, true);
  assert.equal(schema.safeParse({ workspace: "WS-1" }).success, false);
  assert.equal(schema.safeParse({ workspace: "WS-1", command: "echo hi", argv: ["echo", "hi"] }).success, false);
  assert.equal(schema.safeParse({ workspace: "WS-1", argv: [] }).success, false);
});

test("boundary operations expose stable result contracts and scaffold availability", async () => {
  const registered = tools();
  assert.equal(registered.put_file_in_workspace.inputSchema.shape.overwrite.safeParse(undefined).success, true);
  assert.deepEqual(registered.put_file_in_workspace.annotations, { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false });
  assert.equal(registered.read_workspace_file.inputSchema.safeParse({ workspace: "WS-1", path: "out.txt" }).success, true);
  assert.equal(registered.read_workspace_file.inputSchema.safeParse({ workspace: "WS-1", path: "out.txt", locator: { kind: "lines", start: 1, end: 2 } }).success, true);
  assert.equal(registered.read_workspace_file.inputSchema.safeParse({ workspace: "WS-1", path: "out.txt", locator: { kind: "pages", start: 1, end: 2 } }).success, false);
  assert.equal(registered.read_workspace_file.inputSchema.safeParse({ workspace: "WS-1", path: "out.txt", locator: { kind: "lines", start: 1, end: 2 }, cursor: "next" }).success, false);
  assert.equal(registered.read_workspace_file.inputSchema.safeParse({ workspace: "WS-1", path: "out.txt", cursor: "next" }).success, true);
  assert.equal(registered.read_workspace_execution_output.inputSchema.shape.stream.safeParse("stdout").success, true);
  assert.equal(registered.read_workspace_execution_output.inputSchema.shape.stream.safeParse("stdin").success, false);
  assert.match(registered.read_workspace_execution_output.description, /Continue reading.*opaque cursor/);
  assert.deepEqual(registered.exec_workspace.annotations, { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true });
  assert.match(registered.exec_workspace.description, /general-purpose Linux execution surface.*package installation.*outbound network/i);
  assert.equal(registered.read_workspace_transcript.outputSchema.safeParse({ workspace: "WS-1", events: [{ kind: "file_imported", sequence: 1, occurred_at: "2026-01-01T00:00:00Z", workspace: "WS-1", file: "LB-F1", path: "input.txt", byte_size: 4, sha256: "a".repeat(64) }], next_cursor: null }).success, true);
  assert.equal(registered.read_workspace_transcript.inputSchema.safeParse({ workspace: "WS-1" }).success, true);
  assert.equal(registered.read_workspace_transcript.inputSchema.safeParse({ workspace: "WS-1", from_sequence: 2, to_sequence: 4, limit: 10 }).success, true);
  assert.equal(registered.read_workspace_transcript.inputSchema.safeParse({ workspace: "WS-1", cursor: "next", from_sequence: 2 }).success, false);
  assert.equal(registered.read_workspace_transcript.inputSchema.safeParse({ workspace: "WS-1", cursor: "next" }).success, true);
  const result = await registered.exec_workspace.handler({ workspace: "WS-1", command: "true" });
  assert.equal(result.isError, true);
  assert.deepEqual(JSON.parse(result.content[0].text), { error: { code: "workspace_unavailable", message: "Workspace execution is not available yet" } });
});

test("Workspace input schemas are object-shaped in the actual MCP tools/list response", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  registerWorkspaceTools(server);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "1" });
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  const listed = await client.listTools();
  const byName = Object.fromEntries(listed.tools.map((tool) => [tool.name, tool]));

  for (const name of ["exec_workspace", "read_workspace_file", "read_workspace_transcript"]) {
    assert.equal(byName[name].inputSchema.type, "object");
    assert.ok(byName[name].inputSchema.properties);
  }
  assert.deepEqual(Object.keys(byName.exec_workspace.inputSchema.properties ?? {}).sort(), ["argv", "command", "cwd", "env", "secret_env", "stdin", "timeout_seconds", "workspace"].sort());
  assert.deepEqual(Object.keys(byName.read_workspace_file.inputSchema.properties ?? {}).sort(), ["cursor", "locator", "path", "workspace"].sort());
  assert.deepEqual(Object.keys(byName.read_workspace_transcript.inputSchema.properties ?? {}).sort(), ["cursor", "from_sequence", "limit", "to_sequence", "workspace"].sort());
  await client.close();
  await server.close();
});

test("read_workspace_file returns structured content through the real tools/call boundary", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const api = {
    workspaceAction: async () => ({ workspace: "WS-1", path: "out.txt", content: "generated text\n", media_type: "text/plain", range: { kind: "lines", start: 1, end: 1, byte_start: 0, byte_end: 14, complete: true }, next_cursor: null })
  } as unknown as LaterBenderApi;
  registerWorkspaceTools(server, api);
  const [clientTransport, serverTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "1" });
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  const result = await client.callTool({ name: "read_workspace_file", arguments: { workspace: "WS-1", path: "out.txt" } });
  assert.equal(result.isError, undefined);
  assert.deepEqual(result.structuredContent, {
    workspace: "WS-1", path: "out.txt", content: "generated text\n", media_type: "text/plain",
    range: { kind: "lines", start: 1, end: 1, byte_start: 0, byte_end: 14, complete: true }, next_cursor: null
  });
  await client.close();
  await server.close();
});

function registeredExecSchema() {
  return tools().exec_workspace.inputSchema;
}
