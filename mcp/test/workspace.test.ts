import assert from "node:assert/strict";
import { test } from "node:test";
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
  assert.equal(registered.create_workspace.inputSchema.safeParse({ environment: "future-linux", architecture: "riscv64", resources: { min_memory_bytes: 1024 } }).success, true);
  assert.equal(registered.create_workspace.outputSchema.safeParse({ workspace: {
    ref: "WS-1", label: null, state: "ready", environment: "future-linux", architecture: "riscv64",
    os: { name: "Linux", version: "1" }, shell: "/bin/bash", workspace_root: "/workspace",
    limits: { cpus: 2, memory_bytes: 1024, disk_bytes: 2048 }, capabilities: { internet: true, gpu: false, nested_virtualization: false },
    created_at: "2026-01-01T00:00:00Z", last_activity_at: "2026-01-01T00:00:00Z", expires_at: null
  } }).success, true);
});

test("execution input requires exactly shell or direct argv", () => {
  const schema = registeredExecSchema();
  assert.equal(schema.safeParse({ workspace: "WS-1", command: "echo hi" }).success, true);
  assert.equal(schema.safeParse({ workspace: "WS-1", argv: ["printf", "hi"] }).success, true);
  assert.equal(schema.safeParse({ workspace: "WS-1" }).success, false);
  assert.equal(schema.safeParse({ workspace: "WS-1", command: "echo hi", argv: ["echo", "hi"] }).success, false);
});

test("boundary operations expose stable result contracts and scaffold availability", async () => {
  const registered = tools();
  assert.equal(registered.put_file_in_workspace.inputSchema.shape.overwrite.safeParse(undefined).success, true);
  assert.equal(registered.read_workspace_file.inputSchema.shape.locator.safeParse({ kind: "lines", start: 1, end: 2 }).success, true);
  assert.equal(registered.read_workspace_file.inputSchema.shape.locator.safeParse({ kind: "pages", start: 1, end: 2 }).success, false);
  assert.equal(registered.read_workspace_execution_output.inputSchema.shape.stream.safeParse("stdout").success, true);
  assert.equal(registered.read_workspace_execution_output.inputSchema.shape.stream.safeParse("stdin").success, false);
  const result = await registered.exec_workspace.handler({ workspace: "WS-1", command: "true" });
  assert.equal(result.isError, true);
  assert.deepEqual(JSON.parse(result.content[0].text), { error: { code: "workspace_unavailable", message: "Workspace execution is not available yet" } });
});

function registeredExecSchema() {
  return tools().exec_workspace.inputSchema;
}
