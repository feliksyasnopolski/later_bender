import { createHash } from "node:crypto";
export type ApiErrorCode =
  | "unauthorized"
  | "not_found"
  | "validation_failed"
  | "backend_unavailable"
  | "workspace_unavailable"
  | "capability_unavailable"
  | "workspace_not_found"
  | "workspace_not_ready"
  | "execution_not_found"
  | "execution_not_running"
  | "invalid_cursor"
  | "invalid_range"
  | "not_text"
  | "path_invalid"
  | "path_not_found"
  | "path_exists"
  | "path_not_file"
  | "source_required"
  | "source_conflict"
  | "unsupported_url_scheme"
  | "invalid_url"
  | "blocked_destination"
  | "redirect_blocked_destination"
  | "too_many_redirects"
  | "fetch_timeout"
  | "upstream_http_failure"
  | "file_too_large"
  | "empty_fetch"
  | "credential_not_found"
  | "credential_conflict"
  | "credential_injection_failed"
  | "context_selection_required"
  | "target_not_found"
  | "executor_unsupported";

export class ApiError extends Error {
  constructor(
    public readonly code: ApiErrorCode,
    public readonly status: number,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export type FileEgress = {
  ref: string;
  filename: string;
  media_type: string;
  byte_size: number;
  sha256: string;
  download_path: string;
};

export type Page<T> = { items: T[]; next_cursor: string | null };

export class LaterBenderApi {
  private readonly conversationKey?: string;

  constructor(
    private readonly baseUrl = process.env.LATER_BENDER_API_BASE_URL,
    private readonly token?: string,
    private readonly fetcher: typeof fetch = fetch,
    private readonly publicBaseUrl = process.env
      .LATER_BENDER_PUBLIC_API_BASE_URL ||
      process.env.LATER_BENDER_OAUTH_ISSUER ||
      baseUrl,
    conversationId?: string,
  ) {
    if (!baseUrl) throw new Error("LATER_BENDER_API_BASE_URL is required");
    if (!publicBaseUrl)
      throw new Error("LATER_BENDER_PUBLIC_API_BASE_URL is required");
    this.conversationKey = conversationId
      ? createHash("sha256").update(conversationId).digest("hex")
      : undefined;
  }

  private contextSelector(contextId?: number): Record<string, string> {
    if (contextId !== undefined) return { context_id: contextId.toString() };
    if (this.conversationKey) return { conversation_key: this.conversationKey };
    throw new ApiError(
      "context_selection_required",
      409,
      "This client supplied no ChatGPT conversation identity; pass context_id explicitly.",
    );
  }

  private conversationPayload(
    payload: Record<string, unknown>,
  ): Record<string, unknown> {
    return this.conversationKey
      ? { ...payload, conversation_key: this.conversationKey }
      : payload;
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl!.replace(/\/$/, "")}${path}`;
    const started = performance.now();
    let response: Response;
    try {
      response = await this.fetcher(url, {
        ...init,
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}),
          ...init.headers,
        },
      });
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "backend_request",
          path: path.split("?")[0],
          status: "network_error",
          error_type: error instanceof Error ? error.name : "unknown",
          duration_ms: Math.round((performance.now() - started) * 100) / 100,
        }),
      );
      throw new ApiError(
        "backend_unavailable",
        503,
        error instanceof Error ? error.message : "Backend unavailable",
      );
    }
    const body = await response.json().catch(() => undefined);
    console.log(
      JSON.stringify({
        event: "backend_request",
        path: path.split("?")[0],
        status: response.status,
        ok: response.ok,
        duration_ms: Math.round((performance.now() - started) * 100) / 100,
      }),
    );
    if (!response.ok) {
      const error = body?.error;
      const code: ApiErrorCode =
        response.status === 401
          ? "unauthorized"
          : response.status === 404
            ? "not_found"
            : response.status === 409 &&
                error?.code === "context_selection_required"
              ? "context_selection_required"
              : response.status === 422 && typeof error?.code === "string"
                ? error.code
                : response.status === 422
                  ? "validation_failed"
                  : "backend_unavailable";
      throw new ApiError(
        code,
        response.status,
        error?.message ||
          (typeof error === "string" ? error : response.statusText),
        error?.details,
      );
    }
    return body as T;
  }

  getWorkContext(contextId?: number) {
    return this.request<{ context: unknown }>(
      `/api/work-context${query(this.contextSelector(contextId))}`,
    );
  }
  listWorkContexts(input: { limit?: number; beforeId?: number } = {}) {
    return this.request<{ contexts: unknown[]; next_before_id: number | null }>(
      `/api/work-contexts${query({ limit: input.limit?.toString(), before_id: input.beforeId?.toString() })}`,
    );
  }
  getWorkContextById(id: number) {
    return this.request<{ context: unknown }>(`/api/work-contexts/${id}`);
  }
  selectWorkContext(id: number) {
    return this.request<{ context: unknown }>(
      "/api/work-context/select",
      json("POST", this.conversationPayload({ id })),
    );
  }
  startWorkContext(task?: string) {
    return this.request<{ context: unknown }>(
      "/api/work-context",
      json("POST", this.conversationPayload(task ? { task } : {})),
    );
  }
  selectExecutionContext(
    payload: Record<string, unknown> & { context_id?: number },
  ) {
    const body =
      payload.context_id !== undefined
        ? payload
        : this.conversationPayload(payload);
    if (payload.context_id === undefined && !this.conversationKey)
      throw new ApiError(
        "context_selection_required",
        409,
        "Pass context_id explicitly when conversation metadata is unavailable.",
      );
    return this.request<Record<string, unknown>>(
      "/api/work-context/execution",
      json("POST", body),
    );
  }
  selectForegroundExecution(execution: string, contextId?: number) {
    const body =
      contextId !== undefined
        ? { execution, context_id: contextId }
        : { execution, ...this.contextSelector() };
    return this.request<Record<string, unknown>>(
      "/api/work-context/execution/foreground",
      json("POST", body),
    );
  }
  finishWorkContext(contextId?: number) {
    const body =
      contextId !== undefined
        ? { context_id: contextId }
        : this.contextSelector();
    return this.request<{ context: unknown }>(
      "/api/work-context/finish",
      json("POST", body),
    );
  }
  attachWorkContextTask(contextId: number | undefined, task: string) {
    const body =
      contextId !== undefined
        ? { context_id: contextId, task }
        : { ...this.contextSelector(), task };
    return this.request<{ context: unknown }>(
      "/api/work-context/task",
      json("POST", body),
    );
  }
  readScratchpad(contextId?: number) {
    return this.request<{ scratchpad: string }>(
      `/api/work-context/scratchpad${query(this.contextSelector(contextId))}`,
    );
  }
  writeScratchpad(contextId: number | undefined, scratchpad: string) {
    const body =
      contextId !== undefined
        ? { context_id: contextId, scratchpad }
        : { ...this.contextSelector(), scratchpad };
    return this.request<{ updated_at: string; character_count: number }>(
      "/api/work-context/scratchpad",
      json("PUT", body),
    );
  }

  listProjects(input: { limit?: number; cursor?: string } = {}) {
    return this.request<{ projects: unknown[]; next_cursor: string | null }>(
      `/api/projects${query({ paginated: "true", limit: input.limit?.toString(), cursor: input.cursor })}`,
    ).then((response) => ({
      items: response.projects.map(projectView),
      next_cursor: response.next_cursor,
    }));
  }
  getProject(slug: string) {
    return this.request<unknown>(
      `/api/projects/${encodeURIComponent(slug)}`,
    ).then(projectView);
  }
  createProject(payload: Record<string, unknown>) {
    return this.request<unknown>("/api/projects", json("POST", payload)).then(
      projectView,
    );
  }
  updateProject(slug: string, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/projects/${encodeURIComponent(slug)}`,
      json("PATCH", payload),
    ).then(projectView);
  }
  listTasks(project: string, filters: Record<string, string | undefined>) {
    return this.request<{ tasks: unknown[]; next_cursor: string | null }>(
      `/api/projects/${encodeURIComponent(project)}/tasks${query({ ...filters, paginated: "true", summary: "true" })}`,
    ).then((response) => ({
      items: response.tasks,
      next_cursor: response.next_cursor,
    }));
  }
  getTask(ref: string) {
    return this.request<unknown>(
      `/api/tasks/by-ref/${encodeURIComponent(ref)}`,
    );
  }
  createTask(project: string, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/projects/${encodeURIComponent(project)}/tasks`,
      json("POST", payload),
    );
  }
  updateTask(ref: string, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/tasks/by-ref/${encodeURIComponent(ref)}`,
      json("PATCH", payload),
    );
  }
  getTasks(refs: string[]) {
    return Promise.all(
      refs.map(async (ref) => {
        try {
          return { ref, task: await this.getTask(ref) };
        } catch (error) {
          if (error instanceof ApiError && error.code === "not_found")
            return { ref, error: "not_found" };
          throw error;
        }
      }),
    );
  }
  listNotes(input: {
    scope?: string;
    project?: string;
    tags?: string[];
    limit?: number;
    cursor?: string;
    sort?: string;
    order?: string;
  }) {
    const scope = input.scope || "global";
    const path =
      scope === "project" && input.project
        ? `/api/projects/${encodeURIComponent(input.project)}/notes`
        : "/api/notes";
    return this.request<{ notes: unknown[]; next_cursor: string | null }>(
      `${path}${query({ scope, tag: input.tags?.join(","), limit: input.limit?.toString(), cursor: input.cursor, sort: input.sort, order: input.order, paginated: "true", summary: "true" })}`,
    ).then((response) => ({
      items: response.notes,
      next_cursor: response.next_cursor,
    }));
  }
  getNote(id: number) {
    return this.request<unknown>(`/api/notes/${id}`);
  }
  deleteNote(id: number) {
    return this.request<unknown>(`/api/notes/${id}`, { method: "DELETE" });
  }
  createNote(payload: Record<string, unknown>) {
    const project =
      typeof payload.project === "string" ? payload.project : undefined;
    const body = { ...payload };
    delete body.project;
    const path = project
      ? `/api/projects/${encodeURIComponent(project)}/notes`
      : "/api/notes";
    return this.request<unknown>(path, json("POST", body));
  }
  updateNote(id: number, payload: Record<string, unknown>) {
    return this.request<unknown>(`/api/notes/${id}`, json("PATCH", payload));
  }
  editNote(id: number, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/notes/${id}/edit`,
      json("PATCH", payload),
    );
  }
  listFiles(project: string, filters: Record<string, string | undefined>) {
    return this.request<{ files: unknown[]; next_cursor: string | null }>(
      `/api/projects/${encodeURIComponent(project)}/files${query({ ...filters, paginated: "true" })}`,
    ).then((response) => ({
      items: response.files,
      next_cursor: response.next_cursor,
    }));
  }
  getFile(ref: string) {
    return this.request<unknown>(
      `/api/files/by-ref/${encodeURIComponent(ref)}`,
    );
  }
  getFileEgress(ref: string) {
    return this.request<{ file: FileEgress }>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/egress`,
    ).then((response) => response.file);
  }
  fileDownloadUrl(downloadPath: string) {
    if (!downloadPath.startsWith("/") || downloadPath.startsWith("//"))
      throw new ApiError(
        "backend_unavailable",
        502,
        "Backend returned an invalid file download path",
      );
    return new URL(downloadPath, this.publicBaseUrl).href;
  }
  async downloadFile(ref: string): Promise<Uint8Array> {
    const url = `${this.baseUrl!.replace(/\/$/, "")}/api/files/by-ref/${encodeURIComponent(ref)}/download`;
    let response: Response;
    try {
      response = await this.fetcher(url, {
        headers: {
          Accept: "*/*",
          ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}),
        },
      });
    } catch (error) {
      throw new ApiError(
        "backend_unavailable",
        503,
        error instanceof Error ? error.message : "Backend unavailable",
      );
    }
    if (!response.ok)
      throw new ApiError(
        response.status === 404 ? "not_found" : "backend_unavailable",
        response.status,
        response.statusText || "File download failed",
      );
    return new Uint8Array(await response.arrayBuffer());
  }
  getFiles(refs: string[]) {
    return Promise.all(
      refs.map(async (ref) => {
        try {
          return { ref, file: await this.getFile(ref) };
        } catch (error) {
          if (error instanceof ApiError && error.code === "not_found")
            return { ref, error: "not_found" };
          throw error;
        }
      }),
    );
  }
  createFile(project: string, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/projects/${encodeURIComponent(project)}/files`,
      json("POST", payload),
    );
  }
  updateFile(ref: string, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/files/by-ref/${encodeURIComponent(ref)}`,
      json("PATCH", payload),
    );
  }
  publishFile(ref: string) {
    return this.request<{ ref: string; url: string; updated_at: string }>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/publication`,
      json("POST", {}),
    );
  }
  unpublishFile(ref: string) {
    return this.request<{ ref: string; updated_at: string }>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/publication`,
      { method: "DELETE" },
    );
  }
  deleteFile(ref: string) {
    return this.request<unknown>(
      `/api/files/by-ref/${encodeURIComponent(ref)}`,
      { method: "DELETE" },
    );
  }
  readFile(
    ref: string,
    representation = "auto",
    locator?: Record<string, unknown>,
  ) {
    return this.request<unknown>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/read${query({ representation, locator: locator ? JSON.stringify(locator) : undefined })}`,
    );
  }
  readFiles(reads: Array<Record<string, unknown>>) {
    return Promise.all(
      reads.map(async (read) => {
        const ref = String(read.ref);
        try {
          return {
            ref,
            read: await this.readFile(
              ref,
              String(read.representation || "auto"),
              read.locator as Record<string, unknown> | undefined,
            ),
          };
        } catch (error) {
          if (error instanceof ApiError && error.code === "not_found")
            return { ref, error: "not_found" };
          if (error instanceof ApiError && error.code === "validation_failed")
            return { ref, error: "invalid_locator" };
          throw error;
        }
      }),
    );
  }
  listArchive(ref: string, input: Record<string, unknown>) {
    return this.request<{ entries: unknown[]; next_cursor: string | null }>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/archive${query({ path: input.path as string | undefined, depth: input.depth?.toString(), limit: input.limit?.toString(), cursor: input.cursor as string | undefined, paginated: "true" })}`,
    ).then((response) => ({
      items: response.entries,
      next_cursor: response.next_cursor,
    }));
  }
  readArchiveEntry(
    ref: string,
    path: string,
    representation = "auto",
    locator?: Record<string, unknown>,
  ) {
    return this.request<unknown>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/archive/entry${query({ path, representation, locator: locator ? JSON.stringify(locator) : undefined })}`,
    ).then((response: any) => response.read);
  }
  extractArchiveEntry(ref: string, payload: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/files/by-ref/${encodeURIComponent(ref)}/archive/extract`,
      json("POST", payload),
    );
  }
  searchMemory(input: Record<string, unknown>) {
    return this.request<{ results: unknown[] }>(
      `/api/search${query({ q: String(input.query), scope: String(input.scope || "all"), project: input.project as string | undefined, kinds: (input.kinds as string[] | undefined)?.join(","), tags: (input.tags as string[] | undefined)?.join(","), task_statuses: (input.task_statuses as string[] | undefined)?.join(","), task_priorities: (input.task_priorities as string[] | undefined)?.join(","), limit: String(input.limit || 8) })}`,
    );
  }
  getWorkspaceCapabilities() {
    return this.request<unknown>("/api/workspaces/capabilities");
  }
  listWorkspaceTargets() {
    return this.request<unknown>("/api/workspaces/targets");
  }
  createWorkspace(payload: Record<string, unknown>) {
    return this.request<unknown>("/api/workspaces", json("POST", payload));
  }
  listWorkspaces(input: Record<string, unknown>) {
    return this.request<unknown>(
      `/api/workspaces${query({ state: input.state as string | undefined, limit: input.limit?.toString(), cursor: input.cursor as string | undefined })}`,
    );
  }
  listCredentials(input: Record<string, unknown> = {}) {
    return this.request<{ credentials: unknown[]; next_cursor: string | null }>(
      `/api/credentials${query({ kind: input.kind as string | undefined, limit: input.limit?.toString(), cursor: input.cursor as string | undefined })}`,
    ).then((response) => ({
      items: response.credentials,
      next_cursor: response.next_cursor,
    }));
  }
  getWorkspace(ref: string) {
    return this.request<unknown>(`/api/workspaces/${encodeURIComponent(ref)}`);
  }
  destroyWorkspace(ref: string) {
    return this.request<unknown>(`/api/workspaces/${encodeURIComponent(ref)}`, {
      method: "DELETE",
    });
  }
  workspaceAction(
    ref: string,
    action: string,
    payload: Record<string, unknown> = {},
  ) {
    return this.request<unknown>(
      `/api/workspaces/${encodeURIComponent(ref)}/${action}`,
      json("POST", payload),
    );
  }
  executeWorkspace(payload: Record<string, unknown>) {
    const { workspace, ...body } = payload;
    return this.workspaceAction(String(workspace), "executions", body);
  }
  getWorkspaceExecution(ref: string, execution: string) {
    return this.request<unknown>(
      `/api/workspaces/${encodeURIComponent(ref)}/executions/${encodeURIComponent(execution)}`,
    );
  }
  workspaceExecutionAction(
    ref: string,
    execution: string,
    action: string,
    payload: Record<string, unknown> = {},
  ) {
    return this.request<unknown>(
      `/api/workspaces/${encodeURIComponent(ref)}/executions/${encodeURIComponent(execution)}/${action}`,
      json("POST", payload),
    );
  }
  getWorkspaceExecutionByRef(ref: string) {
    return this.request<unknown>(
      `/api/workspace-executions/${encodeURIComponent(ref)}`,
    );
  }
  sendWorkspaceExecutionInput(ref: string, data: string) {
    return this.request<Record<string, unknown>>(
      `/api/workspace-executions/${encodeURIComponent(ref)}/input`,
      json("POST", { data }),
    );
  }
  workspaceExecutionActionByRef(
    ref: string,
    action: string,
    payload: Record<string, unknown> = {},
  ) {
    return this.request<unknown>(
      `/api/workspace-executions/${encodeURIComponent(ref)}/${action}`,
      json("POST", payload),
    );
  }
}

function projectView(project: unknown): unknown {
  if (!project || typeof project !== "object") return project;
  const {
    id: _id,
    archived_at: _archivedAt,
    ...view
  } = project as Record<string, unknown>;
  return view;
}

function json(method: string, body: Record<string, unknown>): RequestInit {
  return { method, body: JSON.stringify(body) };
}
function query(values: Record<string, string | undefined>): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values))
    if (value !== undefined) params.set(key, value);
  const encoded = params.toString();
  return encoded ? `?${encoded}` : "";
}
