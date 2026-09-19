import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { createHash } from "node:crypto";
import { z } from "zod";
import { ApiError, type FileEgress, LaterBenderApi } from "./api.js";
import { registerWorkspaceTools } from "./workspace.js";

const statuses = z.enum(["backlog", "ready", "doing", "done", "dropped"]);
const priorities = z.enum(["low", "normal", "high"]);
const timestamp = z.string();
const projectSummary = z.object({
  slug: z.string(),
  shorthand: z.string(),
  name: z.string(),
});
const project = projectSummary.extend({
  description: z.string().nullable(),
  task_count: z.number(),
  created_at: timestamp,
  updated_at: timestamp,
});
const relatedNote = z.object({
  id: z.number(),
  title: z.string(),
  project: projectSummary.nullable(),
});
const relatedFile = z.object({
  ref: z.string(),
  filename: z.string(),
  media_type: z.string(),
});
const taskSummary = z.object({
  ref: z.string(),
  number: z.number(),
  project: projectSummary,
  title: z.string(),
  status: statuses,
  position: z.number(),
  priority: priorities,
  tags: z.array(z.string()),
  related_note_ids: z.array(z.number()),
  created_at: timestamp,
  updated_at: timestamp,
});
const locator = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("lines"),
    start: z.number().int().positive(),
    end: z.number().int().positive(),
  }),
  z.object({
    kind: z.literal("pages"),
    start: z.number().int().positive(),
    end: z.number().int().positive(),
  }),
]);
const citation = z.object({
  file: z.string(),
  representation: z.string(),
  locator,
});
const task = taskSummary.extend({
  context: z.string().nullable(),
  intended_direction: z.string().nullable(),
  related_notes: z.array(relatedNote),
  related_files: z.array(relatedFile),
  citations: z.array(citation),
});
const relatedTask = z.object({
  ref: z.string(),
  number: z.number(),
  title: z.string(),
  status: statuses,
  priority: priorities,
  project: projectSummary,
});
const noteBase = z.object({
  id: z.number(),
  project: projectSummary.nullable(),
  title: z.string(),
  tags: z.array(z.string()),
  created_at: timestamp,
  updated_at: timestamp,
});
const noteSummary = noteBase.extend({ excerpt: z.string() });
const note = noteBase.extend({
  body: z.string(),
  related_task_refs: z.array(z.string()),
  related_tasks: z.array(relatedTask),
  related_files: z.array(relatedFile),
  citations: z.array(citation),
});
const mutationAcknowledgement = z.object({
  id: z.number(),
  updated_at: timestamp,
});
const taskMutationAcknowledgement = z.object({
  ref: z.string(),
  updated_at: timestamp,
});
const projectCreateOutput = {
  project: z.object({
    slug: z.string(),
    shorthand: z.string(),
    updated_at: timestamp,
  }),
};
const projectUpdateOutput = {
  project: z.object({ slug: z.string(), updated_at: timestamp }),
};
const taskMutationOutput = { task: taskMutationAcknowledgement };
const noteMutationOutput = { note: mutationAcknowledgement };
const noteDeletionOutput = { note: z.object({ id: z.number() }) };
const credential = z.object({
  ref: z.string(),
  name: z.string(),
  kind: z.enum(["env", "file"]),
  env_name: z.string().optional(),
  file_path: z.string().optional(),
  file_mode: z.number().int().optional(),
  created_at: timestamp,
  updated_at: timestamp,
});
const fileProject = z.object({
  slug: z.string(),
  shorthand: z.string(),
  name: z.string(),
});
const fileSummary = z.object({
  ref: z.string(),
  number: z.number(),
  filename: z.string(),
  media_type: z.string(),
  byte_size: z.number(),
  sha256: z.string(),
  tags: z.array(z.string()),
  project: fileProject,
  created_at: timestamp,
  updated_at: timestamp,
});
const representation = z.object({
  kind: z.string(),
  media_type: z.string().nullable(),
  coordinate: z.string().nullable(),
});
const urlOrigin = z.object({
  kind: z.literal("url"),
  requested_url: z.string(),
  final_url: z.string(),
  fetched_at: timestamp,
  etag: z.string().optional(),
  last_modified: z.string().optional(),
});
const fileProvenance = z
  .object({
    archive_ref: z.string().optional(),
    entry_path: z.string().optional(),
    origin: urlOrigin.optional(),
  })
  .nullable();
