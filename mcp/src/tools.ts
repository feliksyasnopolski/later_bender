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
  published: z.boolean(),
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
  z.object({ operation: z.literal("publish"), ref: z.string().min(1) }),
  z.object({ operation: z.literal("unpublish"), ref: z.string().min(1) }),
]);
const manageFilesOutput = {
  results: z.array(
    z.object({
      operation: z.enum(["delete", "publish", "unpublish"]),
      ref: z.string(),
      status: z.enum(["succeeded", "not_found"]),
      url: z.string().url().optional(),
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
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false,
};
const updateAnnotations = {
  readOnlyHint: true,
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
  Promise.resolve()
    .then(fn)
    .then((data) => result(root, data))
    .catch(failure);
const safeObject = (fn: () => Promise<Record<string, unknown>>) =>
  Promise.resolve()
    .then(fn)
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
  related_file_refs: z.array(z.string()).optional(),
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
  })
  .meta({
    oneOf: [
      { required: ["file"], not: { required: ["url"] } },
      { required: ["url"], not: { required: ["file"] } },
    ],
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
  const nativeCapabilities = [
    {
      name: "memory.search",
      description:
        "Find approximate matches across the authenticated user's Tasks, Notes, and Files.",
      workflow:
        'Call search_memory({query, scope:"all", limit:8}). Then use get_task({ref}) for a Task, get_note({id}) for a Note, or get_file({ref}) for a File. Prerequisites: a non-empty query; returned refs/IDs come from Later Bender.',
      tools: ["search_memory", "get_task", "get_note", "get_file"],
    },
    {
      name: "tasks.manage",
      description: "Find and update actionable Tasks in a user's Project.",
      workflow:
        'Call list_projects({}) or search_memory({query, kinds:["task"]}); call list_tasks({project, ...filters}) for board order; call get_task({ref}) before update_task({ref, ...changes}). Create with create_task({project, title, ...}). Prerequisite: project slug for list/create.',
      tools: [
        "list_projects",
        "list_tasks",
        "get_task",
        "get_tasks",
        "create_task",
        "update_task",
      ],
    },
    {
      name: "notes.manage",
      description:
        "Search, read, create, update, and make targeted edits to durable semantic Notes.",
      workflow:
        'Call search_memory({query, kinds:["note"]}) or list_notes({scope:"all"}); read via get_note({id}); create_note({title, body, project?}) or update_note({id, ...changes}). Use edit_note({id, operations}) for targeted body edits. Prerequisite: project slug when scoping a Note.',
      tools: [
        "search_memory",
        "list_notes",
        "get_note",
        "create_note",
        "update_note",
        "edit_note",
      ],
    },
    {
      name: "projects.manage",
      description:
        "Find and maintain the user's project scopes for Tasks and Files.",
      workflow:
        "Call list_projects({}) and use the returned slug with get_project({slug}); create with create_project({name, ...}) or update_project({slug, ...changes}). Prerequisite: use the returned project slug for project-scoped Tasks, Notes, and Files.",
      tools: [
        "list_projects",
        "get_project",
        "create_project",
        "update_project",
      ],
    },
    {
      name: "work-contexts",
      description:
        "Start, inspect, resume, and finish conversation-scoped working contexts.",
      workflow:
        "Call work_context_current({}); if empty, start with work_context_start({task?}) or list and resume with work_context_select({id}); use work_context_get({id}) for inspection. Attach an existing Task with work_context_attach_task({task}), and finish with work_context_finish({}). Work contexts are temporary working state, not durable Notes or Tasks.",
      tools: [
        "work_context_current",
        "work_context_list",
        "work_context_get",
        "work_context_start",
        "work_context_select",
        "work_context_attach_task",
        "work_context_finish",
        "scratchpad_read",
        "scratchpad_write",
      ],
    },
    {
      name: "files.manage",
      description:
        "Store and retrieve canonical project Files and their readable representations.",
      workflow:
        'Call list_projects({}); create_file({project, url:"https://public.example/file", filename:"report.pdf"}) for a public artifact, or supply the provider file payload; use search_memory({query, kinds:["file"]}) then get_file({ref}) and read_file({ref, ...}) for existing evidence. Prerequisite: project slug for creation; file ref for reads.',
      tools: [
        "list_projects",
        "create_file",
        "search_memory",
        "get_file",
        "read_file",
      ],
    },
    {
      name: "execution",
      description:
        "Create and inspect a transient Workspace, then run commands and collect output.",
      workflow:
        'Call get_workspace_capabilities({}) and list_workspace_targets({}); create_workspace({target?, executor?, environment?}) using supported requirements; inspect get_workspace({ref}) until state is ready; run exec_workspace({workspace:ref, argv:[...]}); inspect get_workspace_execution({ref:execution_ref}) and read_workspace_execution_output({ref:execution_ref, stream:"stdout"}). Prerequisite: eligible target/capabilities; persistent sessions also need a selected work context.',
      tools: [
        "get_workspace_capabilities",
        "list_workspace_targets",
        "create_workspace",
        "exec_workspace",
        "get_workspace_execution",
        "read_workspace_execution_output",
      ],
    },
    {
      name: "execution.sessions",
      description:
        "Select a Workspace for the current work context and interact with resumable executions.",
      workflow:
        'Call execution_current({}) and work_context_current({}); if there is no context, call work_context_start({}) or explicitly select one. Discover with get_workspace_capabilities({}) and list_workspace_targets({}); call execution_select({target, executor?, cwd?}) to acquire and bind a Workspace, or pass workspace to reuse one. Run exec_workspace({argv:[...]}) or exec_workspace({command, pty:true}) for a persistent terminal. Use execution_sessions({}) to rediscover sessions, session_select({ref}) to switch foreground, send_workspace_execution_input({data}) to send input, and read_workspace_execution_output({stream:"stdout", cursor?}) to collect output. Carry next_cursor forward; cancel_workspace_execution requires an explicit ref.',
      tools: [
        "work_context_current",
        "work_context_start",
        "work_context_select",
        "execution_current",
        "get_workspace_capabilities",
        "list_workspace_targets",
        "execution_select",
        "exec_workspace",
        "execution_sessions",
        "session_select",
        "send_workspace_execution_input",
        "get_workspace_execution",
        "read_workspace_execution_output",
        "cancel_workspace_execution",
      ],
    },
    {
      name: "workspace.lifecycle",
      description:
        "Discover, create, inspect, list, and destroy transient Workspaces.",
      workflow:
        "Call get_workspace_capabilities({}) and list_workspace_targets({}) before placement when requirements matter; create_workspace({target?, executor?, environment?, resources?, required_capabilities?}) then inspect get_workspace({ref}) until state is ready. Use list_workspaces({}) to rediscover surviving Workspaces. destroy_workspace({ref}) deletes the Workspace and its executions, filesystem, and transcript.",
      tools: [
        "get_workspace_capabilities",
        "list_workspace_targets",
        "create_workspace",
        "get_workspace",
        "list_workspaces",
        "destroy_workspace",
      ],
    },
    {
      name: "workspace.artifacts",
      description:
        "Move canonical Files into a Workspace and explicitly promote resulting artifacts or transcript evidence.",
      workflow:
        "Use put_file_in_workspace({workspace, file, path?}) to copy exact canonical File bytes; inspect with read_workspace_file({workspace, path, cursor?}). Promote an artifact with promote_workspace_file({workspace, path, project, ...}) or activity with promote_workspace_transcript({workspace, project, ...}). Promotion creates a canonical immutable File; prerequisites are an accessible Workspace and project slug.",
      tools: [
        "put_file_in_workspace",
        "read_workspace_file",
        "promote_workspace_file",
        "read_workspace_transcript",
        "promote_workspace_transcript",
        "list_files",
        "get_file",
        "read_file",
      ],
    },
    {
      name: "execution.interactive-terminal",
      description:
        "Run a long-lived interactive command and exchange terminal input/output.",
      workflow:
        'Call get_workspace_capabilities({}) and list_workspace_targets({}); create_workspace({target?, executor?}); inspect get_workspace({ref}) until ready; start exec_workspace({workspace:ref, argv:["bash"], pty:true}); continue with send_workspace_execution_input({data:"...\\n"}) and read_workspace_execution_output({stream:"stdout"}); call cancel_workspace_execution({ref:execution_ref}) when appropriate. Prerequisites: ready Workspace, supported target/executor, and a selected work context for persistent sessions.',
      tools: [
        "get_workspace_capabilities",
        "list_workspace_targets",
        "create_workspace",
        "exec_workspace",
        "get_workspace_execution",
        "send_workspace_execution_input",
        "read_workspace_execution_output",
        "cancel_workspace_execution",
      ],
    },
  ];
  server.registerTool(
    "capabilities",
    {
      description:
        "Browse Later Bender native tool workflows and saved model workflows. This describes Later Bender only.",
      inputSchema: z
        .object({
          name: z.string().optional(),
          query: z.string().optional(),
          detail: z.enum(["summary", "workflow", "schema"]).optional(),
        })
        .strict(),
      annotations: readAnnotations,
    },
    async ({ name, query, detail }) => {
      const saved = (await api.listModelWorkflows({ name, query })).workflows;
      const schemaFor = (toolName: string) => {
        const input = (server as any)._registeredTools?.[toolName]?.inputSchema;
        if (!input) return null;
        try {
          return z.toJSONSchema(
            typeof input.safeParse === "function" ? input : z.object(input),
          );
        } catch {
          return { available_via_tools_list: true };
        }
      };
      const selected = nativeCapabilities.filter(
        (item) =>
          (!name || item.name === name || item.name.startsWith(`${name}.`)) &&
          (!query ||
            query
              .toLowerCase()
              .split(/[^a-z0-9]+/)
              .filter(Boolean)
              .some((term) =>
                `${item.name} ${item.description} ${item.workflow}`
                  .toLowerCase()
                  .includes(term),
              )),
      );
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                native: selected.map(
                  ({ name: n, description, workflow, tools }) => ({
                    name: n,
                    description,
                    evidence: "native",
                    ...(detail === "workflow" ? { workflow, tools } : {}),
                    ...(detail === "schema"
                      ? {
                          workflow,
                          tools: tools.map((tool) => ({
                            name: tool,
                            input_schema: schemaFor(tool),
                          })),
                        }
                      : {}),
                  }),
                ),
                saved,
              },
              null,
              2,
            ),
          },
        ],
      };
    },
  );
  server.registerTool(
    "capabilities_save",
    {
      description:
        "Save or replace a model-discovered Later Bender workflow. Native tool schemas cannot be overwritten; saved workflow evidence is labeled claimed.",
      inputSchema: z
        .object({
          name: z.string(),
          description: z.string(),
          workflow: z.string(),
          tools: z.array(z.string()).optional(),
        })
        .strict(),
      annotations: updateAnnotations,
    },
    async (input) => {
      const result = await api.saveModelWorkflow(input);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    },
  );
  server.registerTool(
    "capabilities_delete",
    {
      description:
        "Permanently delete one saved model-discovered workflow by its exact name. Native workflows cannot be deleted. This cannot be undone.",
      inputSchema: z.object({ name: z.string().min(1).max(120) }).strict(),
      annotations: {
        ...updateAnnotations,
        readOnlyHint: false,
        idempotentHint: false,
      },
    },
    async ({ name }) => {
      await api.deleteModelWorkflow(name);
      return {
        content: [
          { type: "text", text: JSON.stringify({ deleted: true, name }) },
        ],
      };
    },
  );
  server.registerTool(
    "library_load",
    {
      description:
        "Load metadata for trusted agent-authored JavaScript libraries, or source for one named library. Returned source is for evaluation inside Code Mode.",
      inputSchema: z.object({ name: z.string().optional() }).strict(),
      annotations: readAnnotations,
    },
    async ({ name }) => {
      const result = await api.listModelLibraries(name);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    },
  );
  server.registerTool(
    "library_save",
    {
      description:
        "Persist trusted agent-authored JavaScript with syntax validation and prior snapshots.",
      inputSchema: z
        .object({
          name: z.string(),
          source: z.string(),
          description: z.string().optional(),
          exports: z.array(z.string()).optional(),
        })
        .strict(),
      annotations: createAnnotations,
    },
    async (input) => {
      try {
        new Function(input.source);
      } catch (error) {
        throw new Error(
          `Invalid JavaScript: ${error instanceof Error ? error.message : "syntax error"}`,
        );
      }
      const result = await api.saveModelLibrary(input);
      return { content: [{ type: "text", text: JSON.stringify(result) }] };
    },
  );
  server.registerTool(
    "library_delete",
    {
      description:
        "Permanently delete one saved model library by its exact name, including its saved versions. This cannot be undone.",
      inputSchema: z.object({ name: z.string().min(1).max(120) }).strict(),
      annotations: {
        ...updateAnnotations,
        readOnlyHint: false,
        idempotentHint: false,
      },
    },
    async ({ name }) => {
      await api.deleteModelLibrary(name);
      return {
        content: [
          { type: "text", text: JSON.stringify({ deleted: true, name }) },
        ],
      };
    },
  );
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
    (input: any) =>
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
    ({ slug, ...payload }: any) =>
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
        "Create an actionable Task in a project. Omitted status and priority use Later Bender defaults (backlog and normal). position controls canonical board order; omitted position appends. Unknown tags are created automatically. related_note_ids links Notes that materially contributed to or contextualize the Task. related_file_refs replaces the Task's generic File relationships when supplied. citations are exact evidence pointers into canonical Files, distinct from broader related_files relationships.",
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
        related_file_refs: z.array(z.string()).optional(),
        citations: z.array(citationInput).optional(),
      },
      outputSchema: taskMutationOutput,
      annotations: createAnnotations,
    },
    ({ project: projectSlug, ...payload }: any) =>
      compactMutation("task", () => api.createTask(projectSlug, payload)),
  );
  server.registerTool(
    "update_task",
    {
      description:
        "Partially update a Task by external ref. Omitted tags, related_note_ids, related_file_refs, or citations preserve existing values; [] clears them; a non-empty array replaces them exactly. related_file_refs mutates the same generic File relationship exposed by update_file_metadata. citations are exact evidence pointers into canonical Files, distinct from broader related_files relationships. Unknown tags are created automatically.",
      inputSchema: { ref: z.string(), ...taskFields },
      outputSchema: taskMutationOutput,
      annotations: updateAnnotations,
    },
    ({ ref, ...payload }: any) =>
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
    (input: any) => compactMutation("note", () => api.createNote(input)),
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
    ({ id, ...payload }: any) =>
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
    ({ id, ...payload }: any) =>
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
        "Manage canonical File lifecycle operations. Publish or unpublish an existing HTML File for unauthenticated read-only sharing, or permanently delete it. File content remains immutable.",
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
              const result =
                operation.operation === "delete"
                  ? await api.deleteFile(operation.ref)
                  : operation.operation === "publish"
                    ? await api.publishFile(operation.ref)
                    : await api.unpublishFile(operation.ref);
              return {
                operation: operation.operation,
                ref: operation.ref,
                status: "succeeded" as const,
                ...(operation.operation === "publish"
                  ? { url: (result as { url: string }).url }
                  : {}),
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
        "Read a bounded model-consumable File representation. Omit representation or use auto for the most useful available representation. To select explicitly, use a kind listed in this File's representations; kinds vary by File and can be extended, so representation is intentionally an open string rather than a global enum. Results identify the canonical File, effective representation, coordinate system, and effective locator; images return typed metadata only.",
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
        "Read multiple Files in request order with typed results and per-item not_found or invalid_locator errors. Omit representation or use auto per File; explicit representation kinds must be present in that File's representations and are intentionally not one global enum. Returned locators support bounded follow-up reads and citations.",
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
        "Read one exact member of one canonical archive File without creating a File. Omit representation or use auto (recommended); an explicit representation must match the kind derived from that member's media type, so valid kinds vary by entry and are not a global enum. A mismatching kind returns not_found. Results identify the archive ref and member path with typed text, PDF, or metadata output. Nested archives remain entries until explicitly read or extracted.",
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
  server.registerTool(
    "work_context_list",
    {
      description:
        "List recent work contexts, newest first, including inactive and finished contexts. Returns stable numeric IDs, associated Task, lifecycle state, and execution-selection metadata. Use next_before_id as before_id to page older history.",
      inputSchema: {
        limit: z.number().int().min(1).max(100).optional(),
        before_id: z.number().int().positive().optional(),
      },
      outputSchema: {
        contexts: z.array(z.unknown()),
        next_before_id: z.number().int().positive().nullable(),
      },
      annotations: readAnnotations,
    },
    ({ limit, before_id }) =>
      safeObject(() => api.listWorkContexts({ limit, beforeId: before_id })),
  );
  server.registerTool(
    "work_context_get",
    {
      description:
        "Inspect one of your own work contexts by its stable numeric ID, whether current, inactive, or finished. This does not change the selected context.",
      inputSchema: { id: z.number().int().positive() },
      outputSchema: { context: z.unknown() },
      annotations: readAnnotations,
    },
    ({ id }) => safeObject(() => api.getWorkContextById(id)),
  );
  server.registerTool(
    "work_context_select",
    {
      description:
        "Explicitly resume a work context by ID and bind it to this ChatGPT conversation. This transfers any existing conversation binding away from that context. Selecting a finished context reopens it. Other context-sensitive tools in this conversation can then omit context_id.",
      inputSchema: { id: z.number().int().positive() },
      outputSchema: { context: z.unknown() },
      annotations: updateAnnotations,
    },
    ({ id }) => safeObject(() => api.selectWorkContext(id)),
  );
  server.registerTool(
    "work_context_start",
    {
      description:
        "Start a new independent work context and bind it to this ChatGPT conversation when openai/session metadata is available. Multiple contexts may remain active concurrently under the same OAuth client. Pass task to connect it to an existing Task; omit task for an ephemeral context. Context-sensitive tools automatically resolve the conversation's selected context. Clients without conversation metadata must use the returned context.id explicitly. This is working-state, not workflow orchestration.",
      inputSchema: { task: z.string().min(1).optional() },
      outputSchema: { context: z.unknown() },
      annotations: createAnnotations,
    },
    ({ task }) => safeObject(() => api.startWorkContext(task)),
  );
  server.registerTool(
    "work_context_current",
    {
      description:
        "Return the work context bound to this ChatGPT conversation. Returns null when this conversation has no binding. Clients without ChatGPT conversation metadata cannot use implicit current-context lookup: use work_context_list, explicitly select a context, and pass context_id to context-sensitive tools. Never guess from an actor-global pointer. Do not use as a substitute for durable Tasks, Notes, or Files.",
      inputSchema: {},
      outputSchema: { context: z.unknown() },
      annotations: readAnnotations,
    },
    () => safeObject(() => api.getWorkContext()),
  );
  server.registerTool(
    "work_context_finish",
    {
      description:
        "Finish this conversation's selected work context; ChatGPT resolves it from openai/session metadata. Pass context_id for an explicit override or when using a client without conversation metadata. Its history and scratchpad remain stored; work_context_select can explicitly reopen it later.",
      inputSchema: { context_id: z.number().int().positive().optional() },
      outputSchema: { context: z.unknown() },
      annotations: updateAnnotations,
    },
    ({ context_id }) => safeObject(() => api.finishWorkContext(context_id)),
  );
  server.registerTool(
    "work_context_attach_task",
    {
      description:
        "Attach an existing Task to this conversation's selected work context; ChatGPT resolves it from openai/session metadata. Pass context_id for an explicit override or when using a client without conversation metadata. Use this when an initially ephemeral investigation becomes actionable work.",
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        task: z.string().min(1),
      },
      outputSchema: { context: z.unknown() },
      annotations: updateAnnotations,
    },
    ({ context_id, task }) =>
      safeObject(() => api.attachWorkContextTask(context_id, task)),
  );
  server.registerTool(
    "scratchpad_read",
    {
      description:
        "Read the private model working state for this conversation's selected context; ChatGPT normally resolves it via openai/session metadata. Pass context_id only for an explicit override or when using a client without conversation metadata. This is private model working state, optimized for efficient continuation rather than human-facing content. It may be stale or speculative; durable Tasks, Notes, Files, and current tool results remain authoritative.",
      inputSchema: { context_id: z.number().int().positive().optional() },
      outputSchema: { scratchpad: z.string() },
      annotations: readAnnotations,
    },
    ({ context_id }) => safeObject(() => api.readScratchpad(context_id)),
  );
  server.registerTool(
    "scratchpad_write",
    {
      description:
        "Replace the private model working state for this conversation's selected context as one atomic register; ChatGPT normally resolves it via openai/session metadata. Pass context_id only for an explicit override or when using a client without conversation metadata. This is private model working state ONLY, NEVER human-facing content. Optimize exclusively for efficient continuation. An empty string clears it.",
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        scratchpad: z.string(),
      },
      outputSchema: {
        updated_at: timestamp,
        character_count: z.number().int().nonnegative(),
      },
      annotations: updateAnnotations,
    },
    ({ context_id, scratchpad }) =>
      safeObject(() => api.writeScratchpad(context_id, scratchpad)),
  );
  registerWorkspaceTools(server, api);
}
