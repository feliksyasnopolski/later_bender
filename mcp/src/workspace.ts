import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { ApiError, LaterBenderApi } from "./api.js";

const timestamp = z.string();
const opaqueRef = z.string().min(1);
const cursor = z.string().nullable();
const workspaceState = z.enum(["starting", "ready", "stopping", "failed"]);
const executionState = z.enum([
  "running",
  "exited",
  "timed_out",
  "cancelled",
  "failed_to_start",
  "lost",
]);
const bytes = z.number().int().nonnegative();
const resourceRequirements = {
  min_cpus: z.number().positive().optional(),
  min_memory_bytes: bytes.optional(),
  min_disk_bytes: bytes.optional(),
  min_pids: z.number().int().positive().optional(),
};
const resourceLimits = z.object({
  cpus: z.number().positive().nullable(),
  memory_bytes: bytes.nullable(),
  disk_bytes: bytes.nullable(),
  pids: z.number().int().positive().nullable(),
});
const capabilityFlags = z.record(
  z.string(),
  z.union([z.boolean(), z.string()]),
);
const os = z.object({ name: z.string(), version: z.string() });
const failure = z
  .object({
    code: z.string().min(1),
    stage: z.string().min(1),
    message: z.string().max(500),
  })
  .nullable()
  .optional();
const architectureOffering = z.object({
  architecture: z.string(),
  os,
  shell: z.string(),
  resources: z.object({ default: resourceLimits, max: resourceLimits }),
  capabilities: capabilityFlags,
});
const environmentOffering = z.object({
  environment: z.string(),
  description: z.string(),
  architectures: z.array(architectureOffering),
});
const workspaceTarget = z.object({
  ref: opaqueRef,
  kind: z.string(),
  name: z.string(),
  availability: z.enum(["available", "unavailable"]),
  last_seen_at: timestamp.nullable(),
  platform: z.object({
    environment: z.string(),
    os,
    architectures: z.array(z.string()),
  }),
  supported_executors: z.array(z.enum(["native", "docker"])),
  resources: z
    .object({ default: resourceLimits, max: resourceLimits })
    .nullable(),
  capabilities: capabilityFlags,
});
const credentialBinding = z.object({
  ref: opaqueRef,
  name: z.string(),
  kind: z.enum(["env", "file"]),
  env_name: z.string().optional(),
  file_path: z.string().optional(),
  file_mode: z.number().int().optional(),
});

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
  credential_bindings: z.array(credentialBinding).default([]),
  created_at: timestamp,
  last_activity_at: timestamp,
  expires_at: timestamp.nullable(),
  target: z.string().optional(),
  executor: z.enum(["native", "docker"]).nullable().optional(),
  availability: z.string().optional(),
  failure,
});
const workspaceSummary = z.object({
  ref: opaqueRef,
  label: z.string().nullable(),
  state: workspaceState,
  environment: z.string(),
  architecture: z.string(),
  created_at: timestamp,
  last_activity_at: timestamp,
  expires_at: timestamp.nullable(),
  failure,
});
const canonicalFileAcknowledgement = z.object({
  ref: opaqueRef,
  filename: z.string(),
  media_type: z.string(),
  byte_size: bytes,
  sha256: z.string(),
});
const lineLocator = z.object({
  kind: z.literal("lines"),
  start: z.number().int().positive(),
  end: z.number().int().positive(),
});
const invocation = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("shell"), command: z.string() }),
  z.object({ kind: z.literal("argv"), argv: z.array(z.string()).min(1) }),
]);
const streamPreviewProjection = z.object({
  format: z.enum(["text", "base64"]),
  data: z.string(),
  total_byte_size: bytes,
  inline_complete: z.boolean(),
});
const streamProjection = streamPreviewProjection.extend({
  next_cursor: cursor,
});
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
  failure,
  stdout: streamProjection,
  stderr: streamProjection,
});
const transcriptInvocation = invocation;
const execCommonInput = {
  context_id: z.number().int().positive().optional(),
  workspace: opaqueRef.optional(),
  cwd: z.string().optional(),
  pty: z.boolean().optional(),
  interactive: z.boolean().optional(),
  env: z.record(z.string(), z.string()).optional(),
  secret_env: z.record(z.string(), z.string()).optional(),
  stdin: z.string().optional(),
  timeout_seconds: z.number().positive().optional(),
  wait_seconds: z.number().min(0).max(20).optional(),
};
const execInput = z
  .object({
    ...execCommonInput,
    command: z.string().optional(),
    argv: z.array(z.string()).min(1).optional(),
  })
  .strict()
  .superRefine((input, context) => {
    if (input.command === undefined && input.argv === undefined) {
      context.addIssue({
        code: "custom",
        message: "Exactly one of command or argv is required",
        path: ["command"],
      });
    }
    if (input.command !== undefined && input.argv !== undefined) {
      context.addIssue({
        code: "custom",
        message: "command and argv are mutually exclusive",
        path: ["argv"],
      });
    }
  })
  .meta({
    oneOf: [
      { required: ["command"], not: { required: ["argv"] } },
      { required: ["argv"], not: { required: ["command"] } },
    ],
  });
