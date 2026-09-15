export type ApiErrorCode = "unauthorized" | "not_found" | "validation_failed" | "backend_unavailable";

export class ApiError extends Error {
  constructor(public readonly code: ApiErrorCode, public readonly status: number, message: string, public readonly details?: unknown) { super(message); this.name = "ApiError"; }
}

export class LaterBenderApi {
  constructor(private readonly baseUrl = process.env.LATER_BENDER_API_BASE_URL, private readonly token?: string, private readonly fetcher: typeof fetch = fetch) {
    if (!baseUrl) throw new Error("LATER_BENDER_API_BASE_URL is required");
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl!.replace(/\/$/, "")}${path}`;
    let response: Response;
    try { response = await this.fetcher(url, { ...init, headers: { Accept: "application/json", "Content-Type": "application/json", ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}), ...init.headers } }); }
    catch (error) { throw new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable"); }
    const body = await response.json().catch(() => undefined);
    if (!response.ok) {
      const error = body?.error;
      const code: ApiErrorCode = response.status === 401 ? "unauthorized" : response.status === 404 ? "not_found" : response.status === 422 ? "validation_failed" : "backend_unavailable";
      throw new ApiError(code, response.status, error?.message || (typeof error === "string" ? error : response.statusText), error?.details);
    }
    return body as T;
  }

  listProjects() { return this.request<unknown[]>("/api/projects").then((projects) => projects.map(projectView)); }
  getProject(slug: string) { return this.request<unknown>(`/api/projects/${encodeURIComponent(slug)}`).then(projectView); }
  createProject(payload: Record<string, unknown>) { return this.request<unknown>("/api/projects", json("POST", payload)).then(projectView); }
  updateProject(slug: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(slug)}`, json("PATCH", payload)).then(projectView); }
  listTasks(project: string, filters: Record<string, string | undefined>) { return this.request<unknown[]>(`/api/projects/${encodeURIComponent(project)}/tasks${query({ ...filters, summary: "true" })}`); }
  getTask(id: number) { return this.request<unknown>(`/api/tasks/${id}`); }
  createTask(project: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(project)}/tasks`, json("POST", payload)); }
  updateTask(id: number, payload: Record<string, unknown>) { return this.request<unknown>(`/api/tasks/${id}`, json("PATCH", payload)); }
  listNotes(input: { scope?: string; project?: string; tags?: string[]; limit?: number }) {
    const scope = input.scope || "global";
    const path = scope === "project" && input.project ? `/api/projects/${encodeURIComponent(input.project)}/notes` : "/api/notes";
    return this.request<unknown[]>(`${path}${query({ scope, tag: input.tags?.join(","), limit: input.limit?.toString(), summary: "true" })}`);
  }
  getNote(id: number) { return this.request<unknown>(`/api/notes/${id}`); }
  createNote(payload: Record<string, unknown>) {
    const project = typeof payload.project === "string" ? payload.project : undefined;
    const body = { ...payload }; delete body.project;
    const path = project ? `/api/projects/${encodeURIComponent(project)}/notes` : "/api/notes";
    return this.request<unknown>(path, json("POST", body));
  }
  updateNote(id: number, payload: Record<string, unknown>) { return this.request<unknown>(`/api/notes/${id}`, json("PATCH", payload)); }
  searchMemory(input: Record<string, unknown>) { return this.request<{ results: unknown[] }>(`/api/search${query({ q: String(input.query), scope: String(input.scope || "all"), project: input.project as string | undefined, kinds: (input.kinds as string[] | undefined)?.join(","), tags: (input.tags as string[] | undefined)?.join(","), task_statuses: (input.task_statuses as string[] | undefined)?.join(","), task_priorities: (input.task_priorities as string[] | undefined)?.join(","), limit: String(input.limit || 8) })}`); }
}

function projectView(project: unknown): unknown {
  if (!project || typeof project !== "object") return project;
  const { archived_at: _archivedAt, ...view } = project as Record<string, unknown>;
  return view;
}

function json(method: string, body: Record<string, unknown>): RequestInit { return { method, body: JSON.stringify(body) }; }
function query(values: Record<string, string | undefined>): string { const params = new URLSearchParams(); for (const [key, value] of Object.entries(values)) if (value !== undefined) params.set(key, value); const encoded = params.toString(); return encoded ? `?${encoded}` : ""; }