const file = fileSummary.extend({
  related_task_refs: z.array(z.string()),
  related_note_ids: z.array(z.number()),
  representations: z.array(representation),
  provenance: fileProvenance,
});
const archiveEntry = z.object({
  path: z.string(),
  kind: z.enum(["file", "directory", "symlink"]),
  uncompressed_size: z.number().nullable(),
  compressed_size: z.number().nullable(),
  media_type: z.string().nullable(),
  encrypted: z.boolean(),
  readable: z.boolean(),
});
const fileMutationOutput = {
  file: z.object({ ref: z.string(), updated_at: timestamp }),
};
const fileManagementOperation = z.discriminatedUnion("operation", [
  z.object({ operation: z.literal("delete"), ref: z.string().min(1) }),
]);
const manageFilesOutput = {
  results: z.array(
    z.object({
      operation: z.literal("delete"),
      ref: z.string(),
      status: z.enum(["succeeded", "not_found"]),
    }),
  ),
};
const searchHighlight = z.object({
  field: z.string(),
  fragments: z.array(z.string()),
});
const taskSearchResult = z
  .object({
    kind: z.literal("task"),
    ref: z.string(),
    number: z.number(),
    project: projectSummary,
    title: z.string(),
    snippet: z.string(),
    highlights: z.array(searchHighlight),
    tags: z.array(z.string()),
    status: statuses,
    priority: priorities,
    created_at: timestamp,
    updated_at: timestamp,
  })
  .strict();
const noteSearchResult = z
  .object({
    kind: z.literal("note"),
    id: z.number(),
    project: projectSummary.nullable(),
    title: z.string(),
    snippet: z.string(),
    highlights: z.array(searchHighlight),
    tags: z.array(z.string()),
    created_at: timestamp,
    updated_at: timestamp,
  })
  .strict();
const fileSearchResult = z
  .object({
    kind: z.literal("file"),
    ref: z.string(),
    number: z.number(),
    filename: z.string(),
    media_type: z.string(),
    project: fileProject,
    tags: z.array(z.string()),
    snippet: z.string(),
    match: z.object({ representation: z.string(), locator }),
    created_at: timestamp,
    updated_at: timestamp,
  })
  .strict();
const searchResult = z.discriminatedUnion("kind", [
  taskSearchResult,
  noteSearchResult,
  fileSearchResult,
]);
const cursorOutput = z.string().nullable();
const source = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("file"), ref: z.string() }),
  z.object({
    kind: z.literal("archive_entry"),
    ref: z.string(),
    path: z.string(),
  }),
]);
const textRead = z.object({
  kind: z.literal("text"),
  source,
  representation: z.string(),
  coordinate: z.literal("lines"),
  locator: z.object({
    kind: z.literal("lines"),
    start: z.number().int().positive(),
    end: z.number().int().positive(),
  }),
  media_type: z.string().nullable(),
  content: z.string(),
  metadata: z.record(z.string(), z.unknown()),
});
const pdfRead = z.object({
  kind: z.literal("pdf"),
  source,
  representation: z.string(),
  coordinate: z.literal("pages"),
  locator: z.object({
    kind: z.literal("pages"),
    start: z.number().int().positive(),
    end: z.number().int().positive(),
  }),
  media_type: z.string().nullable(),
  content: z.string(),
  metadata: z.record(z.string(), z.unknown()),
});
const metadataRead = z.object({
  kind: z.literal("metadata"),
  source,
  representation: z.string(),
  coordinate: z.null(),
  locator: z.null(),
  media_type: z.string().nullable(),
  metadata: z.record(z.string(), z.unknown()),
});
const readResult = z.discriminatedUnion("kind", [
  textRead,
  pdfRead,
  metadataRead,
]);
const readBatchResult = z.union([
  z.object({ ref: z.string(), read: readResult }),
  z.object({
    ref: z.string(),
    error: z.enum(["not_found", "invalid_locator"]),
  }),
]);

const readAnnotations = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};
const createAnnotations = {
  readOnlyHint: false,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false,
};
const updateAnnotations = {
  readOnlyHint: false,
  destructiveHint: true,
  idempotentHint: true,
  openWorldHint: false,
};
const result = (root: string, data: unknown) => ({
  content: [{ type: "text" as const, text: JSON.stringify({ [root]: data }) }],
  structuredContent: { [root]: data },
});
const failure = (error: unknown) => {
  const e =
    error instanceof ApiError
      ? error
      : new ApiError(
          "backend_unavailable",
          503,
          error instanceof Error ? error.message : "Backend unavailable",
        );
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({ error: { code: e.code, message: e.message } }),
      },
    ],
    isError: true,
  };
};
const safe = (root: string, fn: () => Promise<unknown>) =>
  fn()
    .then((data) => result(root, data))
    .catch(failure);
const safeObject = (fn: () => Promise<Record<string, unknown>>) =>
  fn()
    .then((data) => ({
      content: [{ type: "text" as const, text: JSON.stringify(data) }],
      structuredContent: data,
    }))
    .catch(failure);
