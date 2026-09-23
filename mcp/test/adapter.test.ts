import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { ApiError, LaterBenderApi } from "../src/api.js";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { registerTools } from "../src/tools.js";
import { workspaceToolNames } from "../src/workspace.js";

async function railsSearchFixture() {
  return JSON.parse(await readFile(fileURLToPath(new URL("../../test/fixtures/rails_search_response.json", import.meta.url)), "utf8"));
}

function apiFor(responses: Array<{ status: number; body: unknown }>, publicBaseUrl?: string) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const api = new LaterBenderApi("https://example.test/laterbender", "secret", async (url, init) => {
    calls.push({ url: String(url), init });
    const response = responses.shift()!;
    return new Response(JSON.stringify(response.body), { status: response.status, headers: { "content-type": "application/json" } });
  }, publicBaseUrl);
  return { api, calls };
}

test("list_workspace_targets uses the target discovery endpoint", async () => {
  const { api, calls } = apiFor([{ status: 200, body: { targets: [] } }]);
  await api.listWorkspaceTargets();
  assert.equal(calls[0].url, "https://example.test/laterbender/api/workspaces/targets");
  assert.equal(calls[0].init.method, undefined);
});

test("sends bearer auth and maps project and task endpoints", async () => {
  const { api, calls } = apiFor([{ status: 200, body: { projects: [], next_cursor: null } }, { status: 200, body: {} }, { status: 200, body: { tasks: [], next_cursor: null } }]);
  await api.listProjects();
  await api.getProject("my project");
  await api.listTasks("writing", { status: "ready", q: "draft" });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/projects?paginated=true");
  assert.equal(calls[0].init.headers && new Headers(calls[0].init.headers).get("Authorization"), "Bearer secret");
  assert.equal(calls[1].url, "https://example.test/laterbender/api/projects/my%20project");
  assert.equal(calls[2].url, "https://example.test/laterbender/api/projects/writing/tasks?status=ready&q=draft&paginated=true&summary=true");
});

test("create_task uses the project-scoped task endpoint and task payload", async () => {
  const { api, calls } = apiFor([{ status: 201, body: {} }, { status: 200, body: {} }]);
  await api.createTask("writing", { title: "Ship", status: "backlog", priority: "normal", context: "A task", tags: ["release"], related_file_refs: ["LB-F7"] });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/projects/writing/tasks");
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { title: "Ship", status: "backlog", priority: "normal", context: "A task", tags: ["release"], related_file_refs: ["LB-F7"] });
  assert.equal(calls[0].init.method, "POST");
});

test("project responses omit persistence-only ids and archive timestamps", async () => {
  const { api } = apiFor([{ status: 200, body: { id: 1, slug: "writing", name: "Writing", archived_at: null } }]);
  const project = await api.getProject("writing") as Record<string, unknown>;
  assert.equal(project.archived_at, undefined);
  assert.equal(project.id, undefined);
});

test("update_task sends only supplied fields", async () => {
  const { api, calls } = apiFor([{ status: 200, body: {} }]);
  await api.updateTask("LB-7", { status: "done", tags: [] });
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { status: "done", tags: [] });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/tasks/by-ref/LB-7");
  assert.equal(calls[0].init.method, "PATCH");
});

test("task tools expose generic file relationship mutation", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api } = apiFor([{ status: 200, body: {} }, { status: 200, body: {} }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  assert.equal(tools.create_task.inputSchema.shape.related_file_refs.safeParse(["LB-F7"]).success, true);
  assert.equal(tools.update_task.inputSchema.shape.related_file_refs.safeParse([]).success, true);
  assert.match(tools.update_task.description, /same generic File relationship/);
});

test("MCP client lists every tool as read-only and closed-world", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api } = apiFor([]);
  registerTools(server, api);
  const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
  const [serverTransport, clientTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "1" });
  await server.connect(serverTransport);
  await client.connect(clientTransport);
  const listed = await client.listTools();

  assert.ok(listed.tools.length > 0);
  for (const tool of listed.tools) {
    assert.equal(tool.annotations?.readOnlyHint, true, `${tool.name} readOnlyHint`);
    assert.equal(tool.annotations?.openWorldHint, false, `${tool.name} openWorldHint`);
  }
  await client.close();
  await server.close();
});

