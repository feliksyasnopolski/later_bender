import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ApiError, LaterBenderApi } from "./api.js";

const statuses = z.enum(["backlog", "ready", "doing", "done", "dropped"]);
const priorities = z.enum(["low", "normal", "high"]);
const timestamp = z.string();
const projectSummary = z.object({ id: z.number(), slug: z.string(), name: z.string() });
const project = projectSummary.extend({ description: z.string().nullable(), task_count: z.number(), created_at: timestamp, updated_at: timestamp });
const relatedNote = z.object({ id: z.number(), title: z.string(), project: projectSummary.nullable() });
const taskSummary = z.object({ id: z.number(), project: projectSummary, title: z.string(), status: statuses, priority: priorities, tags: z.array(z.string()), related_note_ids: z.array(z.number()), created_at: timestamp, updated_at: timestamp });
const task = taskSummary.extend({ context: z.string().nullable(), intended_direction: z.string().nullable(), related_notes: z.array(relatedNote) });
const relatedTask = z.object({ id: z.number(), title: z.string(), status: statuses, priority: priorities, project: projectSummary });
const noteBase = z.object({ id: z.number(), project: projectSummary.nullable(), title: z.string(), tags: z.array(z.string()), created_at: timestamp, updated_at: timestamp });
const noteSummary = noteBase.extend({ excerpt: z.string() });
const note = noteBase.extend({ body: z.string(), related_task_ids: z.array(z.number()), related_tasks: z.array(relatedTask) });
const mutationAcknowledgement = z.object({ id: z.number(), updated_at: timestamp });
const taskMutationOutput = { task: mutationAcknowledgement };
const noteMutationOutput = { note: mutationAcknowledgement };
const searchHighlight = z.object({ field: z.string(), fragments: z.array(z.string()) });
const taskSearchResult = z.object({ kind: z.literal("task"), id: z.number(), project: projectSummary, title: z.string(), snippet: z.string(), highlights: z.array(searchHighlight), tags: z.array(z.string()), status: statuses, priority: priorities, created_at: timestamp, updated_at: timestamp }).strict();
const noteSearchResult = z.object({ kind: z.literal("note"), id: z.number(), project: projectSummary.nullable(), title: z.string(), snippet: z.string(), highlights: z.array(searchHighlight), tags: z.array(z.string()), created_at: timestamp, updated_at: timestamp }).strict();
const searchResult = z.discriminatedUnion("kind", [taskSearchResult, noteSearchResult]);

