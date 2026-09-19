#!/usr/bin/env python3
"""Small host-side Workspace runner.

The process is deliberately independent of Rails and Kubernetes.  It owns the
Docker calls and all transient workspace/output storage; Rails only receives
opaque handles and execution state through this HTTP API.
"""
import base64
import hashlib
import json
import mimetypes
import os
import platform
import secrets
import shlex
import signal
import sqlite3
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(os.environ.get("WORKSPACE_STORAGE", "/var/lib/later-bender/workspaces"))
DB = ROOT / "runner.sqlite3"
IMAGE = os.environ.get("WORKSPACE_IMAGE", "ubuntu:24.04")
TOKEN = os.environ.get("WORKSPACE_RUNNER_TOKEN", "")
HOST = os.environ.get("WORKSPACE_RUNNER_HOST", "127.0.0.1")
PORT = int(os.environ.get("WORKSPACE_RUNNER_PORT", "8787"))
NETWORK = os.environ.get("WORKSPACE_DOCKER_NETWORK", "none")
DEFAULT_TTL_SECONDS = int(os.environ.get("WORKSPACE_DEFAULT_TTL_SECONDS", "86400"))
REAPER_INTERVAL_SECONDS = int(os.environ.get("WORKSPACE_REAPER_INTERVAL_SECONDS", "60"))
MAX_CHUNK = 256 * 1024
lock = threading.RLock()


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def expiry(payload):
    requested = int(payload.get("ttl_seconds", DEFAULT_TTL_SECONDS))
    if requested < 1 or requested > 7 * 24 * 60 * 60:
        raise ValueError("invalid_expiry")
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + requested))


def docker(*args, check=True):
    return subprocess.run(["docker", *args], check=check, text=True, capture_output=True)


def db():
    connection = sqlite3.connect(DB)
    connection.row_factory = sqlite3.Row
    return connection


def setup():
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    with db() as connection:
        connection.executescript("""
          CREATE TABLE IF NOT EXISTS workspaces (
            handle TEXT PRIMARY KEY, label TEXT, state TEXT NOT NULL,
            environment TEXT NOT NULL, architecture TEXT NOT NULL,
            created_at TEXT NOT NULL, last_activity_at TEXT NOT NULL,
            expires_at TEXT, limits_json TEXT NOT NULL, capabilities_json TEXT NOT NULL,
            workspace_dir TEXT NOT NULL
          );
          CREATE TABLE IF NOT EXISTS executions (
            handle TEXT PRIMARY KEY, workspace_handle TEXT NOT NULL,
            sequence INTEGER NOT NULL, state TEXT NOT NULL, invocation_json TEXT NOT NULL,
            cwd TEXT NOT NULL, env_json TEXT NOT NULL, secret_env_names_json TEXT NOT NULL,
            started_at TEXT NOT NULL, finished_at TEXT, exit_code INTEGER,
            terminating_signal TEXT, timeout_seconds REAL, output_dir TEXT NOT NULL
          );
        """)


def reap_expired():
    with db() as connection:
        rows = connection.execute("SELECT handle FROM workspaces WHERE expires_at IS NOT NULL AND expires_at <= ?", (now(),)).fetchall()
    for row in rows:
        docker("rm", "-f", row["handle"], check=False)
        with db() as connection:
            connection.execute("DELETE FROM workspaces WHERE handle=?", (row["handle"],))


def reaper_loop():
    while True:
        try:
            reap_expired()
        except Exception:
            pass
        time.sleep(REAPER_INTERVAL_SECONDS)


def limits(payload):
    requested = payload.get("resources") or {}
    values = {"cpus": float(os.environ.get("WORKSPACE_DEFAULT_CPUS", "2")),
              "memory_bytes": int(os.environ.get("WORKSPACE_DEFAULT_MEMORY", str(2 * 1024**3))),
              "disk_bytes": int(os.environ.get("WORKSPACE_DEFAULT_DISK", str(10 * 1024**3))),
              "pids": int(os.environ.get("WORKSPACE_DEFAULT_PIDS", "256"))}
    checks = {"min_cpus": "cpus", "min_memory_bytes": "memory_bytes", "min_disk_bytes": "disk_bytes", "min_pids": "pids"}
    for source, target in checks.items():
        if source in requested and float(requested[source]) > values[target]:
            raise ValueError("workspace_quota_exceeded")
    return values