test("get_tasks preserves order and returns per-ref not_found entries", async () => {
  const { api } = apiFor([
    { status: 200, body: { id: 1, ref: "LB-1" } },
    { status: 404, body: { error: "Not found" } },
    { status: 200, body: { id: 2, ref: "LB-2" } }
  ]);
  const result = await api.getTasks(["LB-1", "LB-404", "LB-2"]);
  assert.deepEqual(result, [
    { ref: "LB-1", task: { id: 1, ref: "LB-1" } },
    { ref: "LB-404", error: "not_found" },
    { ref: "LB-2", task: { id: 2, ref: "LB-2" } }
  ]);
});

test("delete_note uses a destructive non-idempotent delete and returns its id", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api, calls } = apiFor([{ status: 200, body: { id: 17 } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;
  const result = await tools.delete_note.handler({ id: 17 });
  assert.deepEqual(result.structuredContent, { note: { id: 17 } });
  assert.equal(calls[0].url, "https://example.test/laterbender/api/notes/17");
  assert.equal(calls[0].init.method, "DELETE");
  assert.equal(tools.delete_note.annotations.destructiveHint, true);
  assert.equal(tools.delete_note.annotations.idempotentHint, false);
  assert.equal(tools.delete_note.outputSchema.safeParse({ note: { id: 17 } }).success, true);
});

test("manage_files deletes independently, preserves order, and reports missing refs", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api, calls } = apiFor([
    { status: 200, body: { ref: "LB-F17" } },
    { status: 404, body: { error: { code: "not_found", message: "File not found" } } }
  ]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;
  const result = await tools.manage_files.handler({ operations: [
    { operation: "delete", ref: "LB-F17" },
    { operation: "delete", ref: "LB-MISSING" }
  ] });
  assert.deepEqual(result.structuredContent, { results: [
    { operation: "delete", ref: "LB-F17", status: "succeeded" },
    { operation: "delete", ref: "LB-MISSING", status: "not_found" }
  ] });
  assert.deepEqual(calls.map((call) => [call.url, call.init.method]), [
    ["https://example.test/laterbender/api/files/by-ref/LB-F17", "DELETE"],
    ["https://example.test/laterbender/api/files/by-ref/LB-MISSING", "DELETE"]
  ]);
  assert.equal(tools.manage_files.annotations.destructiveHint, true);
  assert.equal(tools.manage_files.annotations.idempotentHint, false);
  assert.equal(tools.manage_files.outputSchema.safeParse(result.structuredContent).success, true);
});

test("create_file accepts exactly one attachment or URL source and preserves URL acknowledgements", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api, calls } = apiFor([{ status: 201, body: { ref: "LB-F20", updated_at: "2026-09-17T12:00:00Z", filename: "ignored.txt" } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;
  const schema = tools.create_file.inputSchema;

  assert.equal(schema.safeParse({ project: "later-bender", file: { file_id: "file-1" } }).success, true);
  assert.equal(schema.safeParse({ project: "later-bender", url: "https://example.com/report.pdf" }).success, true);
  assert.equal(schema.safeParse({ project: "later-bender" }).success, false);
  assert.equal(schema.safeParse({ project: "later-bender", file: {}, url: "https://example.com/report.pdf" }).success, false);
  assert.deepEqual(tools.create_file._meta, { "openai/fileParams": ["file"] });
  assert.match(tools.create_file.description, /attached artifact.*file.*remote public HTTP\(S\).*url.*Exactly one/s);

  const result = await tools.create_file.handler({ project: "later-bender", url: "https://example.com/report.pdf", tags: ["source"] });
  assert.deepEqual(result.structuredContent, { file: { ref: "LB-F20", updated_at: "2026-09-17T12:00:00Z" } });
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { url: "https://example.com/report.pdf", tags: ["source"] });
});

test("preserves stable URL-ingestion errors from the backend", async () => {
  const { api } = apiFor([{ status: 422, body: { error: { code: "blocked_destination", message: "URL points to a blocked destination" } } }]);
  await assert.rejects(
    api.createFile("later-bender", { url: "http://127.0.0.1/" }),
    (error: unknown) => error instanceof ApiError && error.code === "blocked_destination" && error.message === "URL points to a blocked destination"
  );
});

