import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError, LaterBenderApi } from "../src/api.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerTools } from "../src/tools.js";

function apiFor(responses: Array<{ status: number; body: unknown }>) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const api = new LaterBenderApi("https://example.test/laterbender", "secret", async (url, init) => {
    calls.push({ url: String(url), init });
    const response = responses.shift()!;
    return new Response(JSON.stringify(response.body), { status: response.status, headers: { "content-type": "application/json" } });
  });
  return { api, calls };
}

test("sends bearer auth and maps project and task endpoints", async () => {
  const { api, calls } = apiFor([{ status: 200, body: [] }, { status: 200, body: {} }, { status: 200, body: [] }]);
  await api.listProjects();
  await api.getProject("my project");
  await api.listTasks("writing", { status: "ready", q: "draft" });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/projects");
  assert.equal(calls[0].init.headers && new Headers(calls[0].init.headers).get("Authorization"), "Bearer secret");
  assert.equal(calls[1].url, "https://example.test/laterbender/api/projects/my%20project");
  assert.equal(calls[2].url, "https://example.test/laterbender/api/projects/writing/tasks?status=ready&q=draft&summary=true");
});

test("create_task uses the project-scoped task endpoint and task payload", async () => {
  const { api, calls } = apiFor([{ status: 201, body: {} }, { status: 200, body: {} }]);
  await api.createTask("writing", { title: "Ship", status: "backlog", priority: "normal", context: "A task", tags: ["release"] });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/projects/writing/tasks");
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { title: "Ship", status: "backlog", priority: "normal", context: "A task", tags: ["release"] });
  assert.equal(calls[0].init.method, "POST");
});

test("update_task sends only supplied fields", async () => {
  const { api, calls } = apiFor([{ status: 200, body: {} }]);
  await api.updateTask(7, { status: "done", tags: [] });
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { status: "done", tags: [] });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/tasks/7");
  assert.equal(calls[0].init.method, "PATCH");
});

test("preserves Rails validation failures and distinguishes auth/backend errors", async () => {
  const validation = apiFor([{ status: 422, body: { error: { code: "validation_failed", message: "Validation failed", details: { title: ["can't be blank"] } } } }]);
  await assert.rejects(validation.api.createProject({ name: "" }), (error: unknown) => error instanceof ApiError && error.code === "validation_failed" && error.details?.title?.[0] === "can't be blank");
  const unauthorized = apiFor([{ status: 401, body: { error: "Authentication required" } }]);
  await assert.rejects(unauthorized.api.listProjects(), (error: unknown) => error instanceof ApiError && error.code === "unauthorized");
  const unavailable = new LaterBenderApi("https://example.test", "secret", async () => { throw new Error("offline"); });
  await assert.rejects(unavailable.listProjects(), (error: unknown) => error instanceof ApiError && error.code === "backend_unavailable");
});

test("registers exactly the v1 tools with schemas", () => {
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, new LaterBenderApi("https://example.test", "secret", fetch));
  const tools = (server as any)._registeredTools as Record<string, { inputSchema: unknown }>;
  assert.deepEqual(Object.keys(tools).sort(), ["create_note", "create_project", "create_task", "get_note", "get_project", "get_task", "list_notes", "list_projects", "list_tasks", "search_memory", "update_note", "update_project", "update_task"]);
  assert.ok(tools.create_task.inputSchema);
  assert.ok(tools.update_task.inputSchema);
  assert.equal(tools.list_tasks.annotations.readOnlyHint, true);
  assert.equal(tools.update_task.annotations.destructiveHint, true);
  assert.equal(tools.search_memory.annotations.openWorldHint, false);
});