def workspace_json(row):
    return {"ref": row["handle"], "runner_handle": row["handle"], "label": row["label"], "state": row["state"],
            "environment": row["environment"], "architecture": row["architecture"],
            "os": {"name": "Linux", "version": platform.release()}, "shell": "/bin/bash",
            "workspace_root": "/workspace", "limits": json.loads(row["limits_json"]),
            "capabilities": json.loads(row["capabilities_json"]), "created_at": row["created_at"],
            "last_activity_at": row["last_activity_at"], "expires_at": row["expires_at"]}


def execution_state(row):
    marker = Path(row["output_dir"]) / "exit.json"
    if row["state"] == "running" and marker.exists():
        try:
            result = json.loads(marker.read_text())
            with db() as connection:
                connection.execute("UPDATE executions SET state=?, finished_at=?, exit_code=?, terminating_signal=? WHERE handle=?",
                                  (result.get("state", "exited"), now(), result.get("exit_code"), result.get("signal"), row["handle"]))
            row = db().execute("SELECT * FROM executions WHERE handle=?", (row["handle"],)).fetchone()
        except (OSError, ValueError, json.JSONDecodeError):
            pass
    return row


def stream(row, name, cursor, format_name):
    path = Path(row["output_dir"]) / name
    offset = int(cursor or 0)
    data = path.read_bytes() if path.exists() else b""
    chunk = data[offset:offset + MAX_CHUNK]
    next_offset = offset + len(chunk)
    terminal = execution_state(row)["state"] != "running"
    complete = terminal and next_offset >= len(data)
    output_format = "text" if format_name == "text" else "base64"
    if format_name in (None, "auto"):
        try:
            if b"\x00" in chunk:
                raise UnicodeDecodeError("utf-8", chunk, chunk.index(b"\x00"), chunk.index(b"\x00") + 1, "NUL is not text")
            chunk.decode("utf-8")
            output_format = "text"
        except UnicodeDecodeError:
            output_format = "base64"
    encoded = chunk.decode("utf-8") if output_format == "text" else base64.b64encode(chunk).decode("ascii")
    return {"execution": row["handle"], "stream": name, "format": output_format, "data": encoded,
            "chunk_byte_size": len(chunk), "total_byte_size": len(data), "next_cursor": None if complete else str(next_offset),
            "stream_complete": complete, "state": execution_state(row)["state"]}


def workspace_row(handle):
    with db() as connection:
        return connection.execute("SELECT * FROM workspaces WHERE handle=?", (handle,)).fetchone()


def safe_workspace_path(row, relative):
    root = (Path(row["workspace_dir"]) / "workspace").resolve()
    candidate = (root / str(relative).lstrip("/")).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        raise ValueError("path_invalid")
    return candidate


def media_type_for(filename, data):
    guessed, _ = mimetypes.guess_type(filename)
    try:
        data.decode("utf-8")
        return guessed or "text/plain"
    except UnicodeDecodeError:
        return guessed if guessed and not guessed.startswith("text/") else "application/octet-stream"


def execution_json(row):
    row = execution_state(row)
    output = {"format": "base64", "data": "", "total_byte_size": 0, "inline_complete": False}
    for name in ("stdout", "stderr"):
        path = Path(row["output_dir"]) / name
        output["total_byte_size"] = path.stat().st_size if path.exists() else 0
        output["inline_complete"] = row["state"] != "running"
        yield_name = name
        if name == "stdout": stdout = dict(output)
        else: stderr = dict(output)
    return {"ref": row["handle"], "workspace": row["workspace_handle"], "sequence": row["sequence"],
            "state": row["state"], "invocation": json.loads(row["invocation_json"]), "cwd": row["cwd"],
            "env": json.loads(row["env_json"]), "secret_env_names": json.loads(row["secret_env_names_json"]),
            "started_at": row["started_at"], "finished_at": row["finished_at"], "exit_code": row["exit_code"],
            "terminating_signal": row["terminating_signal"], "requested_timeout_seconds": row["timeout_seconds"],
            "stdout": stdout, "stderr": stderr, "stdout_handle": row["handle"] + ":stdout", "stderr_handle": row["handle"] + ":stderr"}