const compactMutation = (root: string, fn: () => Promise<unknown>) =>
  safe(root, () =>
    fn().then((value) => {
      const mutation = value as {
        id?: unknown;
        ref?: unknown;
        updated_at?: unknown;
      };
      return root === "task" || root === "file"
        ? { ref: mutation.ref, updated_at: mutation.updated_at }
        : { id: mutation.id, updated_at: mutation.updated_at };
    }),
  );
const projectView = (value: any): any =>
  value && typeof value === "object"
    ? { slug: value.slug, shorthand: value.shorthand, name: value.name }
    : value;
const taskView = (value: any): any => {
  if (!value || typeof value !== "object") return value;
  const { id: _id, ...task } = value;
  const view: any = { ...task, project: projectView(task.project) };
  if (Array.isArray(task.related_notes))
    view.related_notes = task.related_notes.map((related: any) => ({
      ...related,
      project: related.project === null ? null : projectView(related.project),
    }));
  if (Array.isArray(task.related_tasks))
    view.related_tasks = task.related_tasks.map(taskView);
  return view;
};
const noteView = (value: any): any => {
  if (!value || typeof value !== "object") return value;
  const { related_task_ids: _ids, ...note } = value;
  const relatedTasks = note.related_tasks?.map(taskView) || [];
  return {
    ...note,
    project: note.project === null ? null : projectView(note.project),
    related_task_refs: relatedTasks.map((task: any) => task.ref),
    related_tasks: relatedTasks,
  };
};
const noteSummaryView = (value: any): any =>
  value && typeof value === "object"
    ? {
        ...value,
        project: value.project === null ? null : projectView(value.project),
      }
    : value;
const fileView = (value: any): any => {
  if (!value || typeof value !== "object") return value;
  const { id: _id, ...file } = value;
  return file;
};
const projectSearchView = projectView;
const highlightsSearchView = (value: any): any[] =>
  Array.isArray(value)
    ? value.map((highlight) => ({
        field: highlight.field,
        fragments: highlight.fragments,
      }))
    : [];
const taskSearchView = (value: any): any => ({
  kind: "task",
  ref: value.ref,
  number: value.number,
  project: projectSearchView(value.project),
  title: value.title,
  snippet: value.snippet,
  highlights: highlightsSearchView(value.highlights),
  tags: value.tags,
  status: value.status,
  priority: value.priority,
  created_at: value.created_at,
  updated_at: value.updated_at,
});
const noteSearchView = (value: any): any => ({
  kind: "note",
  id: value.id,
  project: value.project === null ? null : projectSearchView(value.project),
  title: value.title,
  snippet: value.snippet,
  highlights: highlightsSearchView(value.highlights),
  tags: value.tags,
  created_at: value.created_at,
  updated_at: value.updated_at,
});
const fileSearchView = (value: any): any => ({
  kind: "file",
  ref: value.ref,
  number: value.number,
  filename: value.filename,
  media_type: value.media_type,
  project: projectSearchView(value.project),
  tags: value.tags,
  snippet: value.snippet,
  match: value.match,
  created_at: value.created_at,
  updated_at: value.updated_at,
});
const citationInput = z.object({
  file: z.string(),
  representation: z.string().optional(),
  locator,
});
const taskFields = {
  title: z.string().optional(),
  status: statuses.optional(),
  position: z.number().int().optional(),
  priority: priorities.optional(),
  context: z.string().optional(),
  intended_direction: z.string().optional(),
  tags: z.array(z.string()).optional(),
  related_note_ids: z.array(z.number().int().positive()).optional(),
  citations: z.array(citationInput).optional(),
};
const providedFile = z
  .object({
    download_url: z.string().optional(),
    file_id: z.string().optional(),
    mime_type: z.string().optional(),
    file_name: z.string().optional(),
  })
  .strict();
const createFileInput = z
  .object({
    project: z.string(),
    file: providedFile.optional(),
    url: z.string().min(1).optional(),
    filename: z.string().optional(),
    tags: z.array(z.string()).optional(),
    related_task_refs: z.array(z.string()).optional(),
    related_note_ids: z.array(z.number().int().positive()).optional(),
  })
  .superRefine((value, context) => {
    if (value.file === undefined && value.url === undefined)
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["file"],
        message: "Exactly one of file or url is required",
      });
    if (value.file !== undefined && value.url !== undefined)
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["url"],
        message: "Exactly one of file or url is required",
      });
  });
const fileEgressTransport = z.enum(["resource_link", "embedded_resource"]);
const MAX_EMBEDDED_FILE_BYTES = 20 * 1024 * 1024;