test("view_file_image emits digest-verified canonical bytes as MCP image content", async () => {
  const bytes = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const sha256 = "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6";
  const calls: string[] = [];
  let downloadAuthorization: string | null = null;
  const api = new LaterBenderApi("http://backend.internal", "secret", async (url, init) => {
    calls.push(String(url));
    if (String(url).endsWith("/egress")) {
      return new Response(JSON.stringify({ file: { ref: "LB-F9", filename: "pixel.png", media_type: "image/png", byte_size: bytes.byteLength, sha256, download_path: "/rails/active_storage/blobs/redirect/signed/pixel.png" } }), { status: 200, headers: { "content-type": "application/json" } });
    }
    downloadAuthorization = new Headers(init?.headers).get("authorization");
    return new Response(bytes, { status: 200, headers: { "content-type": "image/png" } });
  }, "https://laterbender-api.example");
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.view_file_image.handler({ ref: "LB-F9" });

  assert.deepEqual(calls, [
    "http://backend.internal/api/files/by-ref/LB-F9/egress",
    "http://backend.internal/api/files/by-ref/LB-F9/download"
  ]);
  assert.equal(downloadAuthorization, "Bearer secret");
  assert.deepEqual(result.content[1], { type: "image", data: bytes.toString("base64"), mimeType: "image/png" });
  assert.deepEqual(JSON.parse(result.content[0].text), { file: { ref: "LB-F9", filename: "pixel.png", media_type: "image/png", byte_size: bytes.byteLength, sha256 } });
  assert.equal(result.structuredContent, undefined);
});

test("retrieve_file emits a public MCP resource link without downloading bytes", async () => {
  const sha256 = "a".repeat(64);
  const { api, calls } = apiFor([{ status: 200, body: { file: { ref: "LB-F10", filename: "report.pdf", media_type: "application/pdf", byte_size: 1234, sha256, download_path: "/rails/active_storage/blobs/redirect/signed/report.pdf" } } }], "https://files.example.test");
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.retrieve_file.handler({ ref: "LB-F10", transport: "resource_link" });

  assert.equal(calls.length, 1);
  assert.deepEqual(result.content[1], {
    type: "resource_link",
    uri: "https://files.example.test/rails/active_storage/blobs/redirect/signed/report.pdf",
    name: "report.pdf",
    mimeType: "application/pdf",
    size: 1234,
    description: `Canonical Later Bender File LB-F10; SHA-256 ${sha256}`
  });
  assert.equal(result.structuredContent, undefined);
});

test("retrieve_file defaults to a bounded embedded resource with a clean filename URI", async () => {
  const bytes = Buffer.from("exact binary bytes\u0000", "utf8");
  const sha256 = "bba2a0ad2ef7c1a046daeca1721c6973e26811ca5663113889b3d78ccd6c68cf";
  let requestCount = 0;
  const api = new LaterBenderApi("http://backend.internal", "secret", async () => {
    requestCount += 1;
    if (requestCount === 1) return new Response(JSON.stringify({ file: { ref: "LB-F11", filename: "payload.bin", media_type: "application/octet-stream", byte_size: bytes.byteLength, sha256, download_path: "/rails/active_storage/blobs/redirect/signed/payload.bin?disposition=attachment" } }), { status: 200, headers: { "content-type": "application/json" } });
    return new Response(bytes, { status: 200 });
  }, "https://files.example.test");
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.retrieve_file.handler({ ref: "LB-F11" });

  assert.deepEqual(result.content[1], {
    type: "resource",
    resource: {
      uri: "https://files.example.test/rails/active_storage/blobs/redirect/signed/payload.bin",
      mimeType: "application/octet-stream",
      blob: bytes.toString("base64")
    }
  });
  assert.equal(JSON.parse(result.content[0].text).transport, "embedded_resource");
  assert.equal(requestCount, 2);
});

