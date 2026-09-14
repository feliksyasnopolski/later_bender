export type ApiErrorCode = "unauthorized" | "not_found" | "validation_failed" | "backend_unavailable";

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

export class LaterBenderApi {
  constructor(
    private readonly baseUrl = process.env.LATER_BENDER_API_BASE_URL,
    private readonly token = process.env.LATER_BENDER_API_TOKEN,
    private readonly fetcher: typeof fetch = fetch,
  ) {
    if (!baseUrl) throw new Error("LATER_BENDER_API_BASE_URL is required");
    if (!token) throw new Error("LATER_BENDER_API_TOKEN is required");
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = `${this.baseUrl!.replace(/\/$/, "")}${path}`;
    let response: Response;
    try {
      response = await this.fetcher(url, {
        ...init,
        headers: { Accept: "application/json", "Content-Type": "application/json", Authorization: `Bearer ${this.token}`, ...init.headers },
      });
    } catch (error) {
      throw new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable");
    }
    const body = await response.json().catch(() => undefined);
    if (!response.ok) {
      const error = body?.error;
      const code: ApiErrorCode = response.status === 401 ? "unauthorized" : response.status === 404 ? "not_found" : response.status === 422 ? "validation_failed" : "backend_unavailable";
      throw new ApiError(code, response.status, error?.message || (typeof error === "string" ? error : response.statusText), error?.details);
    }
    return body as T;
  }

  listProjects() { return this.request<unknown[]>("/api/projects"); }
  getProject(slug: string) { return this.request<unknown>(`/api/projects/${encodeURIComponent(slug)}`); }
  createProject(payload: Record<string, unknown>) { return this.request<unknown>("/api/projects", json("POST", payload)); }
  listTasks(project: string, filters: Record<string, string | undefined>) { return this.request<unknown[]>(`/api/projects/${encodeURIComponent(project)}/tasks${query(filters)}`); }
  searchTasks(filters: Record<string, string | undefined>) { return this.request<unknown[]>(`/api/tasks${query(filters)}`); }
  getTask(project: string, id: number) { return this.request<unknown>(`/api/projects/${encodeURIComponent(project)}/tasks/${id}`); }
  createTask(project: string, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(project)}/tasks`, json("POST", payload)); }
  updateTask(project: string, id: number, payload: Record<string, unknown>) { return this.request<unknown>(`/api/projects/${encodeURIComponent(project)}/tasks/${id}`, json("PATCH", payload)); }
}

function json(method: string, body: Record<string, unknown>): RequestInit { return { method, body: JSON.stringify(body) }; }
function query(values: Record<string, string | undefined>): string {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(values)) if (value !== undefined) params.set(key, value);
  const encoded = params.toString();
  return encoded ? `?${encoded}` : "";
}
