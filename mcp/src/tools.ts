import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { createHash } from "node:crypto";
import { ApiError, LaterBenderApi } from "./api.js";

const statuses = z.enum(["backlog", "ready", "doing", "done", "dropped"]);
const priorities = z.enum(["low", "normal", "high"]);
const timestamp = z.string();
const projectSummary = z.object({ id: z.number(), slug: z.string(), shorthand: z.string(), name: z.string() });
const project = projectSummary.extend({ description: z.string().nullable(), task_count: z.number(), created_at: timestamp, updated_at: timestamp });
const relatedNote = z.object({ id: z.number(), title: z.string(), project: projectSummary.nullable() });
const relatedFile = z.object({ ref: z.string(), filename: z.string(), media_type: z.string() });
const taskSummary = z.object({ ref: z.string(), number: z.number(), project: projectSummary, title: z.string(), status: statuses, position: z.number(), priority: priorities, tags: z.array(z.string()), related_note_ids: z.array(z.number()), created_at: timestamp, updated_at: timestamp });
const task = taskSummary.extend({ context: z.string().nullable(), intended_direction: z.string().nullable(), related_notes: z.array(relatedNote), related_files: z.array(relatedFile) });
const relatedTask = z.object({ ref: z.string(), number: z.number(), title: z.string(), status: statuses, priority: priorities, project: projectSummary });
const noteBase = z.object({ id: z.number(), project: projectSummary.nullable(), title: z.string(), tags: z.array(z.string()), created_at: timestamp, updated_at: timestamp });
const noteSummary = noteBase.extend({ excerpt: z.string() });
const note = noteBase.extend({ body: z.string(), related_task_ids: z.array(z.number()), related_tasks: z.array(relatedTask), related_files: z.array(relatedFile) });
const mutationAcknowledgement = z.object({ id: z.number(), updated_at: timestamp });
const taskMutationAcknowledgement = z.object({ ref: z.string(), updated_at: timestamp });
const projectMutationOutput = { project: mutationAcknowledgement };
const taskMutationOutput = { task: taskMutationAcknowledgement };
const noteMutationOutput = { note: mutationAcknowledgement };
const fileProject = z.object({ slug: z.string(), shorthand: z.string(), name: z.string() });
const fileSummary = z.object({ ref: z.string(), number: z.number(), filename: z.string(), media_type: z.string(), byte_size: z.number(), sha256: z.string(), tags: z.array(z.string()), project: fileProject, created_at: timestamp, updated_at: timestamp });
const file = fileSummary.extend({ related_task_refs: z.array(z.string()), related_note_ids: z.array(z.number()) });
const fileMutationOutput = { file: z.object({ ref: z.string(), updated_at: timestamp }) };
const searchHighlight = z.object({ field: z.string(), fragments: z.array(z.string()) });
const taskSearchResult = z.object({ kind: z.literal("task"), ref: z.string(), number: z.number(), project: projectSummary, title: z.string(), snippet: z.string(), highlights: z.array(searchHighlight), tags: z.array(z.string()), status: statuses, priority: priorities, created_at: timestamp, updated_at: timestamp }).strict();
const noteSearchResult = z.object({ kind: z.literal("note"), id: z.number(), project: projectSummary.nullable(), title: z.string(), snippet: z.string(), highlights: z.array(searchHighlight), tags: z.array(z.string()), created_at: timestamp, updated_at: timestamp }).strict();
const searchResult = z.discriminatedUnion("kind", [taskSearchResult, noteSearchResult]);

const readAnnotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const createAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
const updateAnnotations = { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false };
const result = (root: string, data: unknown) => ({ content: [{ type: "text" as const, text: JSON.stringify({ [root]: data }) }], structuredContent: { [root]: data } });
const failure = (error: unknown) => { const e = error instanceof ApiError ? error : new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable"); return { content: [{ type: "text" as const, text: JSON.stringify({ error: { code: e.code, message: e.message } }) }], structuredContent: { error: { code: e.code, message: e.message } }, isError: true }; };
const safe = (root: string, fn: () => Promise<unknown>) => fn().then((data) => result(root, data)).catch(failure);
const compactMutation = (root: string, fn: () => Promise<unknown>) => safe(root, () => fn().then((value) => {
  const mutation = value as { id?: unknown; ref?: unknown; updated_at?: unknown };
  return root === "task" || root === "file" ? { ref: mutation.ref, updated_at: mutation.updated_at } : { id: mutation.id, updated_at: mutation.updated_at };
}));
const taskView = (value: any): any => { if (!value || typeof value !== "object") return value; const { id: _id, ...task } = value; return { ...task, related_tasks: task.related_tasks?.map(taskView) }; };
const noteView = (value: any): any => value && typeof value === "object" ? { ...value, related_tasks: value.related_tasks?.map(taskView) } : value;
const fileView = (value: any): any => { if (!value || typeof value !== "object") return value; const { id: _id, ...file } = value; return file; };
const projectSearchView = (value: any): any => value && typeof value === "object" ? { id: value.id, slug: value.slug, shorthand: value.shorthand, name: value.name } : value;
const highlightsSearchView = (value: any): any[] => Array.isArray(value) ? value.map((highlight) => ({ field: highlight.field, fragments: highlight.fragments })) : [];
const taskSearchView = (value: any): any => ({ kind: "task", ref: value.ref, number: value.number, project: projectSearchView(value.project), title: value.title, snippet: value.snippet, highlights: highlightsSearchView(value.highlights), tags: value.tags, status: value.status, priority: value.priority, created_at: value.created_at, updated_at: value.updated_at });
const noteSearchView = (value: any): any => ({ kind: "note", id: value.id, project: value.project === null ? null : projectSearchView(value.project), title: value.title, snippet: value.snippet, highlights: highlightsSearchView(value.highlights), tags: value.tags, created_at: value.created_at, updated_at: value.updated_at });
const taskFields = { title: z.string().optional(), status: statuses.optional(), position: z.number().int().optional(), priority: priorities.optional(), context: z.string().optional(), intended_direction: z.string().optional(), tags: z.array(z.string()).optional(), related_note_ids: z.array(z.number().int().positive()).optional() };
const providedFile = z.object({ download_url: z.string().optional(), file_id: z.string().optional(), mime_type: z.string().optional(), file_name: z.string().optional() }).strict();

// TEMPORARY TRANSPORT PROBE: this intentionally accepts only the JSON value
// that the MCP client puts in a tool argument. It is not a File-domain shape.
const probeFileInput = z.object({ file: z.object({ download_url: z.string().optional(), file_id: z.string().optional(), mime_type: z.string().optional(), file_name: z.string().optional() }).passthrough() });
const probeFileOutput = z.object({
  received_bytes: z.boolean(), input_kind: z.string(), filename: z.string().nullable(), file_name: z.string().nullable(), mime_type: z.string().nullable(),
  file_id_present: z.boolean(), download_url_present: z.boolean(), byte_length: z.number().nullable(), downloaded_byte_length: z.number().nullable(),
  sha256: z.string().nullable(), text_preview: z.string().nullable(), http_status: z.number().nullable(), response_content_type: z.string().nullable(), download_error: z.string().nullable()
});
export const PROBE_MAX_DOWNLOAD_BYTES = 1024 * 1024;
const probeFile = async (value: unknown, fetcher: typeof fetch = fetch): Promise<z.infer<typeof probeFileOutput>> => {
  const encoder = new TextEncoder();
  const hash = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");
  const emptyDownload = { http_status: null, response_content_type: null, download_error: null };
  const base = (filename: string | null, mimeType: string | null, inputKind: string, extra: Partial<z.infer<typeof probeFileOutput>> = {}) => ({
    received_bytes: false, input_kind: inputKind, filename, file_name: filename, mime_type: mimeType,
    file_id_present: false, download_url_present: false, byte_length: null, downloaded_byte_length: null, sha256: null, text_preview: null,
    ...emptyDownload, ...extra
  });
  const text = (value: unknown, filename: string | null, mimeType: string | null, inputKind: string) => {
    const bytes = encoder.encode(value as string);
    return base(filename, mimeType, inputKind, { received_bytes: true, byte_length: bytes.byteLength, sha256: hash(bytes), text_preview: (value as string).slice(0, 120) });
  };
  if (typeof value === "string") return text(value, null, "text/plain", "string");
  if (!value || typeof value !== "object") return base(null, null, typeof value);
  const input = value as Record<string, unknown>;
  const filename = typeof input.filename === "string" ? input.filename : null;
  const mimeType = typeof input.mimeType === "string" ? input.mimeType : null;
  if (typeof input.text === "string") return text(input.text, filename, mimeType, "text");
  if (typeof input.data === "string" && input.encoding === "base64") {
    const bytes = Buffer.from(input.data, "base64");
    return base(filename, mimeType, "base64", { received_bytes: true, byte_length: bytes.byteLength, sha256: hash(bytes) });
  }
  if (typeof input.blob === "string") {
    const bytes = Buffer.from(input.blob, "base64");
    return base(filename, mimeType, "resource_blob", { received_bytes: true, byte_length: bytes.byteLength, sha256: hash(bytes) });
  }
  if (typeof input.download_url === "string" || typeof input.file_id === "string") {
    const fileName = typeof input.file_name === "string" ? input.file_name : filename;
    const providedMimeType = typeof input.mime_type === "string" ? input.mime_type : mimeType;
    const fileIdPresent = typeof input.file_id === "string";
    const downloadUrlPresent = typeof input.download_url === "string";
    const diagnostic = base(fileName, providedMimeType, "provided_file_payload", { file_id_present: fileIdPresent, download_url_present: downloadUrlPresent });
    if (!downloadUrlPresent) return diagnostic;
    try {
      const response = await fetcher(input.download_url as string, { method: "GET" });
      const responseContentType = response.headers.get("content-type");
      if (!response.ok) return { ...diagnostic, http_status: response.status, response_content_type: responseContentType, download_error: "download_failed" };
      const declaredLength = response.headers.get("content-length");
      if (declaredLength && Number(declaredLength) > PROBE_MAX_DOWNLOAD_BYTES) return { ...diagnostic, http_status: response.status, response_content_type: responseContentType, download_error: "download_too_large" };
      if (!response.body) return { ...diagnostic, http_status: response.status, response_content_type: responseContentType, download_error: "download_body_unavailable" };
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      const digest = createHash("sha256");
      let byteLength = 0;
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        byteLength += chunk.value.byteLength;
        if (byteLength > PROBE_MAX_DOWNLOAD_BYTES) {
          await reader.cancel();
          return { ...diagnostic, http_status: response.status, response_content_type: responseContentType, downloaded_byte_length: byteLength, download_error: "download_too_large" };
        }
        chunks.push(chunk.value);
        digest.update(chunk.value);
      }
      return { ...diagnostic, received_bytes: byteLength > 0, byte_length: byteLength, downloaded_byte_length: byteLength, sha256: byteLength > 0 ? digest.digest("hex") : null, http_status: response.status, response_content_type: responseContentType };
    } catch {
      return { ...diagnostic, download_error: "download_failed" };
    }
  }
  if (typeof input.uri === "string" || typeof input.path === "string") return base(filename, mimeType, typeof input.uri === "string" ? "uri" : "path");
  return base(filename, mimeType, "json_object");
};