const readWorkspaceFileInput = z
  .object({
    workspace: opaqueRef,
    path: z.string(),
    locator: lineLocator.optional(),
    cursor: z.string().optional(),
  })
  .strict()
  .superRefine((input, context) => {
    if (input.locator !== undefined && input.cursor !== undefined) {
      context.addIssue({
        code: "custom",
        message: "locator and cursor are mutually exclusive",
        path: ["cursor"],
      });
    }
  });
const readWorkspaceTranscriptInput = z
  .object({
    workspace: opaqueRef,
    from_sequence: z.number().int().positive().optional(),
    to_sequence: z.number().int().positive().optional(),
    limit: z.number().int().positive().max(100).optional(),
    cursor: z.string().optional(),
  })
  .strict()
  .superRefine((input, context) => {
    if (
      input.cursor !== undefined &&
      (input.from_sequence !== undefined || input.to_sequence !== undefined)
    ) {
      context.addIssue({
        code: "custom",
        message: "cursor cannot be combined with sequence bounds",
        path: ["cursor"],
      });
    }
  });
const transcriptEvent = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("workspace_created"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
  }),
  z.object({
    kind: z.literal("workspace_prepared"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
  }),
  z.object({
    kind: z.literal("workspace_failed"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
    operation_id: opaqueRef,
    code: z.string().min(1),
    stage: z.string().min(1),
    message: z.string().max(500),
  }),
  z.object({
    kind: z.literal("file_imported"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
    file: opaqueRef,
    path: z.string(),
    byte_size: bytes,
    sha256: z.string(),
  }),
  z.object({
    kind: z.literal("execution"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
    execution: opaqueRef,
    invocation: transcriptInvocation,
    cwd: z.string(),
    secret_env_names: z.array(z.string()),
    started_at: timestamp,
    finished_at: timestamp.nullable(),
    requested_timeout_seconds: z.number().positive().nullable(),
    state: executionState,
    failure,
    exit_code: z.number().int().nullable(),
    terminating_signal: z.string().nullable(),
    stdout_preview: streamPreviewProjection,
    stderr_preview: streamPreviewProjection,
  }),
  z.object({
    kind: z.literal("file_promoted"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
    path: z.string(),
    file: opaqueRef,
  }),
  z.object({
    kind: z.literal("transcript_promoted"),
    sequence: z.number().int().positive(),
    occurred_at: timestamp,
    workspace: opaqueRef,
    file: opaqueRef,
  }),
]);
const transcriptOutput = z.object({
  workspace: opaqueRef,
  events: z.array(transcriptEvent),
  next_cursor: cursor,
});

const noRuntime = () =>
  Promise.resolve({
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({
          error: {
            code: "workspace_unavailable",
            message: "Workspace execution is not available yet",
          },
        }),
      },
    ],
    isError: true,
  });
const nestedResults: Record<string, string> = {
  create_workspace: "workspace",
  get_workspace: "workspace",
  exec_workspace: "execution",
  get_workspace_execution: "execution",
  cancel_workspace_execution: "execution",
};
const runtime = (api: LaterBenderApi | undefined, name: string) =>
  api
    ? async (input: any) => {
        const result = await workspaceOperation(api, name, input);
        if (
          result &&
          typeof result === "object" &&
          (result.isError || Array.isArray(result.content))
        )
          return result;
        const structuredContent = nestedResults[name]
          ? { [nestedResults[name]]: result }
          : result;
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(structuredContent) },
          ],
          structuredContent,
        };
      }
    : noRuntime;
