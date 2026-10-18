// Standalone Code Mode factory body. Evaluate with new Function("tools", source)(tools).
return (() => {
  if (!tools || typeof tools !== "object")
    throw new TypeError("tools must be an object");

  const call = async (name, args = {}) => {
    const tool = tools[`mcp__laterbender__${name}`] || tools[name];
    if (typeof tool !== "function")
      throw new Error(`Later Bender tool unavailable: ${name}`);
    const result = await tool(args);
    if (result?.isError) {
      const detail = result.content
        ?.filter((part) => part?.type === "text")
        .map((part) => part.text)
        .join("\n");
      throw new Error(detail || `Later Bender tool failed: ${name}`);
    }
    if (
      result &&
      Object.prototype.hasOwnProperty.call(result, "structuredContent")
    )
      return result.structuredContent;
    const textPart = result?.content?.find((part) => part?.type === "text");
    if (textPart) {
      try {
        return JSON.parse(textPart.text);
      } catch {
        return textPart.text;
      }
    }
    if (result && typeof result === "object" && "error" in result) {
      const error = result.error;
      throw new Error(
        typeof error === "string"
          ? error
          : error?.message || JSON.stringify(error),
      );
    }
    return result;
  };

  const context = {
    current: () => call("work_context_current"),
    list: (args = {}) => call("work_context_list", args),
    get: (id) => call("work_context_get", { id }),
    start: (args = {}) => call("work_context_start", args),
    select: (id) => call("work_context_select", { id }),
    finish: (args = {}) => call("work_context_finish", args),
    attachTask: (task, args = {}) =>
      call("work_context_attach_task", { ...args, task }),
  };

  const execution = {
    capabilities: () => call("get_workspace_capabilities"),
    targets: () => call("list_workspace_targets"),
    current: (args = {}) => call("execution_current", args),
    select: (args) => call("execution_select", args),
    exec: async (command, options = {}) => {
      const invocation = Array.isArray(command)
        ? { argv: command }
        : typeof command === "string"
          ? { command }
          : command;
      if (!invocation || typeof invocation !== "object")
        throw new TypeError(
          "exec expects a command string, argv array, or execution options object",
        );

      let workspace = invocation.workspace;
      let cwd = invocation.cwd ?? options.cwd;
      if (!workspace) {
        const current = await call("execution_current", {
          ...(options.context_id === undefined
            ? {}
            : { context_id: options.context_id }),
        });
        const selected = current?.context?.execution;
        workspace = selected?.workspace;
        cwd ??= selected?.cwd;
        if (!workspace)
          throw new Error(
            "No execution Workspace selected; call lb.execution.select(...) first",
          );
      }
      return call("exec_workspace", {
        ...invocation,
        ...options,
        workspace,
        ...(cwd ? { cwd } : {}),
      });
    },
    sessions: (args = {}) => call("execution_sessions", args),
    selectSession: (ref, args = {}) => call("session_select", { ...args, ref }),
    send: (data, args = {}) =>
      call("send_workspace_execution_input", { ...args, data }),
    status: (args = {}) => call("get_workspace_execution", args),
    output: (args) => call("read_workspace_execution_output", args),
    cancel: (ref) => call("cancel_workspace_execution", { ref }),
  };

  const memory = {
    search: (args) => call("search_memory", args),
    getTask: (ref) => call("get_task", { ref }),
    getNote: (id) => call("get_note", { id }),
    getFile: (ref) => call("get_file", { ref }),
    listTasks: (args) => call("list_tasks", args),
    createTask: (args) => call("create_task", args),
    updateTask: (args) => call("update_task", args),
    listNotes: (args = {}) => call("list_notes", args),
    createNote: (args) => call("create_note", args),
    updateNote: (args) => call("update_note", args),
    editNote: (args) => call("edit_note", args),
    listProjects: (args = {}) => call("list_projects", args),
  };

  return Object.freeze({
    manifest: Object.freeze({
      name: "lb",
      version: "1",
      tools: Object.freeze([
        "execution_select",
        "exec_workspace",
        "work_context_current",
        "work_context_start",
        "search_memory",
        "create_task",
        "create_note",
      ]),
    }),
    call,
    context: Object.freeze(context),
    execution: Object.freeze(execution),
    memory: Object.freeze(memory),
  });
})();