const readAnnotations = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const createAnnotations = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
const updateAnnotations = { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false };
const result = (root: string, data: unknown) => ({ content: [{ type: "text" as const, text: JSON.stringify({ [root]: data }) }], structuredContent: { [root]: data } });
const failure = (error: unknown) => { const e = error instanceof ApiError ? error : new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable"); return { content: [{ type: "text" as const, text: JSON.stringify({ error: { code: e.code, message: e.message } }) }], structuredContent: { error: { code: e.code, message: e.message } }, isError: true }; };
const safe = (root: string, fn: () => Promise<unknown>) => fn().then((data) => result(root, data)).catch(failure);
const compactMutation = (root: string, fn: () => Promise<unknown>) => safe(root, () => fn().then((value) => {
  const mutation = value as { id?: unknown; updated_at?: unknown };
  return { id: mutation.id, updated_at: mutation.updated_at };
}));
const taskFields = { title: z.string().optional(), status: statuses.optional(), priority: priorities.optional(), context: z.string().optional(), intended_direction: z.string().optional(), tags: z.array(z.string()).optional(), related_note_ids: z.array(z.number().int().positive()).optional() };

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
  server.registerTool("create_project", { description: "Create a project. Omit slug to let Later Bender generate one from the name.", inputSchema: { name: z.string(), slug: z.string().optional(), description: z.string().optional() }, outputSchema: { project }, annotations: createAnnotations }, (input) => safe("project", () => api.createProject(input)));
  server.registerTool("update_project", { description: "Update mutable project fields by slug.", inputSchema: { slug: z.string(), name: z.string().optional(), description: z.string().optional() }, outputSchema: { project }, annotations: updateAnnotations }, ({ slug, ...payload }) => safe("project", () => api.updateProject(slug, payload)));

  server.registerTool("list_tasks", { description: "Browse Tasks in a known project using structured filters. Use search_memory for approximate textual recall or when you do not know whether information is a Task or Note. tags matches all supplied tags; omitted or [] applies no tag filter.", inputSchema: { project: z.string(), status: statuses.optional(), priority: priorities.optional(), tags: z.array(z.string()).optional(), limit: z.number().int().positive().max(100).optional() }, outputSchema: { tasks: z.array(taskSummary) }, annotations: readAnnotations }, ({ project: projectSlug, tags, limit, ...filters }) => safe("tasks", () => api.listTasks(projectSlug, { ...filters, tags: tags?.join(","), limit: limit?.toString() })));
  server.registerTool("get_task", { description: "Fetch the complete canonical Task after identifying it by global numeric ID, typically from a list or search result.", inputSchema: { id: z.number().int().positive() }, outputSchema: { task }, annotations: readAnnotations }, ({ id }) => safe("task", () => api.getTask(id)));
  server.registerTool("create_task", { description: "Create an actionable Task in a project. Omitted status and priority use Later Bender defaults (backlog and normal). Unknown tags are created automatically. related_note_ids links Notes that materially contributed to or contextualize the Task.", inputSchema: { project: z.string(), title: z.string(), status: statuses.optional(), priority: priorities.optional(), context: z.string().optional(), intended_direction: z.string().optional(), tags: z.array(z.string()).optional(), related_note_ids: z.array(z.number().int().positive()).optional() }, outputSchema: taskMutationOutput, annotations: createAnnotations }, ({ project: projectSlug, ...payload }) => compactMutation("task", () => api.createTask(projectSlug, payload)));
  server.registerTool("update_task", { description: "Partially update a Task by global ID. Omitted tags or related_note_ids preserve existing relations; [] clears them; a non-empty array replaces them exactly. Unknown tags are created automatically.", inputSchema: { id: z.number().int().positive(), ...taskFields }, outputSchema: taskMutationOutput, annotations: updateAnnotations }, ({ id, ...payload }) => compactMutation("task", () => api.updateTask(id, payload)));

  server.registerTool("list_notes", { description: "Browse compact Note summaries in a known scope. Use search_memory instead for approximate recall. Omitted scope defaults to global; scope=project requires project, and project is forbidden for global/all.", inputSchema: noteScopeInput, outputSchema: { notes: z.array(noteSummary) }, annotations: readAnnotations }, (input) => safe("notes", () => api.listNotes(input)));
  server.registerTool("get_note", { description: "Fetch the complete canonical Note after identifying it by global numeric ID, typically from a list or search result.", inputSchema: { id: z.number().int().positive() }, outputSchema: { note }, annotations: readAnnotations }, ({ id }) => safe("note", () => api.getNote(id)));
  server.registerTool("create_note", { description: "Store durable non-actionable context such as an idea, decision, finding, constraint, hypothesis, observation, possible direction, or discussion result. Omit project for global context; provide a project slug for project-specific context. Unknown tags are created automatically.", inputSchema: { title: z.string(), body: z.string(), project: z.string().optional(), tags: z.array(z.string()).optional() }, outputSchema: noteMutationOutput, annotations: createAnnotations }, (input) => compactMutation("note", () => api.createNote(input)));
  server.registerTool("update_note", { description: "Partially update a Note by global ID. Omitted project or tags preserve them; project null makes it global; tags [] clears tags and a non-empty array replaces them exactly.", inputSchema: { id: z.number().int().positive(), title: z.string().optional(), body: z.string().optional(), project: z.string().nullable().optional(), tags: z.array(z.string()).optional() }, outputSchema: noteMutationOutput, annotations: updateAnnotations }, ({ id, ...payload }) => compactMutation("note", () => api.updateNote(id, payload)));

  server.registerTool("search_memory", { description: "Search Later Bender durable state across Tasks and Notes. Use this for recalling prior decisions, ideas, findings, project context, or work when you may not know where or how it was stored. Results are ranked summaries with matching excerpts; fetch the full Task or Note when exact details are needed. Omitted scope defaults to all; scope=project requires project, and project is forbidden for global/all.", inputSchema: searchInput, outputSchema: { results: z.array(searchResult) }, annotations: readAnnotations }, (input) => safe("results", () => api.searchMemory(input).then((response) => response.results)));
}