test("create and update mutation handlers return only an acknowledgement", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api } = apiFor([
    { status: 201, body: { id: 3, slug: "created-project", shorthand: "CP", name: "Created project", description: "large description", updated_at: "2026-01-01T00:00:00Z" } },
    { status: 200, body: { id: 3, slug: "created-project", shorthand: "CP", name: "Updated project", description: "large description", updated_at: "2026-01-02T00:00:00Z" } },
    { status: 201, body: { ref: "LB-8", title: "Created", context: "large context", updated_at: "2026-01-03T00:00:00Z" } },
    { status: 201, body: { id: 18, title: "Created note", body: "large body", updated_at: "2026-01-04T00:00:00Z" } },
    { status: 200, body: { ref: "LB-7", title: "Ship", context: "large context", intended_direction: "large direction", updated_at: "2026-01-05T00:00:00Z" } },
    { status: 200, body: { id: 17, title: "Decision", body: "large body", updated_at: "2026-01-06T00:00:00Z" } }
  ]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const createdProjectResult = await tools.create_project.handler({ name: "Created project", description: "large description" });
  const updatedProjectResult = await tools.update_project.handler({ slug: "created-project", description: "large description" });
  const createdTaskResult = await tools.create_task.handler({ project: "writing", title: "Created", context: "large context" });
  const createdNoteResult = await tools.create_note.handler({ title: "Created note", body: "large body" });
  const taskResult = await tools.update_task.handler({ ref: "LB-7", context: "large context" });
  const noteResult = await tools.update_note.handler({ id: 17, body: "large body" });
  assert.deepEqual(createdProjectResult.structuredContent, { project: { slug: "created-project", shorthand: "CP", updated_at: "2026-01-01T00:00:00Z" } });
  assert.deepEqual(updatedProjectResult.structuredContent, { project: { slug: "created-project", updated_at: "2026-01-02T00:00:00Z" } });
  assert.deepEqual(createdTaskResult.structuredContent, { task: { ref: "LB-8", updated_at: "2026-01-03T00:00:00Z" } });
  assert.deepEqual(createdNoteResult.structuredContent, { note: { id: 18, updated_at: "2026-01-04T00:00:00Z" } });
  assert.deepEqual(taskResult.structuredContent, { task: { ref: "LB-7", updated_at: "2026-01-05T00:00:00Z" } });
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

test("browse tools preserve opaque cursors and strip internal project ids", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const project = { id: 3, slug: "writing", shorthand: "WR", name: "Writing" };
  const { api, calls } = apiFor([{ status: 200, body: { tasks: [{ id: 9, ref: "WR-9", number: 9, project, title: "Ship", status: "ready", position: 1000, priority: "high", tags: [], related_note_ids: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }], next_cursor: "opaque-next" } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.list_tasks.handler({ project: "writing", status: "ready", limit: 1, cursor: "opaque-current" });

  assert.equal(calls[0].url, "https://example.test/laterbender/api/projects/writing/tasks?status=ready&limit=1&cursor=opaque-current&paginated=true&summary=true");
  assert.deepEqual(result.structuredContent, { tasks: [{ ref: "WR-9", number: 9, project: { slug: "writing", shorthand: "WR", name: "Writing" }, title: "Ship", status: "ready", position: 1000, priority: "high", tags: [], related_note_ids: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }], next_cursor: "opaque-next" });
  assert.equal(tools.list_tasks.outputSchema.safeParse(result.structuredContent).success, true);
});

test("get_note translates internal task ids into external refs", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const project = { id: 3, slug: "writing", shorthand: "WR", name: "Writing" };
  const { api } = apiFor([{ status: 200, body: { id: 17, project, title: "Decision", body: "Keep it boring", tags: [], related_task_ids: [99], related_tasks: [{ id: 99, ref: "WR-7", number: 7, title: "Ship", status: "doing", priority: "normal", project }], related_files: [], citations: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-02T00:00:00Z" } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.get_note.handler({ id: 17 });

  assert.deepEqual(result.structuredContent.note.related_task_refs, ["WR-7"]);
  assert.equal(result.structuredContent.note.related_task_ids, undefined);
  assert.equal(result.structuredContent.note.related_tasks[0].id, undefined);
  assert.equal(result.structuredContent.note.project.id, undefined);
  assert.equal(tools.get_note.outputSchema.safeParse(result.structuredContent).success, true);
});

test("edit_note sends an ordered atomic edit batch and returns a compact acknowledgement", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api, calls } = apiFor([{ status: 200, body: { id: 17, body: "changed body", updated_at: "2026-01-02T00:00:00Z" } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;
  const operations = [{ operation: "append", text: "\nMore" }, { operation: "replace", old_text: "old", new_text: "new" }];

  const result = await tools.edit_note.handler({ id: 17, operations, expected_updated_at: "2026-01-01T00:00:00Z" });

  assert.equal(calls[0].url, "https://example.test/laterbender/api/notes/17/edit");
  assert.equal(calls[0].init.method, "PATCH");
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { operations, expected_updated_at: "2026-01-01T00:00:00Z" });
  assert.deepEqual(result.structuredContent, { note: { id: 17, updated_at: "2026-01-02T00:00:00Z" } });
});

test("read tools publish explicit text, PDF, metadata, and batch error schemas", () => {
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, new LaterBenderApi("https://example.test", "secret", fetch));
  const tools = (server as any)._registeredTools as Record<string, any>;
  const textRead = { kind: "text", source: { kind: "file", ref: "LB-F1" }, representation: "text", coordinate: "lines", locator: { kind: "lines", start: 1, end: 2 }, media_type: "text/plain", content: "one\ntwo\n", metadata: { coordinate: "lines" } };
  const pdfRead = { kind: "pdf", source: { kind: "archive_entry", ref: "LB-F2", path: "report.pdf" }, representation: "pdf_text", coordinate: "pages", locator: { kind: "pages", start: 2, end: 2 }, media_type: "text/plain", content: "[P2]\ntext\n", metadata: { coordinate: "pages", pages: 3 } };
  const metadataRead = { kind: "metadata", source: { kind: "file", ref: "LB-F3" }, representation: "metadata", coordinate: null, locator: null, media_type: "image/png", metadata: { byte_size: 8 } };

  assert.equal(tools.read_file.outputSchema.safeParse({ read: textRead }).success, true);
  assert.equal(tools.read_archive_entry.outputSchema.safeParse({ read: pdfRead }).success, true);
  assert.equal(tools.read_file.outputSchema.safeParse({ read: metadataRead }).success, true);
  assert.equal(tools.read_files.outputSchema.safeParse({ results: [{ ref: "LB-F1", read: textRead }, { ref: "LB-F404", error: "not_found" }, { ref: "LB-F1", error: "invalid_locator" }] }).success, true);
});

test("preserves Rails validation failures and distinguishes auth/backend errors", async () => {
  const validation = apiFor([{ status: 422, body: { error: { code: "validation_failed", message: "Validation failed", details: { title: ["can't be blank"] } } } }]);
  await assert.rejects(validation.api.createProject({ name: "" }), (error: unknown) => error instanceof ApiError && error.code === "validation_failed" && error.details?.title?.[0] === "can't be blank");
  const unauthorized = apiFor([{ status: 401, body: { error: "Authentication required" } }]);
  await assert.rejects(unauthorized.api.listProjects(), (error: unknown) => error instanceof ApiError && error.code === "unauthorized");
  const unavailable = new LaterBenderApi("https://example.test", "secret", async () => { throw new Error("offline"); });
  await assert.rejects(unavailable.listProjects(), (error: unknown) => error instanceof ApiError && error.code === "backend_unavailable");
});

test("tool failures use standard error content without schema-invalid structured content", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const { api } = apiFor([{ status: 422, body: { error: { code: "validation_failed", message: "Invalid cursor" } } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.list_tasks.handler({ project: "writing", cursor: "bad" });

  assert.equal(result.isError, true);
  assert.equal(result.structuredContent, undefined);
  assert.deepEqual(JSON.parse(result.content[0].text), { error: { code: "validation_failed", message: "Invalid cursor" } });
});

test("registers exactly the v1 tools with schemas", () => {
  const server = new McpServer({ name: "test", version: "1" });
  registerTools(server, new LaterBenderApi("https://example.test", "secret", fetch));
  const tools = (server as any)._registeredTools as Record<string, any>;
  assert.deepEqual(Object.keys(tools).sort(), ["create_file", "create_note", "create_project", "create_task", "delete_note", "edit_note", "extract_archive_entry", "get_file", "get_files", "get_note", "get_project", "get_task", "get_tasks", "list_archive", "list_credentials", "list_files", "list_notes", "list_projects", "list_tasks", "manage_files", "read_archive_entry", "read_file", "read_files", "retrieve_file", "search_memory", "update_file_metadata", "update_note", "update_project", "update_task", "view_file_image", ...workspaceToolNames].sort());
  assert.ok(tools.create_task.inputSchema);
  assert.equal(tools.create_task.inputSchema.shape.citations.safeParse([{ file: "LB-F7", representation: "text", locator: { kind: "lines", start: 138, end: 152 } }]).success, true);
  assert.equal(tools.create_task.inputSchema.shape.citations.safeParse([{ file: "LB-F7", locator: { kind: "bytes", start: 1, end: 2 } }]).success, false);
  assert.ok(tools.update_task.inputSchema);
  assert.match(tools.create_task.description, /exact evidence pointers into canonical Files/);
  assert.match(tools.create_note.description, /distinct from broader related_files relationships/);
  assert.match(tools.list_tasks.description, /Tasks, Notes, and Files/);
  assert.match(tools.read_file.description, /canonical File.*effective representation.*coordinate system.*effective locator/i);
  assert.match(tools.read_files.description, /typed results.*bounded follow-up reads and citations/i);
  assert.equal(tools.list_tasks.annotations.readOnlyHint, true);
  assert.equal(tools.update_task.annotations.destructiveHint, true);
  assert.deepEqual(tools.create_file._meta, { "openai/fileParams": ["file"] });
  assert.equal(tools.retrieve_file.inputSchema.shape.transport.safeParse("resource_link").success, true);
  assert.equal(tools.retrieve_file.inputSchema.shape.transport.safeParse("embedded_resource").success, true);
  assert.equal(tools.retrieve_file.inputSchema.shape.transport.safeParse("base64_json").success, false);
  assert.equal(tools.view_file_image.annotations.readOnlyHint, true);
  assert.match(tools.manage_files.description, /File lifecycle operations/);
  assert.equal(tools.manage_files.annotations.destructiveHint, true);
  assert.equal(tools.manage_files.annotations.idempotentHint, false);
  assert.equal(tools.manage_files.inputSchema.shape.operations.safeParse([{ operation: "delete", ref: "LB-F17" }]).success, true);
  assert.equal(tools.manage_files.inputSchema.shape.operations.safeParse([{ operation: "update", ref: "LB-F17" }]).success, false);
  assert.equal(tools.manage_files.inputSchema.shape.operations.safeParse([{ operation: "delete", ref: "" }]).success, false);
  assert.equal(tools.delete_file, undefined);
  assert.match(tools.delete_note.description, /Permanently delete.*not archival or supersession/);
  assert.equal(tools.delete_note.inputSchema.shape.id.safeParse(17).success, true);
  assert.equal(tools.delete_note.inputSchema.shape.id.safeParse(0).success, false);
  assert.equal(tools.search_memory.annotations.openWorldHint, false);
  assert.deepEqual(Object.keys(tools.list_tasks.inputSchema.shape), ["project", "status", "priority", "tags", "limit", "cursor"]);
  assert.equal(tools.list_tasks.outputSchema.safeParse({ tasks: [{ ref: "WR-1", number: 1, project: { slug: "writing", shorthand: "WR", name: "Writing" }, title: "Ship", status: "backlog", position: 1000, priority: "normal", tags: [], related_note_ids: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }], next_cursor: null }).success, true);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "task", ref: "WR-1", number: 1, project: { slug: "writing", shorthand: "WR", name: "Writing" }, title: "Ship", snippet: "Ship", highlights: [], tags: [], status: "backlog", priority: "normal", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, true);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "note", id: 1, project: null, title: "Decision", snippet: "Decision", highlights: [], tags: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, true);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "note", id: 1, project: null, title: "Decision", snippet: "Decision", highlights: [], tags: [], status: "done", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }] }).success, false);
  assert.equal(tools.get_note.outputSchema.safeParse({ note: { id: 1, project: null, title: "Decision", tags: [], body: "evidence", related_task_refs: [], related_tasks: [], related_files: [], citations: [{ file: "LB-F7", representation: "text", locator: { kind: "pages", start: 1, end: 2 } }], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" } }).success, true);
  assert.equal(tools.get_file.outputSchema.safeParse({ file: { ref: "LB-F7", number: 7, filename: "report.txt", media_type: "text/plain", byte_size: 4, sha256: "a".repeat(64), tags: [], project: { slug: "later-bender", shorthand: "LB", name: "Later Bender" }, related_task_refs: [], related_note_ids: [], representations: [], provenance: { origin: { kind: "url", requested_url: "https://example.com/report.txt", final_url: "https://cdn.example.com/report.txt", fetched_at: "2026-09-17T12:00:00Z" } }, created_at: "2026-09-17T12:00:00Z", updated_at: "2026-09-17T12:00:00Z" } }).success, true);
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
  const project = { slug: "writing", shorthand: "WR", name: "Writing" };
  const relatedTask = { ref: "WR-7", number: 7, title: "Ship", status: "backlog", priority: "normal", project };
  const fullNote = {
    id: 17,
    project,
    title: "Decision",
    body: "Keep the API boring",
    tags: ["architecture"],
    related_task_refs: ["WR-7"],
    related_tasks: [relatedTask],
    related_files: [],
    citations: [],
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z"
  };
  const summary = { ...fullNote, excerpt: fullNote.body, related_task_refs: undefined, related_tasks: undefined };

  for (const toolName of ["get_note"]) {
    assert.equal(tools[toolName].outputSchema.safeParse({ note: fullNote }).success, true, toolName);
  }
  assert.equal(tools.create_note.outputSchema.safeParse({ note: { id: 17, updated_at: fullNote.updated_at } }).success, true);
  assert.equal(tools.update_note.outputSchema.safeParse({ note: { id: 17, updated_at: fullNote.updated_at } }).success, true);
  assert.equal(tools.get_note.outputSchema.safeParse({ note: { ...fullNote, excerpt: undefined } }).success, true);
  assert.equal(tools.get_note.outputSchema.safeParse({ note: { ...fullNote, body: undefined } }).success, false);
  assert.equal(tools.list_notes.outputSchema.safeParse({ notes: [{ ...summary, related_task_refs: undefined, related_tasks: undefined }], next_cursor: null }).success, true);
  assert.equal(tools.list_notes.outputSchema.safeParse({ notes: [{ ...summary, excerpt: undefined, related_task_refs: undefined, related_tasks: undefined }], next_cursor: null }).success, false);
  assert.equal(tools.search_memory.outputSchema.safeParse({ results: [{ kind: "note", id: 17, project, title: "Decision", snippet: "Keep the API boring", highlights: [], tags: ["architecture"], created_at: fullNote.created_at, updated_at: fullNote.updated_at }] }).success, true);
});

test("projects mixed search results to their strict compact contracts", async () => {
  const server = new McpServer({ name: "test", version: "1" });
  const project = { id: 2, slug: "writing", shorthand: "WR", name: "Writing" };
  const { api } = apiFor([{ status: 200, body: { results: [
    { kind: "task", id: 7, ref: "WR-7", number: 7, project, title: "Ship", snippet: "Implement Workspace MCP contract", highlights: [{ field: "title", fragments: ["Implement Workspace MCP contract"] }], tags: [], status: "ready", priority: "high", related_tasks: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" },
    { kind: "note", id: 8, project: null, title: "Decision", snippet: "Keep it boring", highlights: [], tags: [], status: null, priority: null, ref: null, number: null, related_tasks: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" },
    { kind: "note", id: 9, project, title: "Project note", snippet: "A project detail", highlights: [], tags: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }
  ] } }]);
  registerTools(server, api);
  const tools = (server as any)._registeredTools as Record<string, any>;

  const result = await tools.search_memory.handler({ query: "ship" });
  const publicProject = { slug: "writing", shorthand: "WR", name: "Writing" };
  assert.deepEqual(result.structuredContent.results, [
    { kind: "task", ref: "WR-7", number: 7, project: publicProject, title: "Ship", snippet: "Implement Workspace MCP contract", highlights: [{ field: "title", fragments: ["Implement Workspace MCP contract"] }], tags: [], status: "ready", priority: "high", created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" },
    { kind: "note", id: 8, project: null, title: "Decision", snippet: "Keep it boring", highlights: [], tags: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" },
    { kind: "note", id: 9, project: publicProject, title: "Project note", snippet: "A project detail", highlights: [], tags: [], created_at: "2026-01-01T00:00:00Z", updated_at: "2026-01-01T00:00:00Z" }
  ]);
  assert.equal(tools.search_memory.outputSchema.safeParse(result.structuredContent).success, true);
  assert.equal(result.structuredContent.results[0].id, undefined);
  assert.equal(result.structuredContent.results[0].related_tasks, undefined);
  assert.equal(result.structuredContent.results[1].ref, undefined);
  assert.equal(result.structuredContent.results[1].number, undefined);
  assert.equal(result.structuredContent.results[1].related_tasks, undefined);
  const first = result.structuredContent.results[0];
  assert.equal(first.snippet, "Implement Workspace MCP contract");
  assert.deepEqual(first.highlights, [{ field: "title", fragments: ["Implement Workspace MCP contract"] }]);
  assert.doesNotMatch(first.snippet, /<em>|<\/em>|<mark>|<\/mark>/);
  assert.doesNotMatch(first.highlights[0].fragments[0], /<em>|<\/em>|<mark>|<\/mark>/);
});

test("projects the Rails-shaped mixed search fixture through the real MCP tools/call transport", async () => {
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
  const server = new McpServer({ name: "test", version: "1" });
  const fixture = await railsSearchFixture();
  const { api } = apiFor([{ status: 200, body: fixture }]);
  registerTools(server, api);
  const [serverTransport, clientTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "1" });
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);

  const result = await client.callTool({ name: "search_memory", arguments: { query: "contract" } });
  const structured = result.structuredContent as { results: Array<Record<string, any>> };
  assert.equal(structured.results.length, 3);
  assert.deepEqual(structured.results.map((entry) => entry.kind), ["task", "note", "file"]);
  assert.deepEqual(structured.results[2].project, { slug: "contract-project", shorthand: "CP", name: "Contract Project" });
  assert.equal(structured.results[2].project.id, undefined);
  assert.deepEqual(structured.results[2].match, { representation: "text", locator: { kind: "lines", start: 1, end: 2 } });
  assert.equal(structured.results[0].id, undefined);
  assert.equal(structured.results[1].ref, undefined);
  assert.equal(structured.results[2].snippet, "contract evidence");
  assert.equal(result.isError, undefined);
});

test("tools/list and tools/call expose and forward task file relationships", async () => {
  const { Client } = await import("@modelcontextprotocol/sdk/client/index.js");
  const { InMemoryTransport } = await import("@modelcontextprotocol/sdk/inMemory.js");
  const server = new McpServer({ name: "test", version: "1" });
  const { api, calls } = apiFor([{ status: 201, body: { ref: "LB-88", updated_at: "2026-09-19T00:00:00Z" } }]);
  registerTools(server, api);
  const [serverTransport, clientTransport] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: "test-client", version: "1" });
  await Promise.all([server.connect(serverTransport), client.connect(clientTransport)]);

  const listed = await client.listTools();
  const createTask = listed.tools.find((tool) => tool.name === "create_task");
  const updateTask = listed.tools.find((tool) => tool.name === "update_task");
  assert.equal((createTask?.inputSchema as any).properties.related_file_refs.type, "array");
  assert.equal((updateTask?.inputSchema as any).properties.related_file_refs.type, "array");

  const result = await client.callTool({ name: "create_task", arguments: { project: "later-bender", title: "Attach file", related_file_refs: ["LB-F42"] } });
  assert.deepEqual(result.structuredContent, { task: { ref: "LB-88", updated_at: "2026-09-19T00:00:00Z" } });
  assert.deepEqual(JSON.parse(String(calls[0].init.body)), { title: "Attach file", related_file_refs: ["LB-F42"] });
});