const noteScopeInput = z.object({ scope: z.enum(["global", "project", "all"]).optional(), project: z.string().optional(), tags: z.array(z.string()).optional(), limit: z.number().int().positive().max(100).optional() }).superRefine((value, context) => {
  if (value.scope === "project" && !value.project) context.addIssue({ code: z.ZodIssueCode.custom, path: ["project"], message: "scope=project requires project" });
  if (value.scope !== "project" && value.project) context.addIssue({ code: z.ZodIssueCode.custom, path: ["project"], message: "project requires scope=project" });
});
const searchInput = z.object({ query: z.string(), scope: z.enum(["all", "global", "project"]).optional(), project: z.string().optional(), kinds: z.array(z.enum(["task", "note"])).optional(), tags: z.array(z.string()).optional(), task_statuses: z.array(statuses).optional(), task_priorities: z.array(priorities).optional(), limit: z.number().int().positive().max(100).optional() }).superRefine((value, context) => {
  if (value.scope === "project" && !value.project) context.addIssue({ code: z.ZodIssueCode.custom, path: ["project"], message: "scope=project requires project" });
  if (value.scope !== "project" && value.project) context.addIssue({ code: z.ZodIssueCode.custom, path: ["project"], message: "project requires scope=project" });
});

export function registerTools(server: McpServer, api: LaterBenderApi): void {
  server.registerTool("list_projects", { description: "List projects visible to the authenticated user.", inputSchema: {}, outputSchema: { projects: z.array(project) }, annotations: readAnnotations }, () => safe("projects", () => api.listProjects()));
  server.registerTool("get_project", { description: "Fetch one complete project by its human-readable slug.", inputSchema: { slug: z.string() }, outputSchema: { project }, annotations: readAnnotations }, ({ slug }) => safe("project", () => api.getProject(slug)));
  server.registerTool("create_project", { description: "Create a project. Omit slug to let Later Bender generate one from the name; shorthand is the stable human project key.", inputSchema: { name: z.string(), slug: z.string().optional(), shorthand: z.string().optional(), description: z.string().optional() }, outputSchema: projectMutationOutput, annotations: createAnnotations }, (input) => compactMutation("project", () => api.createProject(input)));
  server.registerTool("update_project", { description: "Update mutable project fields by slug.", inputSchema: { slug: z.string(), name: z.string().optional(), description: z.string().optional() }, outputSchema: projectMutationOutput, annotations: updateAnnotations }, ({ slug, ...payload }) => compactMutation("project", () => api.updateProject(slug, payload)));

  server.registerTool("list_tasks", { description: "Browse Tasks in a known project using structured filters. Use search_memory for approximate textual recall or when you do not know whether information is a Task or Note. tags matches all supplied tags; omitted or [] applies no tag filter.", inputSchema: { project: z.string(), status: statuses.optional(), priority: priorities.optional(), tags: z.array(z.string()).optional(), limit: z.number().int().positive().max(100).optional() }, outputSchema: { tasks: z.array(taskSummary) }, annotations: readAnnotations }, ({ project: projectSlug, tags, limit, ...filters }) => safe("tasks", () => api.listTasks(projectSlug, { ...filters, tags: tags?.join(","), limit: limit?.toString() }).then((tasks: any[]) => tasks.map(taskView))));
  server.registerTool("get_task", { description: "Fetch the complete canonical Task by its external ref, such as LB-56.", inputSchema: { ref: z.string() }, outputSchema: { task }, annotations: readAnnotations }, ({ ref }) => safe("task", () => api.getTask(ref).then(taskView)));
  server.registerTool("get_tasks", { description: "Fetch complete canonical Tasks by exact external refs. Results preserve request order and include a per-ref not_found entry for missing Tasks.", inputSchema: { refs: z.array(z.string()).min(1).max(100) }, outputSchema: { results: z.array(z.union([z.object({ ref: z.string(), task }), z.object({ ref: z.string(), error: z.literal("not_found") })])) }, annotations: readAnnotations }, ({ refs }) => safe("results", () => api.getTasks(refs).then((results: any[]) => results.map((entry) => entry.task ? { ...entry, task: taskView(entry.task) } : entry))));
  server.registerTool("create_task", { description: "Create an actionable Task in a project. Omitted status and priority use Later Bender defaults (backlog and normal). position controls canonical board order; omitted position appends. Unknown tags are created automatically. related_note_ids links Notes that materially contributed to or contextualize the Task.", inputSchema: { project: z.string(), title: z.string(), status: statuses.optional(), position: z.number().int().optional(), priority: priorities.optional(), context: z.string().optional(), intended_direction: z.string().optional(), tags: z.array(z.string()).optional(), related_note_ids: z.array(z.number().int().positive()).optional() }, outputSchema: taskMutationOutput, annotations: createAnnotations }, ({ project: projectSlug, ...payload }) => compactMutation("task", () => api.createTask(projectSlug, payload)));
  server.registerTool("update_task", { description: "Partially update a Task by external ref. Omitted tags or related_note_ids preserve existing relations; [] clears them; a non-empty array replaces them exactly. Unknown tags are created automatically.", inputSchema: { ref: z.string(), ...taskFields }, outputSchema: taskMutationOutput, annotations: updateAnnotations }, ({ ref, ...payload }) => compactMutation("task", () => api.updateTask(ref, payload)));

  server.registerTool("list_notes", { description: "Browse compact Note summaries in a known scope. Use search_memory instead for approximate recall. Omitted scope defaults to global; scope=project requires project, and project is forbidden for global/all.", inputSchema: noteScopeInput, outputSchema: { notes: z.array(noteSummary) }, annotations: readAnnotations }, (input) => safe("notes", () => api.listNotes(input)));
  server.registerTool("get_note", { description: "Fetch the complete canonical Note after identifying it by global numeric ID, typically from a list or search result.", inputSchema: { id: z.number().int().positive() }, outputSchema: { note }, annotations: readAnnotations }, ({ id }) => safe("note", () => api.getNote(id).then(noteView)));
  server.registerTool("create_note", { description: "Store durable non-actionable context such as an idea, decision, finding, constraint, hypothesis, observation, possible direction, or discussion result. Omit project for global context; provide a project slug for project-specific context. Unknown tags are created automatically.", inputSchema: { title: z.string(), body: z.string(), project: z.string().optional(), tags: z.array(z.string()).optional() }, outputSchema: noteMutationOutput, annotations: createAnnotations }, (input) => compactMutation("note", () => api.createNote(input)));
  server.registerTool("update_note", { description: "Partially update a Note by global ID. Omitted project or tags preserve them; project null makes it global; tags [] clears tags and a non-empty array replaces them exactly.", inputSchema: { id: z.number().int().positive(), title: z.string().optional(), body: z.string().optional(), project: z.string().nullable().optional(), tags: z.array(z.string()).optional() }, outputSchema: noteMutationOutput, annotations: updateAnnotations }, ({ id, ...payload }) => compactMutation("note", () => api.updateNote(id, payload)));

  server.registerTool("list_files", { description: "Browse immutable canonical Files in a project. Tags match all supplied tags.", inputSchema: { project: z.string(), tags: z.array(z.string()).optional(), limit: z.number().int().positive().max(100).optional() }, outputSchema: { files: z.array(fileSummary) }, annotations: readAnnotations }, ({ project: projectSlug, tags, limit }) => safe("files", () => api.listFiles(projectSlug, { tags: tags?.join(","), limit: limit?.toString() }).then((files: any[]) => files.map(fileView))));
  server.registerTool("get_file", { description: "Fetch canonical File metadata and relationships by ref. Original bytes are not returned.", inputSchema: { ref: z.string() }, outputSchema: { file }, annotations: readAnnotations }, ({ ref }) => safe("file", () => api.getFile(ref).then(fileView)));
  server.registerTool("get_files", { description: "Fetch canonical Files by exact refs, preserving order and returning per-ref not_found entries.", inputSchema: { refs: z.array(z.string()).min(1).max(100) }, outputSchema: { results: z.array(z.union([z.object({ ref: z.string(), file }), z.object({ ref: z.string(), error: z.literal("not_found") })])) }, annotations: readAnnotations }, ({ refs }) => safe("results", () => api.getFiles(refs).then((results: any[]) => results.map((entry) => entry.file ? { ...entry, file: fileView(entry.file) } : entry))));
  server.registerTool("create_file", { description: "Ingest an attached immutable source artifact into a project. The file argument is a provider-supplied attachment payload; do not construct download URLs or base64 data.", inputSchema: { project: z.string(), file: providedFile, filename: z.string().optional(), tags: z.array(z.string()).optional(), related_task_refs: z.array(z.string()).optional(), related_note_ids: z.array(z.number().int().positive()).optional() }, outputSchema: fileMutationOutput, annotations: createAnnotations, _meta: { "openai/fileParams": ["file"] } }, ({ project: projectSlug, file: provided, ...rest }) => compactMutation("file", () => api.createFile(projectSlug, { file: provided, ...rest })));
  server.registerTool("update_file_metadata", { description: "Update mutable File metadata only. File bytes and integrity are immutable; omitted tags and relationships preserve them, while empty arrays clear them.", inputSchema: { ref: z.string(), filename: z.string().optional(), tags: z.array(z.string()).optional(), related_task_refs: z.array(z.string()).optional(), related_note_ids: z.array(z.number().int().positive()).optional() }, outputSchema: fileMutationOutput, annotations: updateAnnotations }, ({ ref, ...payload }) => compactMutation("file", () => api.updateFile(ref, payload)));
  server.registerTool("delete_file", { description: "Permanently delete a canonical File and its original bytes.", inputSchema: { ref: z.string() }, outputSchema: { file: z.object({ ref: z.string() }) }, annotations: { ...updateAnnotations, idempotentHint: false } }, ({ ref }) => safe("file", () => api.deleteFile(ref).then(fileView)));

  server.registerTool("search_memory", { description: "Search Later Bender durable state across Tasks and Notes. Task results use external refs and Notes retain their existing behavior.", inputSchema: searchInput, outputSchema: { results: z.array(searchResult) }, annotations: readAnnotations }, (input) => safe("results", () => api.searchMemory(input).then((response) => response.results.map((entry: any) => entry.kind === "task" ? taskSearchView(entry) : noteSearchView(entry)))));
  server.registerTool("__TEMP_probe_file_input", { description: "TEMPORARY transport probe: report whether the JSON tool argument contains file bytes. Not a Later Bender File API.", inputSchema: probeFileInput.shape, outputSchema: { probe: probeFileOutput }, annotations: readAnnotations, _meta: { "openai/fileParams": ["file"] } }, async ({ file }) => result("probe", await probeFile(file)));
}
