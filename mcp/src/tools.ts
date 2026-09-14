import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ApiError, LaterBenderApi } from "./api.js";

const filters = { status: z.string().optional(), priority: z.string().optional(), tag: z.string().optional(), q: z.string().optional() };
const result = (data: unknown) => ({ content: [{ type: "text" as const, text: JSON.stringify(data) }], structuredContent: { data } });
const failure = (error: unknown) => {
  const e = error instanceof ApiError ? error : new ApiError("backend_unavailable", 503, error instanceof Error ? error.message : "Backend unavailable");
  const data = { error: { code: e.code, message: e.message, ...(e.details === undefined ? {} : { details: e.details }) }, http_status: e.status };
  return { ...result(data), isError: true };
};
const safe = (fn: () => Promise<unknown>) => fn().then(result).catch(failure);

export function registerTools(server: McpServer, api: LaterBenderApi): void {
  server.registerTool("list_projects", { description: "List projects visible to the authenticated Later, Bender user.", inputSchema: {} }, () => safe(() => api.listProjects()));
  server.registerTool("get_project", { description: "Get one project by slug.", inputSchema: { slug: z.string() } }, ({ slug }) => safe(() => api.getProject(slug)));
  server.registerTool("create_project", { description: "Create a project.", inputSchema: { name: z.string(), slug: z.string(), description: z.string().optional() } }, (input) => safe(() => api.createProject(input)));
  server.registerTool("list_tasks", { description: "List tasks in a project, with optional status, priority, tag, or text filters.", inputSchema: { project: z.string(), ...filters } }, ({ project, ...filter }) => safe(() => api.listTasks(project, filter)));
  server.registerTool("search_tasks", { description: "Search tasks across the authenticated user's projects.", inputSchema: filters }, (input) => safe(() => api.searchTasks(input)));
  server.registerTool("get_task", { description: "Get a task by project slug and numeric task id.", inputSchema: { project: z.string(), id: z.number().int().positive() } }, ({ project, id }) => safe(() => api.getTask(project, id)));
  server.registerTool("create_task", { description: "Create a task in a project; tags are passed to Later, Bender for normal create-on-use handling.", inputSchema: { project: z.string(), title: z.string(), status: z.string(), priority: z.string().optional(), context: z.string().optional(), intended_direction: z.string().optional(), tags: z.array(z.string()).optional() } }, ({ project, ...payload }) => safe(() => api.createTask(project, payload)));
  server.registerTool("update_task", { description: "Partially update a task in a project.", inputSchema: { project: z.string(), id: z.number().int().positive(), title: z.string().optional(), status: z.string().optional(), priority: z.string().optional(), context: z.string().optional(), intended_direction: z.string().optional(), tags: z.array(z.string()).optional() } }, ({ project, id, ...payload }) => safe(() => api.updateTask(project, id, payload)));
}