const noteScopeInput = z
  .object({
    scope: z.enum(["global", "project", "all"]).optional(),
    project: z.string().optional(),
    tags: z.array(z.string()).optional(),
    sort: z.enum(["created_at", "updated_at"]).optional(),
    order: z.enum(["asc", "desc"]).optional(),
    limit: z.number().int().positive().max(100).optional(),
    cursor: z.string().optional(),
  })
  .superRefine((value, context) => {
    if (value.scope === "project" && !value.project)
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["project"],
        message: "scope=project requires project",
      });
    if (value.scope !== "project" && value.project)
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["project"],
        message: "project requires scope=project",
      });
  });
const searchInput = z
  .object({
    query: z.string(),
    scope: z.enum(["all", "global", "project"]).optional(),
    project: z.string().optional(),
    kinds: z.array(z.enum(["task", "note", "file"])).optional(),
    tags: z.array(z.string()).optional(),
    task_statuses: z.array(statuses).optional(),
    task_priorities: z.array(priorities).optional(),
    limit: z.number().int().positive().max(100).optional(),
  })
  .superRefine((value, context) => {
    if (value.scope === "project" && !value.project)
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["project"],
        message: "scope=project requires project",
      });
    if (value.scope !== "project" && value.project)
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["project"],
        message: "project requires scope=project",
      });
  });

async function canonicalFileBytes(
  api: LaterBenderApi,
  file: FileEgress,
  limit?: number,
): Promise<Uint8Array> {
  if (limit !== undefined && file.byte_size > limit)
    throw new ApiError(
      "validation_failed",
      422,
      `File is too large to embed: ${file.byte_size} bytes exceeds the ${limit} byte limit`,
    );
  const bytes = await api.downloadFile(file.ref);
  if (bytes.byteLength !== file.byte_size)
    throw new ApiError(
      "backend_unavailable",
      502,
      `Canonical file size mismatch for ${file.ref}`,
    );
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  if (sha256 !== file.sha256)
    throw new ApiError(
      "backend_unavailable",
      502,
      `Canonical file digest mismatch for ${file.ref}`,
    );
  return bytes;
}

function egressMetadata(file: FileEgress) {
  return {
    ref: file.ref,
    filename: file.filename,
    media_type: file.media_type,
    byte_size: file.byte_size,
    sha256: file.sha256,
  };
}

