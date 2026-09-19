import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const timestamp = z.string();
const opaqueRef = z.string().min(1);
const cursor = z.string().nullable();
const workspaceState = z.enum(["starting", "ready", "stopping", "failed"]);
const executionState = z.enum(["running", "exited", "timed_out", "cancelled", "failed_to_start"]);
const bytes = z.number().int().nonnegative();
const resourceRequirements = {
  min_cpus: z.number().positive().optional(),
  min_memory_bytes: bytes.optional(),
  min_disk_bytes: bytes.optional()
};
const resourceLimits = z.object({ cpus: z.number().positive(), memory_bytes: bytes, disk_bytes: bytes, pids: z.number().int().positive() });
const capabilityFlags = z.record(z.string(), z.boolean());
const os = z.object({ name: z.string(), version: z.string() });
const architectureOffering = z.object({ architecture: z.string(), os, shell: z.string(), resources: z.object({ default: resourceLimits, max: resourceLimits }), capabilities: capabilityFlags });
const environmentOffering = z.object({ environment: z.string(), architectures: z.array(architectureOffering) });

const workspace = z.object({
  ref: opaqueRef,
  label: z.string().nullable(),
  state: workspaceState,
  environment: z.string(),
  architecture: z.string(),
  os,
  shell: z.string(),
  workspace_root: z.string(),
  limits: resourceLimits,
  capabilities: capabilityFlags,
  created_at: timestamp,
  last_activity_at: timestamp,
  expires_at: timestamp.nullable()
});
const workspaceSummary = z.object({
  ref: opaqueRef,
  label: z.string().nullable(),
  state: workspaceState,
  environment: z.string(),
  architecture: z.string(),
  created_at: timestamp,
  last_activity_at: timestamp,
  expires_at: timestamp.nullable()
});
const canonicalFileAcknowledgement = z.object({ ref: opaqueRef, filename: z.string(), media_type: z.string(), byte_size: bytes, sha256: z.string() });
const lineLocator = z.object({ kind: z.literal("lines"), start: z.number().int().positive(), end: z.number().int().positive() });
const invocation = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("shell"), command: z.string() }),
  z.object({ kind: z.literal("argv"), argv: z.array(z.string()).min(1) })
]);
const streamProjection = z.object({ format: z.enum(["text", "base64"]), data: z.string(), total_byte_size: bytes, inline_complete: z.boolean() });
const execution = z.object({
  ref: opaqueRef,
  workspace: opaqueRef,
  sequence: z.number().int().positive(),
  state: executionState,
  invocation,
  cwd: z.string(),
  env: z.record(z.string(), z.string()),
  secret_env_names: z.array(z.string()),
  started_at: timestamp,
  finished_at: timestamp.nullable(),
  exit_code: z.number().int().nullable(),
  terminating_signal: z.string().nullable(),
  requested_timeout_seconds: z.number().positive().nullable(),
  stdout: streamProjection,
  stderr: streamProjection
});
const transcriptInvocation = invocation;
const execCommonInput = {
  workspace: opaqueRef,
  cwd: z.string().optional(),
  env: z.record(z.string(), z.string()).optional(),
  secret_env: z.record(z.string(), z.string()).optional(),
  stdin: z.string().optional(),
  timeout_seconds: z.number().positive().optional()
};
const execInput = z.union([
  z.object({ ...execCommonInput, command: z.string() }).strict(),
  z.object({ ...execCommonInput, argv: z.array(z.string()).min(1) }).strict()
]);
const readWorkspaceFileInput = z.union([
  z.object({ workspace: opaqueRef, path: z.string() }).strict(),
  z.object({ workspace: opaqueRef, path: z.string(), locator: lineLocator }).strict(),
  z.object({ workspace: opaqueRef, path: z.string(), cursor: z.string() }).strict()
]);
const readWorkspaceTranscriptInput = z.union([
  z.object({ workspace: opaqueRef, from_sequence: z.number().int().positive().optional(), to_sequence: z.number().int().positive().optional(), limit: z.number().int().positive().max(100).optional() }).strict(),
  z.object({ workspace: opaqueRef, limit: z.number().int().positive().max(100).optional(), cursor: z.string() }).strict()
]);
const transcriptEvent = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("workspace_created"), sequence: z.number().int().positive(), occurred_at: timestamp, workspace: opaqueRef }),
  z.object({ kind: z.literal("file_imported"), sequence: z.number().int().positive(), occurred_at: timestamp, workspace: opaqueRef, file: opaqueRef, path: z.string(), byte_size: bytes, sha256: z.string() }),
  z.object({
    kind: z.literal("execution"), sequence: z.number().int().positive(), occurred_at: timestamp, workspace: opaqueRef, execution: opaqueRef,
    invocation: transcriptInvocation, cwd: z.string(), secret_env_names: z.array(z.string()), started_at: timestamp, finished_at: timestamp.nullable(),
    requested_timeout_seconds: z.number().positive().nullable(), state: executionState, exit_code: z.number().int().nullable(), terminating_signal: z.string().nullable(), stdout_preview: streamProjection, stderr_preview: streamProjection
  }),
  z.object({ kind: z.literal("file_promoted"), sequence: z.number().int().positive(), occurred_at: timestamp, workspace: opaqueRef, path: z.string(), file: opaqueRef }),
  z.object({ kind: z.literal("transcript_promoted"), sequence: z.number().int().positive(), occurred_at: timestamp, workspace: opaqueRef, file: opaqueRef })
]);

