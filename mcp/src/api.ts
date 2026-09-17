export type ApiErrorCode = "unauthorized" | "not_found" | "validation_failed" | "backend_unavailable" | "source_required" | "source_conflict" | "unsupported_url_scheme" | "invalid_url" | "blocked_destination" | "redirect_blocked_destination" | "too_many_redirects" | "fetch_timeout" | "upstream_http_failure" | "file_too_large" | "empty_fetch";

export class ApiError extends Error {
  constructor(public readonly code: ApiErrorCode, public readonly status: number, message: string, public readonly details?: unknown) { super(message); this.name = "ApiError"; }
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
  constructor(
    private readonly baseUrl = process.env.LATER_BENDER_API_BASE_URL,
    private readonly token?: string,
    private readonly fetcher: typeof fetch = fetch,
    private readonly publicBaseUrl = process.env.LATER_BENDER_PUBLIC_API_BASE_URL || process.env.LATER_BENDER_OAUTH_ISSUER || baseUrl
  ) {
    if (!baseUrl) throw new Error("LATER_BENDER_API_BASE_URL is required");
    if (!publicBaseUrl) throw new Error("LATER_BENDER_PUBLIC_API_BASE_URL is required");
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl!.replace(/\/$/, "")}${path}`;
    let response: Response;
    try { response = await this.fetcher(url, { ...init, headers: { Accept: "application/json", "Content-Type": "application/json", ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}), ...init.headers } }); }
    catch (error) { throw new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable"); }
    const body = await response.json().catch(() => undefined);
    if (!response.ok) {
      const error = body?.error;
      const code: ApiErrorCode = response.status === 401 ? "unauthorized" : response.status === 404 ? "not_found" : response.status === 422 && typeof error?.code === "string" ? error.code : response.status === 422 ? "validation_failed" : "backend_unavailable";
      throw new ApiError(code, response.status, error?.message || (typeof error === "string" ? error : response.statusText), error?.details);
    }
    return body as T;
  }

  listProjects(input: { limit?: number; cursor?: string } = {}) { return this.request<{ projects: unknown[]; next_cursor: string | null }>(`/api/projects${query({ paginated: "true", limit: input.limit?.toString(), cursor: input.cursor })}`).then((response) => ({ items: response.projects.map(projectView), next_cursor: response.next_cursor })); }
  getProject(slug: string) { return this.request<unknown>(`/api/projects/${encodeURIComponent(slug)}`).then(projectView); }
  createProject(payload: Record<string, unknown>) { return this.request<unknown>("/api/projects", json("POST", payload)).then(projectView); }
  updateProject(slug: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(slug)}`, json("PATCH", payload)).then(projectView); }
  listTasks(project: string, filters: Record<string, string | undefined>) { return this.request<{ tasks: unknown[]; next_cursor: string | null }>(`/api/projects/${encodeURIComponent(project)}/tasks${query({ ...filters, paginated: "true", summary: "true" })}`).then((response) => ({ items: response.tasks, next_cursor: response.next_cursor })); }
  getTask(ref: string) { return this.request<unknown>(`/api/tasks/by-ref/${encodeURIComponent(ref)}`); }
  createTask(project: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(project)}/tasks`, json("POST", payload)); }
  updateTask(ref: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/tasks/by-ref/${encodeURIComponent(ref)}`, json("PATCH", payload)); }
  getTasks(refs: string[]) { return Promise.all(refs.map(async (ref) => { try { return { ref, task: await this.getTask(ref) }; } catch (error) { if (error instanceof ApiError && error.code === "not_found") return { ref, error: "not_found" }; throw error; } })); }
  listNotes(input: { scope?: string; project?: string; tags?: string[]; limit?: number; cursor?: string; sort?: string; order?: string }) {
    const scope = input.scope || "global";
    const path = scope === "project" && input.project ? `/api/projects/${encodeURIComponent(input.project)}/notes` : "/api/notes";
    return this.request<{ notes: unknown[]; next_cursor: string | null }>(`${path}${query({ scope, tag: input.tags?.join(","), limit: input.limit?.toString(), cursor: input.cursor, sort: input.sort, order: input.order, paginated: "true", summary: "true" })}`).then((response) => ({ items: response.notes, next_cursor: response.next_cursor }));
  }
  getNote(id: number) { return this.request<unknown>(`/api/notes/${id}`); }
  deleteNote(id: number) { return this.request<unknown>(`/api/notes/${id}`, { method: "DELETE" }); }
  createNote(payload: Record<string, unknown>) {
    const project = typeof payload.project === "string" ? payload.project : undefined;
    const body = { ...payload }; delete body.project;
    const path = project ? `/api/projects/${encodeURIComponent(project)}/notes` : "/api/notes";
    return this.request<unknown>(path, json("POST", body));
  }
  updateNote(id: number, payload: Record<string, unknown>) { return this.request<unknown>(`/api/notes/${id}`, json("PATCH", payload)); }
  editNote(id: number, payload: Record<string, unknown>) { return this.request<unknown>(`/api/notes/${id}/edit`, json("PATCH", payload)); }
  listFiles(project: string, filters: Record<string, string | undefined>) { return this.request<{ files: unknown[]; next_cursor: string | null }>(`/api/projects/${encodeURIComponent(project)}/files${query({ ...filters, paginated: "true" })}`).then((response) => ({ items: response.files, next_cursor: response.next_cursor })); }
  getFile(ref: string) { return this.request<unknown>(`/api/files/by-ref/${encodeURIComponent(ref)}`); }
  getFileEgress(ref: string) { return this.request<{ file: FileEgress }>(`/api/files/by-ref/${encodeURIComponent(ref)}/egress`).then((response) => response.file); }
  fileDownloadUrl(downloadPath: string) {
    if (!downloadPath.startsWith("/") || downloadPath.startsWith("//")) throw new ApiError("backend_unavailable", 502, "Backend returned an invalid file download path");
    return new URL(downloadPath, this.publicBaseUrl).href;
  }
  async downloadFile(ref: string): Promise<Uint8Array> {
    const url = `${this.baseUrl!.replace(/\/$/, "")}/api/files/by-ref/${encodeURIComponent(ref)}/download`;
    let response: Response;
    try { response = await this.fetcher(url, { headers: { Accept: "*/*", ...(this.token ? { Authorization: `Bearer ${this.token}` } : {}) } }); }
    catch (error) { throw new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable"); }
    if (!response.ok) throw new ApiError(response.status === 404 ? "not_found" : "backend_unavailable", response.status, response.statusText || "File download failed");
    return new Uint8Array(await response.arrayBuffer());
  }
  getFiles(refs: string[]) { return Promise.all(refs.map(async (ref) => { try { return { ref, file: await this.getFile(ref) }; } catch (error) { if (error instanceof ApiError && error.code === "not_found") return { ref, error: "not_found" }; throw error; } })); }
  createFile(project: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(project)}/files`, json("POST", payload)); }
  updateFile(ref: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/files/by-ref/${encodeURIComponent(ref)}`, json("PATCH", payload)); }
  deleteFile(ref: string) { return this.request<unknown>(`/api/files/by-ref/${encodeURIComponent(ref)}`, { method: "DELETE" }); }
  readFile(ref: string, representation = "auto", locator?: Record<string, unknown>) { return this.request<unknown>(`/api/files/by-ref/${encodeURIComponent(ref)}/read${query({ representation, locator: locator ? JSON.stringify(locator) : undefined })}`); }
  readFiles(reads: Array<Record<string, unknown>>) { return Promise.all(reads.map(async (read) => { const ref = String(read.ref); try { return { ref, read: await this.readFile(ref, String(read.representation || "auto"), read.locator as Record<string, unknown> | undefined) }; } catch (error) { if (error instanceof ApiError && error.code === "not_found") return { ref, error: "not_found" }; if (error instanceof ApiError && error.code === "validation_failed") return { ref, error: "invalid_locator" }; throw error; } })); }
  listArchive(ref: string, input: Record<string, unknown>) { return this.request<{ entries: unknown[]; next_cursor: string | null }>(`/api/files/by-ref/${encodeURIComponent(ref)}/archive${query({ path: input.path as string | undefined, depth: input.depth?.toString(), limit: input.limit?.toString(), cursor: input.cursor as string | undefined, paginated: "true" })}`).then((response) => ({ items: response.entries, next_cursor: response.next_cursor })); }
  readArchiveEntry(ref: string, path: string, representation = "auto", locator?: Record<string, unknown>) { return this.request<unknown>(`/api/files/by-ref/${encodeURIComponent(ref)}/archive/entry${query({ path, representation, locator: locator ? JSON.stringify(locator) : undefined })}`).then((response: any) => response.read); }
  extractArchiveEntry(ref: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/files/by-ref/${encodeURIComponent(ref)}/archive/extract`, json("POST", payload)); }
  searchMemory(input: Record<string, unknown>) { return this.request<{ results: unknown[] }>(`/api/search${query({ q: String(input.query), scope: String(input.scope || "all"), project: input.project as string | undefined, kinds: (input.kinds as string[] | undefined)?.join(","), tags: (input.tags as string[] | undefined)?.join(","), task_statuses: (input.task_statuses as string[] | undefined)?.join(","), task_priorities: (input.task_priorities as string[] | undefined)?.join(","), limit: String(input.limit || 8) })}`); }
}

function projectView(project: unknown): unknown {
  if (!project || typeof project !== "object") return project;
  const { id: _id, archived_at: _archivedAt, ...view } = project as Record<string, unknown>;
  return view;
}

function json(method: string, body: Record<string, unknown>): RequestInit { return { method, body: JSON.stringify(body) }; }
function query(values: Record<string, string | undefined>): string { const params = new URLSearchParams(); for (const [key, value] of Object.entries(values)) if (value !== undefined) params.set(key, value); const encoded = params.toString(); return encoded ? `?${encoded}` : ""; }
