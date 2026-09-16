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

test("project responses omit persistence-only archive timestamps", async () => {
  const { api } = apiFor([{ status: 200, body: { id: 1, slug: "writing", name: "Writing", archived_at: null } }]);
  const project = await api.getProject("writing") as Record<string, unknown>;
  assert.equal(project.archived_at, undefined);
});

test("update_task sends only supplied fields", async () => {
  const { api, calls } = apiFor([{ status: 200, body: {} }]);
  await api.updateTask(7, { status: "done", tags: [] });
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { status: "done", tags: [] });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/tasks/7");
  assert.equal(calls[0].init.method, "PATCH");
});

test("create and update mutation handlers return only an acknowledgement", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api } = apiFor([
    { status: 201, body: { id: 3, name: "Created project", description: "large description", updated_at: "2026-01-01T00:00:00Z" } },
    { status: 200, body: { id: 3, name: "Updated project", description: "large description", updated_at: "2026-01-02T00:00:00Z" } },
    { status: 201, body: { id: 8, title: "Created", context: "large context", updated_at: "2026-01-03T00:00:00Z" } },
    { status: 201, body: { id: 18, title: "Created note", body: "large body", updated_at: "2026-01-04T00:00:00Z" } },
    { status: 200, body: { id: 7, title: "Ship", context: "large context", intended_direction: "large direction", updated_at: "2026-01-05T00:00:00Z" } },
    { status: 200, body: { id: 17, title: "Decision", body: "large body", updated_at: "2026-01-06T00:00:00Z" } }
  ]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const createdProjectResult = await tools.create_project.handler({ name: "Created project", description: "large description" });
  const updatedProjectResult = await tools.update_project.handler({ slug: "created-project", description: "large description" });
  const createdTaskResult = await tools.create_task.handler({ project: "writing", title: "Created", context: "large context" });
  const createdNoteResult = await tools.create_note.handler({ title: "Created note", body: "large body" });
  const taskResult = await tools.update_task.handler({ id: 7, context: "large context" });
  const noteResult = await tools.update_note.handler({ id: 17, body: "large body" });
  assert.deepEqual(createdProjectResult.structuredContent, { project: { id: 3, updated_at: "2026-01-01T00:00:00Z" } });
  assert.deepEqual(updatedProjectResult.structuredContent, { project: { id: 3, updated_at: "2026-01-02T00:00:00Z" } });
  assert.deepEqual(createdTaskResult.structuredContent, { task: { id: 8, updated_at: "2026-01-03T00:00:00Z" } });
  assert.deepEqual(createdNoteResult.structuredContent, { note: { id: 18, updated_at: "2026-01-04T00:00:00Z" } });
  assert.deepEqual(taskResult.structuredContent, { task: { id: 7, updated_at: "2026-01-05T00:00:00Z" } });
  assert.deepEqual(noteResult.structuredContent, { note: { id: 17, updated_at: "2026-01-06T00:00:00Z" } });
  assert.doesNotMatch(createdProjectResult.content[0].text, /large description/);
  assert.doesNotMatch(updatedProjectResult.content[0].text, /large description/);
  assert.doesNotMatch(createdTaskResult.content[0].text, /large context|intended_direction/);
  assert.doesNotMatch(createdNoteResult.content[0].text, /large body/);
  assert.doesNotMatch(taskResult.content[0].text, /large context|intended_direction/);
  assert.doesNotMatch(noteResult.content[0].text, /large body/);
  assert.equal(tools.create_project.outputSchema.safeParse(createdProjectResult.structuredContent).success, true);
  assert.equal(tools.create_task.outputSchema.safeParse(createdTaskResult.structuredContent).success, true);
  assert.equal(tools.create_note.outputSchema.safeParse(createdNoteResult.structuredContent).success, true);
  assert.equal(tools.update_task.outputSchema.safeParse(taskResult.structuredContent).success, true);
  assert.equal(tools.update_note.outputSchema.safeParse(noteResult.structuredContent).success, true);
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
  const tools = (server as any)._registeredTools as Record<string, any>;
  assert.deepEqual(Object.keys(tools).sort(), ["create_note", "create_project", "create_task", "get_note", "get_project", "get_task", "list_notes", "list_projects", "list_tasks", "search_memory", "update_note", "update_project", "update_task"]);
  assert.ok(tools.create_task.inputSchema);
  assert.ok(tools.update_task.inputSchema);
  assert.equal(tools.list_tasks.annotations.readOnlyHint, true);
  assert.equal(tools.update_task.annotations.destructiveHint, true);
  assert.equal(tools.search_memory.annotations.openWorldHint, false);
  assert.deepEqual(Object.keys(tools.list_tasks.inputSchema.shape), ["project", "status", "priority", "tags", "limit"]);
  assert.equal(tools.list_tasks.outputSchema.safeParse({ tasks: [{ id: 1, project: { id: 2, slug: "writing", name: "Writing" }, title: "Ship", status: "backlog", position: 1000, priority: "normal", tags: [], related_note_ids: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, true);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "task", id: 1, project: { id: 2, slug: "writing", name: "Writing" }, title: "Ship", snippet: "Ship", highlights: [], tags: [], status: "backlog", priority: "normal", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, true);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "note", id: 1, project: null, title: "Decision", snippet: "Decision", highlights: [], tags: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, true);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "note", id: 1, project: null, title: "Decision", snippet: "Decision", highlights: [], tags: [], status: "done", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, false);
  assert.equal(tools.list_notes.inputSchema.safeParse({ scope: "project" }).success, false);
  assert.equal(tools.list_notes.inputSchema.safeParse({ scope: "global", project: "writing" }).success, false);
  assert.equal(tools.list_notes.inputSchema.safeParse({}).success, true);
  assert.equal(tools.search_memory.inputSchema.safeParse({ query: "decision", scope: "all", project: "writing" }).success, false);
  assert.equal(tools.update_project.inputSchema.shape.archived_at, undefined);
});