const noRuntime = () => Promise.resolve({
  content: [{ type: "text" as const, text: JSON.stringify({ error: { code: "workspace_unavailable", message: "Workspace execution is not available yet" } }) }],
  isError: true
});
const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const create = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
const destroy = { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false };
const execute = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: true };
const overwrite = { readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false };
const workspaceFailure = "Expected failures use stable error codes, including workspace_not_found, workspace_not_ready, workspace_unavailable, capability_unavailable, workspace_quota_exceeded, file_not_found, path_invalid, path_not_found, path_exists, path_not_file, not_text, execution_not_found, execution_not_running, invalid_range, invalid_cursor, and invalid_invocation.";

export const workspaceToolNames = [
  "get_workspace_capabilities", "create_workspace", "list_workspaces", "get_workspace", "destroy_workspace",
  "put_file_in_workspace", "read_workspace_file", "promote_workspace_file", "exec_workspace", "get_workspace_execution",
  "read_workspace_execution_output", "cancel_workspace_execution", "read_workspace_transcript", "promote_workspace_transcript"
] as const;

export function registerWorkspaceTools(server: McpServer): void {
  server.registerTool("get_workspace_capabilities", { description: `Discover the environments, architectures, operating system, shell, resource limits, and useful execution capabilities available for a Workspace. Capability maps include current keys such as internet, gpu, and nested_virtualization while allowing new capability names. Identifiers are open strings and no infrastructure implementation details are exposed. ${workspaceFailure}`, inputSchema: {}, outputSchema: {
    default_environment: z.string(), default_architecture: z.string(), environments: z.array(environmentOffering)
  }, annotations: readOnly }, noRuntime);

  server.registerTool("create_workspace", { description: `Create a transient Workspace using optional minimum resource requirements and capability requirements. Every required capability must resolve true for the selected offering; otherwise return capability_unavailable. An empty object requests the normal useful default; requirements are minimums, not exact operator configuration, and are never silently substituted. ${workspaceFailure}`, inputSchema: { label: z.string().optional(), environment: z.string().optional(), architecture: z.string().optional(), resources: z.object(resourceRequirements).optional(), required_capabilities: z.array(z.string()).optional() }, outputSchema: { workspace }, annotations: create }, noRuntime);
  server.registerTool("list_workspaces", { description: `List the authenticated user's surviving transient Workspaces after a chat or connector refresh. Results are compact summaries and pagination uses an opaque cursor. ${workspaceFailure}`, inputSchema: { state: workspaceState.optional(), limit: z.number().int().positive().max(100).optional(), cursor: z.string().optional() }, outputSchema: { workspaces: z.array(workspaceSummary), next_cursor: cursor }, annotations: readOnly }, noRuntime);
  server.registerTool("get_workspace", { description: `Fetch the full resolved projection of one Workspace by its opaque WS- reference. Destroyed or expired Workspaces resolve as not found. ${workspaceFailure}`, inputSchema: { ref: opaqueRef }, outputSchema: { workspace }, annotations: readOnly }, noRuntime);
  server.registerTool("destroy_workspace", { description: `Destroy the entire transient Workspace, including its executions, filesystem, and transcript. The operation itself expresses destructive intent; there is no force option. ${workspaceFailure}`, inputSchema: { ref: opaqueRef }, outputSchema: { ref: opaqueRef, destroyed: z.literal(true) }, annotations: destroy }, noRuntime);

  server.registerTool("put_file_in_workspace", { description: `Copy exact canonical Later Bender File bytes into a Workspace at a Workspace-relative path. If path is omitted, the canonical filename is used at /workspace root. Paths cannot escape /workspace and the import is recorded in the transcript. ${workspaceFailure}`, inputSchema: { workspace: opaqueRef, file: opaqueRef, path: z.string().optional(), overwrite: z.boolean().default(false) }, outputSchema: { workspace: opaqueRef, file: opaqueRef, path: z.string(), byte_size: bytes, sha256: z.string() }, annotations: overwrite }, noRuntime);
  server.registerTool("read_workspace_file", { description: `Read a bounded text-ish generated file using Workspace-relative paths and an optional line locator or continuation cursor. Locator and cursor are mutually exclusive. Without either, return an initial chunk and continuation metadata. This is not a generic binary transport; non-text content returns not_text. ${workspaceFailure}`, inputSchema: readWorkspaceFileInput, outputSchema: { workspace: opaqueRef, path: z.string(), content: z.string(), media_type: z.string(), range: z.object({ kind: z.literal("lines"), start: z.number().int().positive(), end: z.number().int().positive(), byte_start: bytes, byte_end: bytes, complete: z.boolean() }), next_cursor: cursor }, annotations: readOnly }, noRuntime);
  server.registerTool("promote_workspace_file", { description: `Promote one Workspace-relative artifact into a normal immutable canonical Later Bender File. Promotion is explicit and becomes a transcript event. ${workspaceFailure}`, inputSchema: { workspace: opaqueRef, path: z.string(), project: z.string(), filename: z.string().optional(), tags: z.array(z.string()).optional() }, outputSchema: canonicalFileAcknowledgement.shape, annotations: create }, noRuntime);

  server.registerTool("exec_workspace", { description: `Execute one command in a Workspace using exactly one invocation form: shell command run with /bin/bash -lc, or direct argv without shell interpretation. The server waits briefly and returns a terminal projection or a running execution ref. There is no persistent shell session. secret_env values are injected but never recorded; only names are retained. ${workspaceFailure}`, inputSchema: execInput, outputSchema: { execution }, annotations: execute }, noRuntime);
  server.registerTool("get_workspace_execution", { description: `Fetch the current full projection of an execution by its opaque WSE- reference. The execution ref is unambiguous, and authorization remains authenticated-user scoped. ${workspaceFailure}`, inputSchema: { ref: opaqueRef }, outputSchema: { execution }, annotations: readOnly }, noRuntime);
  server.registerTool("read_workspace_execution_output", { description: `Continue reading retained stdout or stderr from an opaque cursor. Each call returns the next bounded stream chunk; a cursor at the current end of a running stream is resumable and returns later appended bytes. next_cursor becomes null only after terminal stream end is consumed. ${workspaceFailure}`, inputSchema: { ref: opaqueRef, stream: z.enum(["stdout", "stderr"]), format: z.enum(["auto", "text", "base64"]).optional(), cursor: z.string().optional() }, outputSchema: { execution: opaqueRef, stream: z.enum(["stdout", "stderr"]), format: z.enum(["text", "base64"]), data: z.string(), chunk_byte_size: bytes, next_cursor: cursor, stream_complete: z.boolean(), state: executionState }, annotations: readOnly }, noRuntime);
  server.registerTool("cancel_workspace_execution", { description: `Terminate the whole process group belonging to an execution. Cancellation is idempotent: an already-terminal execution returns its existing terminal projection. ${workspaceFailure}`, inputSchema: { ref: opaqueRef }, outputSchema: { execution }, annotations: destroy }, noRuntime);

  server.registerTool("read_workspace_transcript", { description: `Read the ordered transient Workspace activity ledger, including creation, File imports, executions, and promotions. Sequence numbers are monotonic per Workspace; use either sequence bounds or a continuation cursor, not both. The transcript also provides execution discovery after chat migration. ${workspaceFailure}`, inputSchema: readWorkspaceTranscriptInput, outputSchema: { workspace: opaqueRef, events: z.array(transcriptEvent), next_cursor: cursor }, annotations: readOnly }, noRuntime);
  server.registerTool("promote_workspace_transcript", { description: `Promote a selected Workspace transcript range, or the transcript through the current point when no range is supplied, into a plain UTF-8 Markdown canonical Later Bender File. It includes complete retained stdout/stderr and never secret environment values. ${workspaceFailure}`, inputSchema: { workspace: opaqueRef, project: z.string(), from_sequence: z.number().int().positive().optional(), to_sequence: z.number().int().positive().optional(), filename: z.string().optional(), tags: z.array(z.string()).optional() }, outputSchema: canonicalFileAcknowledgement.shape, annotations: create }, noRuntime);
}