const DEFAULT_EXECUTION_WAIT_SECONDS = 8;
const EXECUTION_POLL_INTERVAL_MS = 400;

async function waitForExecution(
  api: LaterBenderApi,
  initial: any,
  seconds: number,
) {
  if (!initial?.ref || initial.state !== "running" || seconds <= 0)
    return initial;
  const deadline = Date.now() + seconds * 1000;
  let latest = initial;
  while (latest.state === "running" && Date.now() < deadline) {
    await new Promise((resolve) =>
      setTimeout(
        resolve,
        Math.min(EXECUTION_POLL_INTERVAL_MS, deadline - Date.now()),
      ),
    );
    try {
      const fetched: any = await api.getWorkspaceExecutionByRef(initial.ref);
      latest = fetched?.execution || fetched || latest;
    } catch {
      // Execution has started: preserve its last known identity/state if observation fails.
      break;
    }
  }
  return latest;
}

async function workspaceOperation(
  api: LaterBenderApi,
  name: string,
  input: any,
): Promise<any> {
  try {
    switch (name) {
      case "get_workspace_capabilities":
        return api.getWorkspaceCapabilities();
      case "list_workspace_targets":
        return api.listWorkspaceTargets();
      case "create_workspace":
        return api.createWorkspace(input);
      case "list_workspaces":
        return api.listWorkspaces(input);
      case "get_workspace":
        return api.getWorkspace(input.ref);
      case "destroy_workspace":
        return api.destroyWorkspace(input.ref);
      case "put_file_in_workspace":
        return api.workspaceAction(input.workspace, "files", input);
      case "read_workspace_file":
        return api.workspaceAction(input.workspace, "file-read", input);
      case "promote_workspace_file":
        return api.workspaceAction(input.workspace, "file-promote", input);
      case "execution_current":
        return api.getWorkContext(input.context_id);
      case "execution_sessions": {
        let workspace = input.workspace as string | undefined;
        if (!workspace) {
          const current: any = await api.getWorkContext(input.context_id);
          if (!current?.context && input.context_id === undefined)
            throw new ApiError(
              "context_selection_required",
              409,
              "No work context is selected for this conversation; call work_context_start or work_context_select first.",
            );
          workspace = current?.context?.execution?.workspace;
        }
        if (!workspace)
          throw new ApiError(
            "validation_failed",
            422,
            "No execution environment selected",
          );
        const transcript: any = await api.workspaceAction(
          workspace,
          "transcript",
          {},
        );
        const latestByExecution = new Map<string, any>();
        for (const event of transcript?.events || []) {
          if (event.kind !== "execution" || !event.execution) continue;
          const previous = latestByExecution.get(event.execution);
          if (!previous || event.sequence > previous.sequence) {
            latestByExecution.set(event.execution, event);
          }
        }
        const sessions = [...latestByExecution.values()].sort(
          (left, right) => right.sequence - left.sequence,
        );
        return { workspace, sessions };
      }
      case "session_select": {
        const ref = input.ref as string;
        return api.selectForegroundExecution(ref, input.context_id);
      }
      case "execution_select": {
        // Resolve and validate the conversation's context before allocating a
        // Workspace, so missing/foreign context cannot leave an orphan behind.
        const current: any = await api.getWorkContext(input.context_id);
        if (!current?.context)
          throw new ApiError(
            "context_selection_required",
            409,
            "No work context is selected for this conversation; call work_context_start or work_context_select first.",
          );
        const contextId = input.context_id ?? Number(current.context.id);
        let workspace = input.workspace as string | undefined;
        if (!workspace) {
          if (!input.target)
            throw new ApiError(
              "validation_failed",
              422,
              "Provide workspace to reuse or target to acquire an execution environment",
            );
          const created = await api.createWorkspace({
            label: input.label,
            target: input.target,
            executor: input.executor,
            resource_path: input.resource_path,
            ttl_seconds: input.ttl_seconds,
          });
          workspace = String(
            (created as any).workspace?.ref || (created as any).ref,
          );
        }
        const requestedCwd = input.cwd || input.resource_path;
        if (requestedCwd) {
          const probeResult: any = await api.executeWorkspace({
            workspace,
            argv: ["test", "-d", requestedCwd],
            timeout_seconds: 10,
          });
          const probe = probeResult?.execution || probeResult;
          if (probe?.state !== "exited") {
            throw new ApiError(
              "backend_unavailable",
              503,
              `Could not validate working directory '${requestedCwd}'`,
            );
          }
          if (probe.exit_code !== 0) {
            throw new ApiError(
              "path_not_found",
              422,
              `Cannot select working directory '${requestedCwd}': the directory does not exist or is not accessible to the execution user`,
            );
          }
        }
        return api.selectExecutionContext({
          workspace,
          context_id: contextId,
          ...(requestedCwd ? { cwd: requestedCwd } : {}),
        });
      }
      case "exec_workspace": {
        const {
          wait_seconds: _waitSeconds,
          context_id: _contextId,
          ...executionInput
        } = input;
        const payload = { ...executionInput };
        let contextId = input.context_id as number | undefined;
        if (!payload.workspace || input.pty || input.interactive) {
          const current: any = await api.getWorkContext(contextId);
          if (!current?.context)
            throw new ApiError(
              "context_selection_required",
              409,
              "No work context is selected for this conversation; call work_context_start or work_context_select first.",
            );
          contextId ??= Number(current.context.id);
          if (!payload.workspace) {
            const selected = current.context.execution;
            if (!selected?.workspace)
              throw new ApiError(
                "validation_failed",
                422,
                "No execution environment selected; call execution_select first",
              );
            payload.workspace = selected.workspace;
            if (!payload.cwd) payload.cwd = selected.cwd;
          }
        }
        const result: any = await api.executeWorkspace(payload);
        let started = result?.execution || result;
        if (
          (input.pty || input.interactive) &&
          started?.ref &&
          started.state === "running"
        ) {
          if (!contextId)
            throw new ApiError(
              "context_selection_required",
              409,
              "A selected work context is required to track the foreground execution.",
            );
          await api.selectForegroundExecution(started.ref, contextId);
        } else if (started?.state === "running") {
          started = await waitForExecution(
            api,
            started,
            input.wait_seconds ?? DEFAULT_EXECUTION_WAIT_SECONDS,
          );
        }
        return result?.execution ? { ...result, execution: started } : started;
      }
      case "send_workspace_execution_input": {
        let ref = input.ref as string | undefined;
        if (!ref) {
          const current: any = await api.getWorkContext(input.context_id);
          if (!current?.context && input.context_id === undefined)
            throw new ApiError(
              "context_selection_required",
              409,
              "No work context is selected for this conversation; call work_context_start or work_context_select first.",
            );
          ref = current?.context?.execution?.foreground;
        }
        if (!ref)
          throw new ApiError(
            "validation_failed",
            422,
            "No foreground execution selected",
          );
        return api.sendWorkspaceExecutionInput(ref, input.data as string);
      }
      case "get_workspace_execution": {
        let ref = input.ref as string | undefined;
        if (!ref) {
          const current: any = await api.getWorkContext(input.context_id);
          if (!current?.context && input.context_id === undefined)
            throw new ApiError(
              "context_selection_required",
              409,
              "No work context is selected for this conversation; call work_context_start or work_context_select first.",
            );
          ref = current?.context?.execution?.foreground;
        }
        if (!ref)
          throw new ApiError(
            "validation_failed",
            422,
            "No execution ref or foreground execution selected",
          );
        return api.getWorkspaceExecutionByRef(ref);
      }
      case "read_workspace_execution_output": {
        let ref = input.ref as string | undefined;
        if (!ref) {
          const current: any = await api.getWorkContext(input.context_id);
          if (!current?.context && input.context_id === undefined)
            throw new ApiError(
              "context_selection_required",
              409,
              "No work context is selected for this conversation; call work_context_start or work_context_select first.",
            );
          ref = current?.context?.execution?.foreground;
        }
        if (!ref)
          throw new ApiError(
            "validation_failed",
            422,
            "No execution ref or foreground execution selected",
          );
        const { context_id: _contextId, ref: _ref, ...outputInput } = input;
        return api.workspaceExecutionActionByRef(ref, "output", {
          ...outputInput,
          format: input.format ?? "auto",
          wait_seconds: input.wait_seconds ?? 1,
        });
      }
      case "cancel_workspace_execution": {
        const ref = input.ref as string | undefined;
        if (!ref)
          throw new ApiError(
            "validation_failed",
            422,
            "An explicit execution ref is required for cancellation; implicit foreground cancellation is disabled.",
          );
        return api.workspaceExecutionActionByRef(ref, "cancel");
      }
      case "read_workspace_transcript": {
        const result = await api.workspaceAction(input.workspace, "transcript", input);
        const parsed = transcriptOutput.safeParse(result);
        if (!parsed.success)
          throw new ApiError(
            "backend_unavailable",
            502,
            "Backend returned a malformed Workspace transcript",
          );
        return parsed.data;
      }
      case "promote_workspace_transcript":
        return api.workspaceAction(
          input.workspace,
          "transcript-promote",
          input,
        );
      default:
        throw new ApiError(
          "backend_unavailable",
          500,
          "Unknown Workspace operation",
        );
    }
  } catch (error) {
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
  }
}
const readOnly = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: true,
  openWorldHint: false,
};
const create = {
  readOnlyHint: true,
  destructiveHint: false,
  idempotentHint: false,
  openWorldHint: false,
};
const destroy = {
  readOnlyHint: true,
  destructiveHint: true,
  idempotentHint: true,
  openWorldHint: false,
};
const execute = {
  readOnlyHint: true,
  destructiveHint: true,
  idempotentHint: false,
  openWorldHint: false,
};
const overwrite = {
  readOnlyHint: true,
  destructiveHint: true,
  idempotentHint: false,
  openWorldHint: false,
};
export const workspaceToolNames = [
  "get_workspace_capabilities",
  "list_workspace_targets",
  "create_workspace",
  "list_workspaces",
  "get_workspace",
  "destroy_workspace",
  "put_file_in_workspace",
  "read_workspace_file",
  "promote_workspace_file",
  "exec_workspace",
  "get_workspace_execution",
  "read_workspace_execution_output",
  "cancel_workspace_execution",
  "read_workspace_transcript",
  "promote_workspace_transcript",
  "execution_select",
  "execution_current",
  "send_workspace_execution_input",
  "execution_sessions",
  "session_select",
] as const;

