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
      version: "2",
      factory: 'new Function("tools", source)(tools)',
      description: "Convenience helpers for Later Bender work contexts, Workspace execution, and durable memory. All calls resolve Code Mode namespaced tools first, then unnamespaced tools.",
      argument_conventions: Object.freeze({
        "object methods": "Pass the native MCP argument object unchanged.",
        "id/ref helpers": "Convenience positional forms are retained; use the documented object form when options are needed.",
        "execution.exec": "Accepts a command string, argv array, or options object; options may be supplied as a second argument.",
        "execution.send": "Accepts data then optional options; data is always sent as the data field.",
      }),
      methods: Object.freeze({
        call: "call(name, args = {}) — call one Later Bender tool and unwrap its result.",
        "context.current": "current()",
        "context.list": "list(args = {})",
        "context.get": "get(id) — id is a numeric context id.",
        "context.start": "start(args = {})",
        "context.select": "select(id) — id is a numeric context id.",
        "context.finish": "finish(args = {})",
        "context.attachTask": "attachTask(task, args = {}) — task is a Task ref.",
        "execution.capabilities": "capabilities()",
        "execution.targets": "targets()",
        "execution.current": "current(args = {})",
        "execution.select": "select(args) — native execution_select arguments.",
        "execution.exec": "exec(command, options = {}) — command string, argv array, or exec options object.",
        "execution.sessions": "sessions(args = {})",
        "execution.selectSession": "selectSession(ref, args = {})",
        "execution.send": "send(data, args = {})",
        "execution.status": "status(args = {})",
        "execution.output": "output(args)",
        "execution.cancel": "cancel(ref)",
        "memory.search": "search(args)",
        "memory.getTask": "getTask(ref)",
        "memory.getNote": "getNote(id)",
        "memory.getFile": "getFile(ref)",
        "memory.listTasks": "listTasks(args)",
        "memory.createTask": "createTask(args)",
        "memory.updateTask": "updateTask(args)",
        "memory.listNotes": "listNotes(args = {})",
        "memory.createNote": "createNote(args)",
        "memory.updateNote": "updateNote(args)",
        "memory.editNote": "editNote(args)",
        "memory.listProjects": "listProjects(args = {})",
      }),
      tools: Object.freeze([
        "work_context_current", "work_context_list", "work_context_get",
        "work_context_start", "work_context_select", "work_context_finish",
        "work_context_attach_task", "get_workspace_capabilities", "list_workspace_targets",
        "execution_current", "execution_select", "exec_workspace", "execution_sessions",
        "session_select", "send_workspace_execution_input", "get_workspace_execution",
        "read_workspace_execution_output", "cancel_workspace_execution", "search_memory",
        "get_task", "get_note", "get_file", "list_tasks", "create_task", "update_task",
        "list_notes", "create_note", "update_note", "edit_note", "list_projects",
      ]),
    }),
    call,
    context: Object.freeze(context),
    execution: Object.freeze(execution),
    memory: Object.freeze(memory),
  });
})();