def start_execution(row, payload, container):
    out = Path(row["output_dir"])
    out.mkdir(mode=0o700, parents=True, exist_ok=True)
    command = payload.get("command")
    argv = payload.get("argv")
    if command is not None:
        invocation = ["/bin/bash", "-lc", command]
    else:
        invocation = argv
    env = payload.get("env") or {}
    secret_env = payload.get("secret_env") or {}
    env.update(secret_env)
    env_args = [item for key, value in env.items() for item in ("-e", f"{key}={value}")]
    quoted = " ".join(shlex.quote(item) for item in invocation)
    if payload.get("timeout_seconds"):
        quoted = f"timeout --foreground --signal=TERM --kill-after=2s {shlex.quote(str(payload['timeout_seconds']))} {quoted}"
    stdin = payload.get("stdin")
    if stdin is not None:
        (out / "stdin").write_bytes(str(stdin).encode())
    input_redirect = f" < /runner-output/{row['handle']}/stdin" if stdin is not None else ""
    wrapper = f"( {quoted}{input_redirect} > /runner-output/{row['handle']}/stdout 2> /runner-output/{row['handle']}/stderr; code=$?; state=exited; if [ $code -eq 124 ]; then state=timed_out; fi; printf '{{\"state\":\"%s\",\"exit_code\":%s}}' $state $code > /runner-output/{row['handle']}/exit.json )"
    args = ["exec", "-d", *env_args, "-w", payload.get("cwd", "/workspace"), container, "/bin/bash", "-lc", wrapper]
    docker(*args)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        return

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def send_json(self, status, value):
        raw = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if not self.authorized(): return
        path = [unquote(part) for part in urlparse(self.path).path.split("/") if part]
        try:
            if path == ["capabilities"]:
                default_limits = limits({})
                capabilities = {"internet": NETWORK != "none", "gpu": False, "nested_virtualization": False}
                offering = {"environment": "linux", "description": "General-purpose Linux engineering environment", "architectures": [{"architecture": platform.machine() or "arm64", "os": {"name": "Linux", "version": platform.release()}, "shell": "/bin/bash", "resources": {"default": default_limits, "max": default_limits}, "capabilities": capabilities}]}
                self.send_json(200, {"default_environment": "linux", "default_architecture": platform.machine() or "arm64", "environments": [offering], "capability_definitions": {"internet": "Outbound public internet access", "gpu": "GPU acceleration", "nested_virtualization": "Nested virtualization"}})
            elif len(path) == 2 and path[0] == "workspaces":
                with db() as connection: row = connection.execute("SELECT * FROM workspaces WHERE handle=?", (path[1],)).fetchone()
                if not row: self.send_json(404, {"error": {"code": "workspace_not_found", "message": "Workspace not found"}})
                else: self.send_json(200, workspace_json(row))
            elif len(path) == 2 and path[0] == "executions":
                with db() as connection: row = connection.execute("SELECT * FROM executions WHERE handle=?", (path[1],)).fetchone()
                if not row: self.send_json(404, {"error": {"code": "execution_not_found", "message": "Execution not found"}})
                else: self.send_json(200, execution_json(row))
            else: self.send_json(404, {"error": {"code": "not_found", "message": "Not found"}})
        except Exception as error:
            self.send_json(503, {"error": {"code": "workspace_unavailable", "message": str(error)}})

    def do_POST(self):
        if not self.authorized(): return
        path = [unquote(part) for part in urlparse(self.path).path.split("/") if part]
        payload = self.body()
        try:
            if path == ["workspaces"]:
                self.create_workspace(payload)
            elif len(path) == 3 and path[0] == "workspaces" and path[2] == "executions": self.create_execution(path[1], payload)
            elif len(path) == 3 and path[0] == "workspaces" and path[2] == "files": self.put_file(path[1], payload)
            elif len(path) == 3 and path[0] == "workspaces" and path[2] == "file-read": self.read_file(path[1], payload)
            elif len(path) == 3 and path[0] == "workspaces" and path[2] == "file-promote": self.promote_file(path[1], payload)
            elif len(path) == 3 and path[0] == "workspaces" and path[2] == "transcript-promote": raise ValueError("workspace_unavailable")
            elif len(path) == 3 and path[0] == "executions" and path[2] in ("output", "cancel"): self.execution_action(path[1], path[2], payload)
            else: self.send_json(404, {"error": {"code": "not_found", "message": "Not found"}})
        except ValueError as error:
            self.send_json(422, {"error": {"code": str(error), "message": str(error)}})
        except Exception as error:
            self.send_json(503, {"error": {"code": "workspace_unavailable", "message": str(error)}})

    def do_DELETE(self):
        if not self.authorized(): return
        path = [unquote(part) for part in urlparse(self.path).path.split("/") if part]
        if len(path) != 2 or path[0] != "workspaces": self.send_json(404, {"error": {"code": "not_found", "message": "Not found"}}); return
        with db() as connection: row = connection.execute("SELECT * FROM workspaces WHERE handle=?", (path[1],)).fetchone()
        if not row: self.send_json(404, {"error": {"code": "workspace_not_found", "message": "Workspace not found"}}); return
        docker("rm", "-f", path[1], check=False)
        with db() as connection: connection.execute("DELETE FROM workspaces WHERE handle=?", (path[1],))
        self.send_json(200, {"ref": path[1], "destroyed": True})

    def authorized(self):
        if TOKEN and self.headers.get("Authorization") != f"Bearer {TOKEN}": self.send_json(401, {"error": "Authentication required"}); return False
        return True

    def create_workspace(self, payload):
        handle = "WSR-" + secrets.token_hex(12)
        limits_value = limits(payload)
        requested_capabilities = set(payload.get("required_capabilities") or [])
        capabilities = {"internet": NETWORK != "none", "gpu": False, "nested_virtualization": False}
        unavailable = requested_capabilities - {name for name, enabled in capabilities.items() if enabled}
        if unavailable: raise ValueError("capability_unavailable")
        workspace_dir = ROOT / handle
        (workspace_dir / "workspace").mkdir(mode=0o700, parents=True)
        docker_args = ["run", "-d", "--name", handle, "--network", NETWORK, "--sysctl", "net.ipv6.conf.all.disable_ipv6=1", "--sysctl", "net.ipv6.conf.default.disable_ipv6=1", "--pids-limit", str(limits_value["pids"]), "--memory", str(limits_value["memory_bytes"]), "--cpus", str(limits_value["cpus"]), "-v", f"{workspace_dir / 'workspace'}:/workspace", "-v", f"{workspace_dir}:/runner-output", IMAGE, "sleep", "infinity"]
        docker(*docker_args)
        timestamp = now()
        values = (handle, payload.get("label"), "ready", payload.get("environment", "linux"), payload.get("architecture", "arm64"), timestamp, timestamp, expiry(payload), json.dumps(limits_value), json.dumps(capabilities), str(workspace_dir))
        with db() as connection: connection.execute("INSERT INTO workspaces VALUES (?,?,?,?,?,?,?,?,?,?,?)", values)
        with db() as connection: row = connection.execute("SELECT * FROM workspaces WHERE handle=?", (handle,)).fetchone()
        self.send_json(201, workspace_json(row))

    def create_execution(self, workspace, payload):
        with db() as connection: w = connection.execute("SELECT * FROM workspaces WHERE handle=?", (workspace,)).fetchone()
        if not w: raise ValueError("workspace_not_found")
        if w["state"] != "ready": raise ValueError("workspace_not_ready")
        if ("command" in payload) == ("argv" in payload): raise ValueError("invalid_invocation")
        handle = "WSE-" + secrets.token_hex(12)
        output = Path(w["workspace_dir"]) / handle
        with db() as connection:
            sequence = int(connection.execute("SELECT COALESCE(MAX(sequence), 0) + 1 FROM executions WHERE workspace_handle=?", (workspace,)).fetchone()[0])
        row = (handle, workspace, sequence, "running", json.dumps({"kind": "shell", "command": payload["command"]} if "command" in payload else {"kind": "argv", "argv": payload["argv"]}), payload.get("cwd", "/workspace"), json.dumps(payload.get("env", {})), json.dumps(sorted((payload.get("secret_env") or {}).keys())), now(), None, None, None, payload.get("timeout_seconds"), str(output))
        with db() as connection: connection.execute("INSERT INTO executions VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", row)
        start_execution({"handle": handle, "output_dir": str(output)}, payload, workspace)
        with db() as connection: result = connection.execute("SELECT * FROM executions WHERE handle=?", (handle,)).fetchone()
        self.send_json(201, execution_json(result))

    def put_file(self, workspace, payload):
        row = workspace_row(workspace)
        if not row: raise ValueError("workspace_not_found")
        target = safe_workspace_path(row, payload.get("path") or payload.get("filename") or "input")
        if target.exists() and not payload.get("overwrite", False): raise ValueError("path_exists")
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        data = base64.b64decode(payload.get("bytes_base64", ""), validate=True)
        target.write_bytes(data)
        self.send_json(200, {"workspace": workspace, "path": str(target.relative_to(Path(row["workspace_dir"]) / "workspace")), "byte_size": len(data), "sha256": hashlib.sha256(data).hexdigest()})

    def read_file(self, workspace, payload):
        row = workspace_row(workspace)
        if not row: raise ValueError("workspace_not_found")
        path = safe_workspace_path(row, payload.get("path", ""))
        if not path.exists(): raise ValueError("path_not_found")
        if not path.is_file(): raise ValueError("path_not_file")
        data = path.read_bytes()
        try:
            lines = data.decode("utf-8").splitlines(keepends=True)
        except UnicodeDecodeError as error:
            raise ValueError("not_text") from error
        start = int(payload.get("cursor", "0") or 0)
        if payload.get("locator"):
            start = max(0, int(payload["locator"].get("start", 1)) - 1)
            end = int(payload["locator"].get("end", len(lines)))
            if start < 0 or end < start + 1 or start >= len(lines) or end > len(lines): raise ValueError("invalid_range")
            selected = lines[start:end]
            next_cursor = None
        else:
            selected = lines[start:start + 200]
            next_cursor = str(start + len(selected)) if start + len(selected) < len(lines) else None
        content = "".join(selected)
        self.send_json(200, {"workspace": workspace, "path": str(path.relative_to(Path(row["workspace_dir"]) / "workspace")), "content": content, "media_type": "text/plain", "range": {"kind": "lines", "start": start + 1, "end": start + len(selected), "byte_start": len("".join(lines[:start]).encode()), "byte_end": len("".join(lines[:start + len(selected)]).encode()), "complete": next_cursor is None}, "next_cursor": next_cursor})

    def promote_file(self, workspace, payload):
        row = workspace_row(workspace)
        if not row: raise ValueError("workspace_not_found")
        path = safe_workspace_path(row, payload.get("path", ""))
        if not path.is_file(): raise ValueError("path_not_file")
        data = path.read_bytes()
        filename = payload.get("filename") or path.name
        self.send_json(200, {"filename": filename, "media_type": media_type_for(filename, data), "bytes_base64": base64.b64encode(data).decode(), "byte_size": len(data), "sha256": hashlib.sha256(data).hexdigest()})

    def execution_action(self, handle, action, payload):
        with db() as connection: row = connection.execute("SELECT * FROM executions WHERE handle=?", (handle,)).fetchone()
        if not row: raise ValueError("execution_not_found")
        if action == "output": self.send_json(200, stream(row, payload.get("stream", "stdout"), payload.get("cursor"), payload.get("format"))); return
        if execution_state(row)["state"] != "running": self.send_json(200, execution_json(row)); return
        docker("exec", row["workspace_handle"], "/bin/bash", "-lc", "kill -TERM -- -1", check=False)
        with db() as connection: connection.execute("UPDATE executions SET state=?, finished_at=? WHERE handle=?", ("cancelled", now(), handle))
        with db() as connection: row = connection.execute("SELECT * FROM executions WHERE handle=?", (handle,)).fetchone()
        self.send_json(200, execution_json(row))


if __name__ == "__main__":
    if not TOKEN:
        raise SystemExit("WORKSPACE_RUNNER_TOKEN is required")
    setup()
    threading.Thread(target=reaper_loop, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
