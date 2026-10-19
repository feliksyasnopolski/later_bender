import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(
  new URL("../libraries/lb.js", import.meta.url),
  "utf8",
);
const instantiate = (tools: Record<string, (args: any) => any>) =>
  new Function("tools", source)(tools);

test("standalone source evaluates as a Code Mode factory and exposes a compact manifest", () => {
  const lb = instantiate({});
  assert.equal(lb.manifest.name, "lb");
  assert.equal(typeof lb.execution.exec, "function");
  assert.equal(typeof lb.memory.search, "function");
  assert.equal(lb.manifest.version, "2");
  assert.equal(lb.manifest.factory, 'new Function("tools", source)(tools)');
  assert.equal(lb.manifest.methods["execution.exec"], "exec(command, options = {}) — command string, argv array, or exec options object.");
  assert.ok(lb.manifest.tools.includes("execution_current"));
  assert.ok(lb.manifest.tools.includes("get_workspace_execution"));
  assert.equal(Object.isFrozen(lb.execution), true);
});

test("normalizes structured, text, and direct tool results without retaining request state", async () => {
  const calls: any[] = [];
  const lb = instantiate({
    exec_workspace: async (args: any) => {
      calls.push(args);
      return {
        structuredContent: { execution: { ref: "WSE-x" } },
        content: [],
      };
    },
    search_memory: async (args: any) => {
      calls.push(args);
      return { content: [{ type: "text", text: '{"results":[]}' }] };
    },
    work_context_current: async () => ({ context: null }),
  });
  assert.deepEqual(
    await lb.execution.exec({ argv: ["pwd"], workspace: "WS-explicit" }),
    {
      execution: { ref: "WSE-x" },
    },
  );
  assert.deepEqual(await lb.memory.search({ query: "design" }), {
    results: [],
  });
  assert.deepEqual(await lb.context.current(), { context: null });
  await lb.execution.exec({ command: "true", workspace: "WS-arbitrary" });
  assert.deepEqual(calls[0], { argv: ["pwd"], workspace: "WS-explicit" });
  assert.deepEqual(calls[2], { command: "true", workspace: "WS-arbitrary" });
});

test("prefers Code Mode namespaced tools and exec composes current selection with command", async () => {
  const calls: Array<[string, any]> = [];
  const lb = instantiate({
    mcp__laterbender__execution_current: async (args: any) => {
      calls.push(["current", args]);
      return {
        structuredContent: {
          context: { execution: { workspace: "WS-current", cwd: "/project" } },
        },
      };
    },
    mcp__laterbender__exec_workspace: async (args: any) => {
      calls.push(["exec", args]);
      return { structuredContent: { execution: { ref: "WSE-current" } } };
    },
    exec_workspace: async () => ({
      structuredContent: { execution: { ref: "wrong-fallback" } },
    }),
  });
  const result = await lb.execution.exec("npm test", { wait_seconds: 0 });
  assert.deepEqual(result, { execution: { ref: "WSE-current" } });
  assert.deepEqual(calls, [
    ["current", {}],
    [
      "exec",
      {
        command: "npm test",
        wait_seconds: 0,
        workspace: "WS-current",
        cwd: "/project",
      },
    ],
  ]);
});

test("ergonomic exec can accept argv and fails clearly when no Workspace is selected", async () => {
  const calls: any[] = [];
  const lb = instantiate({
    mcp__laterbender__execution_current: async () => ({
      content: [
        {
          type: "text",
          text: JSON.stringify({
            context: { execution: { workspace: "WS-1" } },
          }),
        },
      ],
    }),
    mcp__laterbender__exec_workspace: async (args: any) => {
      calls.push(args);
      return { content: [{ type: "text", text: "done" }] };
    },
  });
  assert.equal(await lb.execution.exec(["pwd"]), "done");
  assert.deepEqual(calls, [{ argv: ["pwd"], workspace: "WS-1" }]);

  const unselected = instantiate({
    mcp__laterbender__execution_current: async () => ({
      structuredContent: { context: null },
    }),
  });
  await assert.rejects(
    unselected.execution.exec("pwd"),
    /No execution Workspace selected/,
  );
});

test("session helpers preserve cursors and explicit refs while forwarding context overrides", async () => {
  const calls: any[] = [];
  const tools = Object.fromEntries(
    [
      "execution_select",
      "execution_sessions",
      "session_select",
      "send_workspace_execution_input",
      "read_workspace_execution_output",
      "cancel_workspace_execution",
    ].map((name) => [
      name,
      async (args: any) => {
        calls.push([name, args]);
        return { content: [{ type: "text", text: "ok" }] };
      },
    ]),
  );
  const lb = instantiate(tools);
  await lb.execution.select({
    context_id: 9,
    target: "target-ref",
    executor: "native",
    cwd: "/work",
  });
  await lb.execution.sessions({ context_id: 9 });
  await lb.execution.selectSession("WSE-a", { context_id: 9 });
  await lb.execution.send("hello\n", { context_id: 9 });
  await lb.execution.output({ stream: "stdout", cursor: "128", context_id: 9 });
  await lb.execution.cancel("WSE-a");
  assert.deepEqual(
    calls.map((entry) => entry[1]),
    [
      { context_id: 9, target: "target-ref", executor: "native", cwd: "/work" },
      { context_id: 9 },
      { context_id: 9, ref: "WSE-a" },
      { context_id: 9, data: "hello\n" },
      { stream: "stdout", cursor: "128", context_id: 9 },
      { ref: "WSE-a" },
    ],
  );
});

test("surfaces MCP tool errors and missing tools with useful messages", async () => {
  const failed = instantiate({
    create_task: async () => ({
      isError: true,
      content: [{ type: "text", text: "validation_failed: title required" }],
    }),
  });
  await assert.rejects(
    failed.memory.createTask({ project: "p", title: "" }),
    /validation_failed: title required/,
  );
  await assert.rejects(
    failed.memory.search({ query: "x" }),
    /tool unavailable: search_memory/,
  );
  const errorObject = instantiate({
    get_note: async () => ({
      error: { code: "not_found", message: "Note missing" },
    }),
  });
  await assert.rejects(errorObject.memory.getNote(4), /Note missing/);
});