export function registerWorkspaceTools(
  server: McpServer,
  api?: LaterBenderApi,
): void {
  server.registerTool(
    "get_workspace_capabilities",
    {
      description:
        "Discover the environments, architectures, operating system, shell, resource limits, and useful execution capabilities available for a Workspace. Capability maps include current keys such as internet, gpu, and nested_virtualization while allowing new capability names; capability_definitions explains every advertised capability for model use. Identifiers are open strings and no infrastructure implementation details are exposed. This read-only discovery call does not require a selected work context.",
      inputSchema: {},
      outputSchema: {
        default_environment: z.string(),
        default_architecture: z.string(),
        environments: z.array(environmentOffering),
        capability_definitions: z.record(z.string(), z.string()),
      },
      annotations: readOnly,
    },
    runtime(api, "get_workspace_capabilities"),
  );

  server.registerTool(
    "list_workspace_targets",
    {
      description:
        "List the logical execution targets available for Workspace placement. Results expose only compact effective runtime facts useful to the model; provider connection, session, journal, and container identities are omitted. This read-only discovery call does not require a selected work context.",
      inputSchema: {},
      outputSchema: { targets: z.array(workspaceTarget) },
      annotations: readOnly,
    },
    runtime(api, "list_workspace_targets"),
  );

  server.registerTool(
    "create_workspace",
    {
      description: `Create a transient Workspace using optional minimum resource requirements and capability requirements. Every required capability must resolve true for the selected offering; otherwise the request fails with capability_unavailable. An empty object requests the normal useful default; requirements are minimums, not exact operator configuration, and are never silently substituted. After creation, inspect workspace.state: proceed only when it is ready; if it is starting, use get_workspace to refresh its state before calling exec_workspace; if it is failed, report workspace.failure and stop rather than attempting execution. A successful create call does not itself mean the Workspace is ready. Target selection, executor support, or credential failures may return target_not_found, workspace_unavailable, executor_unsupported, credential_not_found, credential_conflict, or credential_injection_failed.`,
      inputSchema: {
        label: z.string().optional(),
        resource_path: z.string().optional(),
        target: z.string().optional(),
        executor: z.enum(["native", "docker"]).optional(),
        environment: z.string().optional(),
        architecture: z.string().optional(),
        ttl_seconds: z.number().int().positive().max(604800).optional(),
        resources: z.object(resourceRequirements).optional(),
        required_capabilities: z.array(z.string()).optional(),
        credentials: z
          .array(z.string().regex(/^CRED-/))
          .max(32)
          .optional(),
      },
      outputSchema: { workspace },
      annotations: create,
    },
    runtime(api, "create_workspace"),
  );
  server.registerTool(
    "list_workspaces",
    {
      description:
        "List the authenticated user's surviving transient Workspaces after a chat or connector refresh. Results are compact summaries and pagination uses an opaque cursor. This operation does not depend on the conversation's selected foreground execution.",
      inputSchema: {
        state: workspaceState.optional(),
        limit: z.number().int().positive().max(100).optional(),
        cursor: z.string().optional(),
      },
      outputSchema: {
        workspaces: z.array(workspaceSummary),
        next_cursor: cursor,
      },
      annotations: readOnly,
    },
    runtime(api, "list_workspaces"),
  );
  server.registerTool(
    "get_workspace",
    {
      description:
        "Fetch the full resolved projection of one Workspace by its opaque WS- reference. An unknown, expired, or inaccessible Workspace returns not_found.",
      inputSchema: { ref: opaqueRef },
      outputSchema: { workspace },
      annotations: readOnly,
    },
    runtime(api, "get_workspace"),
  );
  server.registerTool(
    "destroy_workspace",
    {
      description:
        "Destroy the entire transient Workspace, including its executions, filesystem, and transcript. The operation itself expresses destructive intent; there is no force option. An unknown or inaccessible Workspace returns not_found.",
      inputSchema: { ref: opaqueRef },
      outputSchema: {
        ref: opaqueRef,
        destroyed: z.boolean(),
        state: workspaceState.optional(),
      },
      annotations: destroy,
    },
    runtime(api, "destroy_workspace"),
  );

  server.registerTool(
    "put_file_in_workspace",
    {
      description:
        "Copy exact canonical Later Bender File bytes into a Workspace at a Workspace-relative path. If path is omitted, the canonical filename is used at /workspace root. Paths cannot escape /workspace and the import is recorded in the transcript. Unknown Workspace or File references return not_found; invalid or conflicting destination paths return path-specific errors.",
      inputSchema: {
        workspace: opaqueRef,
        file: opaqueRef,
        path: z.string().optional(),
        overwrite: z.boolean().default(false),
      },
      outputSchema: {
        workspace: opaqueRef,
        file: opaqueRef,
        path: z.string(),
        byte_size: bytes,
        sha256: z.string(),
      },
      annotations: overwrite,
    },
    runtime(api, "put_file_in_workspace"),
  );
  server.registerTool(
    "read_workspace_file",
    {
      description:
        "Read a bounded text-ish generated file using Workspace-relative paths and an optional line locator or continuation cursor. Locator and cursor are mutually exclusive. Without either, return an initial chunk and continuation metadata. This is not a generic binary transport; non-text content returns not_text. Missing paths return path_not_found or path_not_file; invalid ranges and cursors return invalid_range and invalid_cursor, respectively.",
      inputSchema: readWorkspaceFileInput,
      outputSchema: {
        workspace: opaqueRef,
        path: z.string(),
        content: z.string(),
        media_type: z.string(),
        range: z.object({
          kind: z.literal("lines"),
          start: z.number().int().positive(),
          end: z.number().int().positive(),
          byte_start: bytes,
          byte_end: bytes,
          complete: z.boolean(),
        }),
        next_cursor: cursor,
      },
      annotations: readOnly,
    },
    runtime(api, "read_workspace_file"),
  );
  server.registerTool(
    "promote_workspace_file",
    {
      description:
        "Promote one Workspace-relative artifact into a normal immutable canonical Later Bender File. Promotion is explicit and becomes a transcript event. Unknown Workspaces return not_found; missing artifacts or invalid promotion metadata return the corresponding path or validation error.",
      inputSchema: {
        workspace: opaqueRef,
        path: z.string(),
        project: z.string(),
        filename: z.string().optional(),
        tags: z.array(z.string()).optional(),
      },
      outputSchema: canonicalFileAcknowledgement.shape,
      annotations: create,
    },
    runtime(api, "promote_workspace_file"),
  );

  server.registerTool(
    "exec_workspace",
    {
      description: `Execute one command in a Workspace using exactly one invocation form: shell command run with /bin/bash -lc, or direct argv without shell interpretation. Workspace is a general-purpose execution surface for engineering work, including normal tooling, filesystem work, package installation, and outbound internet access when available. The selected Workspace target and environment are authoritative. Ordinary commands wait up to 8 seconds by default and return the latest state/output; set wait_seconds to 0 for immediate return or up to 20 seconds to wait longer. For a persistent terminal such as a Python REPL, use pty=true; use interactive=true for a persistent stdin pipe when a TTY is not needed. Persistent sessions become the foreground execution for this conversation. Continue interacting with that process using send_workspace_execution_input and read_workspace_execution_output without passing ref or context_id; the selected conversation context resolves the foreground process. Use session_select only when deliberately switching to another existing execution. Output previews automatically return readable UTF-8 text or base64 for binary data. secret_env values are injected but never recorded; only names are retained. A workspace that is not ready or a remote target that is offline returns workspace_not_ready or workspace_unavailable; an invalid command specification returns invalid_invocation. Starting a persistent process without a resolvable work context returns context_selection_required.`,
      inputSchema: execInput,
      outputSchema: { execution },
      annotations: execute,
    },
    runtime(api, "exec_workspace"),
  );
  server.registerTool(
    "get_workspace_execution",
    {
      description: `Fetch the current full projection of an execution by its opaque WSE- reference. Omit ref to inspect the foreground execution selected for this conversation; pass ref to inspect a specific execution regardless of foreground selection. Pass context_id only to override the conversation's selected work context. If ref is omitted, a selected work context is required and that context must have a foreground execution. Errors include context_selection_required when no context can be resolved, validation_failed when no foreground execution is selected, and not_found for an unknown execution ref.`,
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        ref: opaqueRef.optional(),
      },
      outputSchema: { execution },
      annotations: readOnly,
    },
    runtime(api, "get_workspace_execution"),
  );
  server.registerTool(
    "read_workspace_execution_output",
    {
      description: `Read the next chunk of retained stdout or stderr. For the normal interactive-session workflow, omit ref to read from the foreground execution selected for this conversation; omit context_id too unless you need an explicit context override. On the first read, omit cursor to start at byte 0; on every subsequent read, pass the previous response's next_cursor to avoid replaying output. Use format=auto (the default): valid UTF-8 text is returned as text and binary/non-text data as base64. Override with format=text only when you explicitly want text decoding, or format=base64 when you need byte-preserving output. Reads wait up to 1 second by default for a short output burst to settle; use wait_seconds=0 for immediate polling or up to 5 seconds for a longer wait. Each call returns a bounded chunk. A cursor at the end of a running stream is resumable; next_cursor becomes null only after terminal stream end is consumed. An omitted ref requires a selected work context with a foreground execution; errors include context_selection_required, validation_failed, not_found, invalid_range, and invalid_cursor for an invalid cursor position.`,
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        ref: opaqueRef.optional(),
        stream: z.enum(["stdout", "stderr"]),
        format: z.enum(["auto", "text", "base64"]).default("auto"),
        cursor: z.string().optional(),
        wait_seconds: z.number().min(0).max(5).optional(),
      },
      outputSchema: {
        execution: opaqueRef,
        stream: z.enum(["stdout", "stderr"]),
        format: z.enum(["text", "base64"]),
        data: z.string(),
        chunk_byte_size: bytes,
        next_cursor: cursor,
        stream_complete: z.boolean(),
        state: executionState,
      },
      annotations: readOnly,
    },
    runtime(api, "read_workspace_execution_output"),
  );
  server.registerTool(
    "cancel_workspace_execution",
    {
      description:
        "Cancel the execution identified by an explicit WSE- ref, terminating its whole process group. An explicit ref is required; this operation deliberately does not resolve or cancel the foreground execution implicitly. Cancellation is idempotent: an already-terminal execution returns its existing terminal projection. An unknown execution returns not_found.",
      inputSchema: { ref: opaqueRef },
      outputSchema: { execution },
      annotations: destroy,
    },
    runtime(api, "cancel_workspace_execution"),
  );

  server.registerTool(
    "read_workspace_transcript",
    {
      description:
        "Read the ordered transient Workspace activity ledger, including creation, File imports, executions, and promotions. Sequence numbers are monotonic per Workspace; use either sequence bounds or a continuation cursor, not both. The transcript also provides execution discovery after chat migration. An unknown Workspace returns not_found.",
      inputSchema: readWorkspaceTranscriptInput,
      outputSchema: {
        ...transcriptOutput.shape,
      },
      annotations: readOnly,
    },
    runtime(api, "read_workspace_transcript"),
  );
  server.registerTool(
    "promote_workspace_transcript",
    {
      description:
        "Promote a selected Workspace transcript range, or the transcript through the current point when no range is supplied, into a plain UTF-8 Markdown canonical Later Bender File. It includes complete retained stdout/stderr and never secret environment values. An unknown Workspace returns not_found; a missing or invalid project returns not_found or validation_failed.",
      inputSchema: {
        workspace: opaqueRef,
        project: z.string(),
        from_sequence: z.number().int().positive().optional(),
        to_sequence: z.number().int().positive().optional(),
        filename: z.string().optional(),
        tags: z.array(z.string()).optional(),
      },
      outputSchema: canonicalFileAcknowledgement.shape,
      annotations: create,
    },
    runtime(api, "promote_workspace_transcript"),
  );
  server.registerTool(
    "execution_select",
    {
      description:
        "Select the execution environment and working directory for this conversation's bound work context; ChatGPT resolves it from openai/session metadata. Pass context_id for an explicit override or when using a client without conversation metadata. Reuse an existing Workspace with workspace, or acquire one on target; resource_path selects an existing directory on a native Remote Agent without copying or owning that directory. Selection persists across calls. Native execution uses the agent OS user's real authority and is not a sandbox. Existing sessions remain bound to their original Workspace.",
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        workspace: opaqueRef.optional(),
        target: z.string().optional(),
        executor: z.enum(["native", "docker"]).optional(),
        label: z.string().optional(),
        resource_path: z.string().optional(),
        cwd: z.string().optional(),
        ttl_seconds: z.number().int().positive().max(604800).optional(),
      },
      outputSchema: { context: z.unknown(), workspace: z.unknown().optional() },
      annotations: create,
    },
    runtime(api, "execution_select"),
  );
  server.registerTool(
    "execution_current",
    {
      description:
        "Inspect this conversation's bound work context's execution Workspace, working directory, and foreground process. ChatGPT resolves it from openai/session metadata; pass context_id for an explicit override or when using a client without conversation metadata. A new conversation starts with no binding until work_context_start or work_context_select is called.",
      inputSchema: { context_id: z.number().int().positive().optional() },
      outputSchema: { context: z.unknown() },
      annotations: readOnly,
    },
    runtime(api, "execution_current"),
  );
  server.registerTool(
    "send_workspace_execution_input",
    {
      description:
        "Send UTF-8 input to a running persistent process; this sends bytes to the process and does not execute a shell command. For normal interactive-session use, omit ref and context_id: input goes to the foreground execution selected for this conversation. Pass ref only to target a specific execution deliberately, or context_id for an explicit context override/client without conversation metadata. Include a newline when the program should receive Enter. Use this after exec_workspace starts a persistent PTY or interactive pipe; maximum 64 KiB per call.",
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        ref: opaqueRef.optional(),
        data: z.string().max(65536),
      },
      outputSchema: {
        execution: opaqueRef,
        bytes_written: z.number().int().nonnegative(),
      },
      annotations: execute,
    },
    runtime(api, "send_workspace_execution_input"),
  );
  server.registerTool(
    "execution_sessions",
    {
      description:
        "List the executions recorded for the Workspace selected in the specified context so you can rediscover and switch between long-running processes after interruption. Optionally pass workspace to inspect another Workspace without changing the current selection.",
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        workspace: opaqueRef.optional(),
      },
      outputSchema: { workspace: opaqueRef, sessions: z.array(z.unknown()) },
      annotations: readOnly,
    },
    runtime(api, "execution_sessions"),
  );
  server.registerTool(
    "session_select",
    {
      description:
        "Make an existing execution the foreground process for subsequent input, status, output, and cancellation calls. ChatGPT resolves the selected context from openai/session metadata; pass context_id for an explicit override or when using a client without conversation metadata. The execution must belong to the currently selected Workspace; switching execution environments does not retarget an existing session.",
      inputSchema: {
        context_id: z.number().int().positive().optional(),
        ref: opaqueRef,
      },
      outputSchema: { context: z.unknown() },
      annotations: create,
    },
    runtime(api, "session_select"),
  );
}