export function registerTools(server: McpServer, api: LaterBenderApi): void {
  server.registerTool(
    "list_credentials",
    {
      description:
        "List metadata for the authenticated user's durable Credentials. Secret values are never returned; use refs only when creating a Workspace.",
      inputSchema: {
        kind: z.enum(["env", "file"]).optional(),
        limit: z.number().int().positive().max(100).optional(),
        cursor: z.string().optional(),
      },
      outputSchema: {
        credentials: z.array(credential),
        next_cursor: cursorOutput,
      },
      annotations: readAnnotations,
    },
    (input) =>
      safeObject(() =>
        api.listCredentials(input).then((page) => ({
          credentials: page.items,
          next_cursor: page.next_cursor,
        })),
      ),
  );
  server.registerTool(
    "list_projects",
    {
      description:
        "Browse Projects visible to the authenticated user in deterministic creation order. Continue with the opaque next_cursor until it is null.",
      inputSchema: {
        limit: z.number().int().positive().max(100).optional(),
        cursor: z.string().optional(),
      },
      outputSchema: { projects: z.array(project), next_cursor: cursorOutput },
      annotations: readAnnotations,
    },
    (input) =>
      safeObject(() =>
        api.listProjects(input).then((page) => ({
          projects: page.items,
          next_cursor: page.next_cursor,
        })),
      ),
  );
  server.registerTool(
    "get_project",
    {
      description: "Fetch one complete project by its human-readable slug.",
      inputSchema: { slug: z.string() },
      outputSchema: { project },
      annotations: readAnnotations,
    },
    ({ slug }) => safe("project", () => api.getProject(slug)),
  );
  server.registerTool(
    "create_project",
    {
      description:
        "Create a project. Omit slug to let Later Bender generate one from the name; the returned slug is the Project identity for subsequent calls.",
      inputSchema: {
        name: z.string(),
        slug: z.string().optional(),
        shorthand: z.string().optional(),
        description: z.string().optional(),
      },
      outputSchema: projectCreateOutput,
      annotations: createAnnotations,
    },
    (input) =>
      safe("project", () =>
        api.createProject(input).then((value: any) => ({
          slug: value.slug,
          shorthand: value.shorthand,
          updated_at: value.updated_at,
        })),
      ),
  );
  server.registerTool(
    "update_project",
    {
      description: "Update mutable Project fields by slug.",
      inputSchema: {
        slug: z.string(),
        name: z.string().optional(),
        description: z.string().optional(),
      },
      outputSchema: projectUpdateOutput,
      annotations: updateAnnotations,
    },
    ({ slug, ...payload }) =>
      safe("project", () =>
        api.updateProject(slug, payload).then((value: any) => ({
          slug: value.slug,
          updated_at: value.updated_at,
        })),
      ),
  );

  server.registerTool(
    "list_tasks",
    {
      description:
        "Browse Tasks in a known project using structured filters and canonical board-position order. Use search_memory for approximate textual recall across Tasks, Notes, and Files. Continue with the opaque next_cursor until it is null; tags matches all supplied tags.",
      inputSchema: {
        project: z.string(),
        status: statuses.optional(),
        priority: priorities.optional(),
        tags: z.array(z.string()).optional(),
        limit: z.number().int().positive().max(100).optional(),
        cursor: z.string().optional(),
      },
      outputSchema: { tasks: z.array(taskSummary), next_cursor: cursorOutput },
      annotations: readAnnotations,
    },
    ({ project: projectSlug, tags, limit, cursor, ...filters }) =>
      safeObject(() =>
        api
          .listTasks(projectSlug, {
            ...filters,
            tags: tags?.join(","),
            limit: limit?.toString(),
            cursor,
          })
          .then((page) => ({
            tasks: (page.items as any[]).map(taskView),
            next_cursor: page.next_cursor,
          })),
      ),
  );
  server.registerTool(
    "get_task",
    {
      description:
        "Fetch the complete canonical Task by its external ref, such as LB-56.",
      inputSchema: { ref: z.string() },
      outputSchema: { task },
      annotations: readAnnotations,
    },
    ({ ref }) => safe("task", () => api.getTask(ref).then(taskView)),
  );
  server.registerTool(
    "get_tasks",
    {
      description:
        "Fetch complete canonical Tasks by exact external refs. Results preserve request order and include a per-ref not_found entry for missing Tasks.",
      inputSchema: { refs: z.array(z.string()).min(1).max(100) },
      outputSchema: {
        results: z.array(
          z.union([
            z.object({ ref: z.string(), task }),
            z.object({ ref: z.string(), error: z.literal("not_found") }),
          ]),
        ),
      },
      annotations: readAnnotations,
    },
    ({ refs }) =>
      safe("results", () =>
        api
          .getTasks(refs)
          .then((results: any[]) =>
            results.map((entry) =>
              entry.task ? { ...entry, task: taskView(entry.task) } : entry,
            ),
          ),
      ),
  );
  server.registerTool(
    "create_task",
    {
      description:
        "Create an actionable Task in a project. Omitted status and priority use Later Bender defaults (backlog and normal). position controls canonical board order; omitted position appends. Unknown tags are created automatically. related_note_ids links Notes that materially contributed to or contextualize the Task. citations are exact evidence pointers into canonical Files, distinct from broader related_files relationships.",
      inputSchema: {
        project: z.string(),
        title: z.string(),
        status: statuses.optional(),
        position: z.number().int().optional(),
        priority: priorities.optional(),
        context: z.string().optional(),
        intended_direction: z.string().optional(),
        tags: z.array(z.string()).optional(),
        related_note_ids: z.array(z.number().int().positive()).optional(),
        citations: z.array(citationInput).optional(),
      },
      outputSchema: taskMutationOutput,
      annotations: createAnnotations,
    },
    ({ project: projectSlug, ...payload }) =>
      compactMutation("task", () => api.createTask(projectSlug, payload)),
  );
  server.registerTool(
    "update_task",
    {
      description:
        "Partially update a Task by external ref. Omitted tags, related_note_ids, or citations preserve existing values; [] clears them; a non-empty array replaces them exactly. citations are exact evidence pointers into canonical Files, distinct from broader related_files relationships. Unknown tags are created automatically.",
      inputSchema: { ref: z.string(), ...taskFields },
      outputSchema: taskMutationOutput,
      annotations: updateAnnotations,
    },
    ({ ref, ...payload }) =>
      compactMutation("task", () => api.updateTask(ref, payload)),
  );

  server.registerTool(
    "list_notes",
    {
      description:
        "Browse compact Note summaries in a known scope with deterministic server-side ordering. Use search_memory instead for approximate recall. Defaults to global scope and updated_at desc; continue with the opaque next_cursor until it is null.",
      inputSchema: noteScopeInput,
      outputSchema: { notes: z.array(noteSummary), next_cursor: cursorOutput },
      annotations: readAnnotations,
    },
    (input) =>
      safeObject(() =>
        api.listNotes(input).then((page) => ({
          notes: (page.items as any[]).map(noteSummaryView),
          next_cursor: page.next_cursor,
        })),
      ),
  );
  server.registerTool(
    "get_note",
    {
      description:
        "Fetch the complete canonical Note after identifying it by global numeric ID, typically from a list or search result.",
      inputSchema: { id: z.number().int().positive() },
      outputSchema: { note },
      annotations: readAnnotations,
    },
    ({ id }) => safe("note", () => api.getNote(id).then(noteView)),
  );
  server.registerTool(
    "create_note",
    {
      description:
        "Store durable non-actionable context such as an idea, decision, finding, constraint, hypothesis, possible direction, or discussion result. Omit project for global context; provide a project slug for project-specific context. citations are exact evidence pointers into canonical Files, distinct from broader related_files relationships. Unknown tags are created automatically.",
      inputSchema: {
        title: z.string(),
        body: z.string(),
        project: z.string().optional(),
        tags: z.array(z.string()).optional(),
        citations: z.array(citationInput).optional(),
      },
      outputSchema: noteMutationOutput,
      annotations: createAnnotations,
    },
    (input) => compactMutation("note", () => api.createNote(input)),
  );
  server.registerTool(
    "update_note",
    {
      description:
        "Update Note metadata or deliberately replace whole fields by global ID. Omitted project, tags, or citations preserve them; empty arrays clear them. Use edit_note for targeted body maintenance.",
      inputSchema: {
        id: z.number().int().positive(),
        title: z.string().optional(),
        body: z.string().optional(),
        project: z.string().nullable().optional(),
        tags: z.array(z.string()).optional(),
        citations: z.array(citationInput).optional(),
      },
      outputSchema: noteMutationOutput,
      annotations: updateAnnotations,
    },
    ({ id, ...payload }) =>
      compactMutation("note", () => api.updateNote(id, payload)),
  );
  const noteEditOperation = z.discriminatedUnion("operation", [
    z.object({ operation: z.literal("append"), text: z.string() }),
    z.object({
      operation: z.literal("replace"),
      old_text: z.string().min(1),
      new_text: z.string(),
    }),
  ]);
  server.registerTool(
    "edit_note",
    {
      description:
        "Apply a small atomic batch of targeted body edits to a Note by global ID. Operations run in order; replace requires old_text to occur exactly once. expected_updated_at prevents overwriting a newer Note.",
      inputSchema: {
        id: z.number().int().positive(),
        operations: z.array(noteEditOperation).min(1).max(100),
        expected_updated_at: timestamp.optional(),
      },
      outputSchema: noteMutationOutput,
      annotations: updateAnnotations,
    },
    ({ id, ...payload }) =>
      compactMutation("note", () => api.editNote(id, payload)),
  );
  server.registerTool(
    "delete_note",
    {
      description:
        "Permanently delete a Note by global numeric ID. This is genuinely destructive and intended for erroneous or throwaway state; it is not archival or supersession. Existing durable Notes that are merely outdated should normally be updated or replaced semantically.",
      inputSchema: { id: z.number().int().positive() },
      outputSchema: noteDeletionOutput,
      annotations: { ...updateAnnotations, idempotentHint: false },
    },
    ({ id }) => safe("note", () => api.deleteNote(id)),
  );

  server.registerTool(
    "list_files",
    {
      description:
        "Browse immutable canonical Files in a project with deterministic server-side ordering. Defaults to created_at desc; continue with the opaque next_cursor until it is null. Tags match all supplied tags.",
      inputSchema: {
        project: z.string(),
        tags: z.array(z.string()).optional(),
        sort: z
          .enum(["created_at", "updated_at", "filename", "size"])
          .optional(),
        order: z.enum(["asc", "desc"]).optional(),
        limit: z.number().int().positive().max(100).optional(),
        cursor: z.string().optional(),
      },
      outputSchema: { files: z.array(fileSummary), next_cursor: cursorOutput },
      annotations: readAnnotations,
    },
    ({ project: projectSlug, tags, limit, cursor, sort, order }) =>
      safeObject(() =>
        api
          .listFiles(projectSlug, {
            tags: tags?.join(","),
            limit: limit?.toString(),
            cursor,
            sort,
            order,
          })
          .then((page) => ({
            files: (page.items as any[]).map(fileView),
            next_cursor: page.next_cursor,
          })),
      ),
  );
  server.registerTool(
    "get_file",
    {
      description:
        "Fetch canonical File metadata, relationships, and available readable representations by ref. Original bytes are not returned.",
      inputSchema: { ref: z.string() },
      outputSchema: { file },
      annotations: readAnnotations,
    },
    ({ ref }) => safe("file", () => api.getFile(ref).then(fileView)),
  );
  server.registerTool(
    "get_files",
    {
      description:
        "Fetch canonical Files by exact refs, preserving order and returning per-ref not_found entries.",
      inputSchema: { refs: z.array(z.string()).min(1).max(100) },
      outputSchema: {
        results: z.array(
          z.union([
            z.object({ ref: z.string(), file }),
            z.object({ ref: z.string(), error: z.literal("not_found") }),
          ]),
        ),
      },
      annotations: readAnnotations,
    },
    ({ refs }) =>
      safe("results", () =>
        api
          .getFiles(refs)
          .then((results: any[]) =>
            results.map((entry) =>
              entry.file ? { ...entry, file: fileView(entry.file) } : entry,
            ),
          ),
      ),
  );
  server.registerTool(
    "view_file_image",
    {
      description:
        "Return the exact canonical bytes of an image File as standard MCP image content for native multimodal inspection. The File must have an image media type.",
      inputSchema: { ref: z.string() },
      annotations: readAnnotations,
    },
    async ({ ref }) => {
      try {
        const file = await api.getFileEgress(ref);
        if (!file.media_type.startsWith("image/"))
          throw new ApiError(
            "validation_failed",
            422,
            `${file.ref} is not an image File`,
          );
        const bytes = await canonicalFileBytes(
          api,
          file,
          MAX_EMBEDDED_FILE_BYTES,
        );
        return {
          content: [
            {
              type: "text" as const,
              text: JSON.stringify({ file: egressMetadata(file) }),
            },
            {
              type: "image" as const,
              data: Buffer.from(bytes).toString("base64"),
              mimeType: file.media_type,
            },
          ],
        };
      } catch (error) {
        return failure(error);
      }
    },
  );
  server.registerTool(
    "retrieve_file",
    {
      description:
        "Return an immutable canonical File using standard MCP file content. Defaults to an embedded_resource for client-native attachment/materialization; embedded payloads are limited to 20 MiB. Use resource_link as the single alternative for clients that consume short-lived download links.",
      inputSchema: {
        ref: z.string(),
        transport: fileEgressTransport.optional(),
      },
      annotations: readAnnotations,
    },
    async ({ ref, transport = "embedded_resource" }) => {
      try {
        const file = await api.getFileEgress(ref);
        const downloadUrl = api.fileDownloadUrl(file.download_path);
        const text = {
          type: "text" as const,
          text: JSON.stringify({ file: egressMetadata(file), transport }),
        };
        if (transport === "resource_link") {
          return {
            content: [
              text,
              {
                type: "resource_link" as const,
                uri: downloadUrl,
                name: file.filename,
                mimeType: file.media_type,
                size: file.byte_size,
                description: `Canonical Later Bender File ${file.ref}; SHA-256 ${file.sha256}`,
              },
            ],
          };
        }
        const bytes = await canonicalFileBytes(
          api,
          file,
          MAX_EMBEDDED_FILE_BYTES,
        );
        const embeddedUri = new URL(downloadUrl);
        embeddedUri.search = "";
        return {
          content: [
            text,
            {
              type: "resource" as const,
              resource: {
                uri: embeddedUri.href,
                mimeType: file.media_type,
                blob: Buffer.from(bytes).toString("base64"),
              },
            },
          ],
        };
      } catch (error) {
        return failure(error);
      }
    },
  );
  server.registerTool(
    "create_file",
    {
      description:
        "Create one canonical immutable File from exactly one source. For an attached artifact, supply the provider-supplied file payload; do not construct attachment URLs or base64 data. For a remote public HTTP(S) artifact, supply url and Later Bender will fetch it with bounded network-safety controls. Exactly one of file or url is required.",
      inputSchema: createFileInput,
      outputSchema: fileMutationOutput,
      annotations: createAnnotations,
      _meta: { "openai/fileParams": ["file"] },
    },
    ({ project: projectSlug, file: provided, url, ...rest }) =>
      compactMutation("file", () =>
        api.createFile(projectSlug, {
          ...(provided === undefined ? {} : { file: provided }),
          ...(url === undefined ? {} : { url }),
          ...rest,
        }),
      ),
  );
  server.registerTool(
    "update_file_metadata",
    {
      description:
        "Update mutable File metadata only. File bytes and integrity are immutable; omitted tags and relationships preserve them, while empty arrays clear them.",
      inputSchema: {
        ref: z.string(),
        filename: z.string().optional(),
        tags: z.array(z.string()).optional(),
        related_task_refs: z.array(z.string()).optional(),
        related_note_ids: z.array(z.number().int().positive()).optional(),
      },
      outputSchema: fileMutationOutput,
      annotations: updateAnnotations,
    },
    ({ ref, ...payload }) =>
      compactMutation("file", () => api.updateFile(ref, payload)),
  );
  server.registerTool(
    "manage_files",
    {
      description:
        "Manage canonical File lifecycle operations. Supports permanently deleting a File by its external ref; File content remains immutable.",
      inputSchema: {
        operations: z.array(fileManagementOperation).min(1).max(100),
      },
      outputSchema: manageFilesOutput,
      annotations: { ...updateAnnotations, idempotentHint: false },
    },
    ({ operations }) =>
      safe("results", () =>
        Promise.all(
          operations.map(async (operation) => {
            try {
              await api.deleteFile(operation.ref);
              return {
                operation: operation.operation,
                ref: operation.ref,
                status: "succeeded" as const,
              };
            } catch (error) {
              if (error instanceof ApiError && error.code === "not_found")
                return {
                  operation: operation.operation,
                  ref: operation.ref,
                  status: "not_found" as const,
                };
              throw error;
            }
          }),
        ),
      ),
  );

  server.registerTool(
    "read_file",
    {
      description:
        "Read a bounded model-consumable File representation. If representation is omitted, auto selects the most useful available representation. Results identify the canonical File, effective representation, coordinate system, and effective locator; images return typed metadata only.",
      inputSchema: {
        ref: z.string(),
        representation: z.string().optional(),
        locator: locator.optional(),
      },
      outputSchema: { read: readResult },
      annotations: readAnnotations,
    },
    ({ ref, representation, locator }) =>
      safe("read", () => api.readFile(ref, representation, locator)),
  );
  server.registerTool(
    "read_files",
    {
      description:
        "Read multiple Files in request order with typed results and per-item not_found or invalid_locator errors. Omitted representation means auto; returned locators support bounded follow-up reads and citations.",
      inputSchema: {
        reads: z
          .array(
            z.object({
              ref: z.string(),
              representation: z.string().optional(),
              locator: locator.optional(),
            }),
          )
          .min(1)
          .max(100),
      },
      outputSchema: { results: z.array(readBatchResult) },
      annotations: readAnnotations,
    },
    ({ reads }) => safe("results", () => api.readFiles(reads)),
  );
  server.registerTool(
    "list_archive",
    {
      description:
        "Browse a canonical archive File in deterministic path order without promoting members into Files. path optionally scopes to a directory/prefix and depth bounds traversal; continue with the opaque next_cursor until it is null.",
      inputSchema: {
        ref: z.string(),
        path: z.string().optional(),
        depth: z.number().int().nonnegative().max(100).optional(),
        limit: z.number().int().positive().max(100).optional(),
        cursor: z.string().optional(),
      },
      outputSchema: {
        entries: z.array(archiveEntry),
        next_cursor: cursorOutput,
      },
      annotations: readAnnotations,
    },
    ({ ref, ...input }) =>
      safeObject(() =>
        api.listArchive(ref, input).then((page) => ({
          entries: page.items,
          next_cursor: page.next_cursor,
        })),
      ),
  );
  server.registerTool(
    "read_archive_entry",
    {
      description:
        "Read one exact member of one canonical archive File without creating a File. Results identify the archive ref and member path with typed text, PDF, or metadata output. Nested archives remain entries until explicitly read or extracted.",
      inputSchema: {
        ref: z.string(),
        path: z.string(),
        representation: z.string().optional(),
        locator: locator.optional(),
      },
      outputSchema: { read: readResult },
      annotations: readAnnotations,
    },
    ({ ref, path, representation, locator }) =>
      safe("read", () =>
        api.readArchiveEntry(ref, path, representation, locator),
      ),
  );
  server.registerTool(
    "extract_archive_entry",
    {
      description:
        "Explicitly promote one exact member of a canonical archive File into a new immutable canonical File. This is the only archive member promotion operation; no automatic archive explosion occurs. The parent archive is unchanged, provenance records archive_ref and entry_path, and the default project is the parent File project.",
      inputSchema: {
        ref: z.string(),
        path: z.string(),
        project: z.string().optional(),
        filename: z.string().optional(),
        tags: z.array(z.string()).optional(),
        related_task_refs: z.array(z.string()).optional(),
        related_note_ids: z.array(z.number().int().positive()).optional(),
      },
      outputSchema: fileMutationOutput,
      annotations: createAnnotations,
    },
    ({ ref, path, ...rest }) =>
      compactMutation("file", () =>
        api.extractArchiveEntry(ref, { path, ...rest }),
      ),
  );
  server.registerTool(
    "search_memory",
    {
      description:
        "Search Later Bender durable state across Tasks, Notes, and readable File representations. File matches return canonical refs and locators suitable for read_file.",
      inputSchema: searchInput,
      outputSchema: { results: z.array(searchResult) },
      annotations: readAnnotations,
    },
    (input) =>
      safe("results", () =>
        api
          .searchMemory(input)
          .then((response) =>
            response.results.map((entry: any) =>
              entry.kind === "task"
                ? taskSearchView(entry)
                : entry.kind === "note"
                  ? noteSearchView(entry)
                  : fileSearchView(entry),
            ),
          ),
      ),
  );
  registerWorkspaceTools(server, api);
}