test("keeps note summary and full-note schemas separate", () => {
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, new LaterBenderApi("https://example.test", "secret", fetch));
  const tools = (server as any)._registeredTools as Record<string, any>;
  const project = { id: 2, slug: "writing", name: "Writing" };
  const relatedTask = { id: 7, title: "Ship", status: "backlog", priority: "normal", project };
  const fullNote = {
    id: 17,
    project,
    title: "Decision",
    body: "Keep the API boring",
    tags: ["architecture"],
    related_task_ids: [7],
    related_tasks: [relatedTask],
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z"
  };
  const summary = { ...fullNote, excerpt: fullNote.body, related_task_ids: undefined, related_tasks: undefined };

  for (const toolName of ["get_note"]) {
    assert.equal(tools[toolName].outputSchema.safeParse({ note: fullNote }).success, true, toolName);
  }
  assert.equal(tools.create_note.outputSchema.safeParse({ note: { id: 17, updated_at: fullNote.updated_at } }).success, true);
  assert.equal(tools.update_note.outputSchema.safeParse({ note: { id: 17, updated_at: fullNote.updated_at } }).success, true);
  assert.equal(tools.get_note.outputSchema.safeParse({ note: { ...fullNote, excerpt: undefined } }).success, true);
  assert.equal(tools.get_note.outputSchema.safeParse({ note: { ...fullNote, body: undefined } }).success, false);
  assert.equal(tools.list_notes.outputSchema.safeParse({ notes: [{ ...summary, related_task_ids: undefined, related_tasks: undefined }] }).success, true);
  assert.equal(tools.list_notes.outputSchema.safeParse({ notes: [{ ...summary, excerpt: undefined, related_task_ids: undefined, related_tasks: undefined }] }).success, false);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "note", id: 17, project, title: "Decision", snippet: "Keep the API boring", highlights: [], tags: ["architecture"], created_at: fullNote.created_at, updated_at: fullNote.updated_at }] }).success, true);
});
