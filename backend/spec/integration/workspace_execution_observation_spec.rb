require "rails_helper"

RSpec.describe "Workspace execution observation", type: :request do
  before do
    @user = User.create!(username: "workspace-observer", password: "password123")
    _token, @raw_token = ApiToken.issue!(user: @user, name: "workspace test")
    @runner_workspace = {
      "ref" => "WSR-test", "runner_handle" => "WSR-test", "state" => "ready", "environment" => "linux",
      "architecture" => "arm64", "os" => { "name" => "Linux", "version" => "test" }, "shell" => "/bin/bash",
      "workspace_root" => "/workspace", "limits" => { "cpus" => 2, "memory_bytes" => 1024, "disk_bytes" => 2048, "pids" => 32 },
      "capabilities" => { "internet" => true }, "created_at" => "2026-01-01T00:00:00Z", "last_activity_at" => "2026-01-01T00:00:00Z", "expires_at" => "2026-01-02T00:00:00Z"
    }
  end

  def stub_runner(terminal_state: "exited")
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request) do |_, method, path, _payload = nil|
      case [ method, path ]
      when [ :post, "/workspaces" ] then @runner_workspace
      when [ :post, "/workspaces/WSR-test/executions" ] then execution_result(state: "running")
      when [ :get, "/executions/WSE-test" ] then execution_result(state: terminal_state)
      when [ :post, "/executions/WSE-test/output" ] then { "format" => "text", "data" => path ? "out" : "", "chunk_byte_size" => 3, "total_byte_size" => 3, "stream_complete" => true }
      else raise "unexpected runner request #{method} #{path}"
      end
    end
  end

  def execution_result(state:)
    { "ref" => "WSE-test", "workspace" => "WSR-test", "sequence" => 1, "state" => state,
      "invocation" => { "kind" => "shell", "command" => "test" }, "cwd" => "/workspace", "env" => {}, "secret_env_names" => [],
      "started_at" => "2026-01-01T00:00:00Z", "finished_at" => state == "running" ? nil : "2026-01-01T00:00:01Z",
      "exit_code" => state == "exited" ? 0 : nil, "terminating_signal" => nil, "requested_timeout_seconds" => state == "timed_out" ? 1 : nil,
      "stdout_handle" => "stdout", "stderr_handle" => "stderr" }
  end

  it "returns a short terminal command with inline streams" do
    stub_runner
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    post "/api/workspaces/#{Workspace.last.ref}/executions", params: { command: "test" }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    assert_equal "exited", json_body.fetch("state")
    assert_equal "out", json_body.dig("stdout", "data")
    assert_equal Workspace.last.ref, json_body.fetch("workspace")
    assert_match(/\AWS-\d+\z/, Workspace.last.ref)
  end

  it "allocates compact public refs per user while keeping runner handles internal" do
    stub_runner
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    first = json_body.fetch("ref")
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    second = json_body.fetch("ref")
    assert_equal "WS-1", first
    assert_equal "WS-2", second
    assert_not_includes [ first, second ], "WSR-test"

    other = User.create!(username: "workspace-observer-other", password: "password123")
    _other_token, raw_other_token = ApiToken.issue!(user: other, name: "workspace test")
    post "/api/workspaces", params: {}.to_json, headers: json_headers(raw_other_token)
    assert_equal "WS-1", json_body.fetch("ref")
  end

  it "returns timeout directly when it occurs inside the observation window" do
    stub_runner(terminal_state: "timed_out")
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    post "/api/workspaces/#{Workspace.last.ref}/executions", params: { command: "test" }.to_json, headers: json_headers(@raw_token)
    assert_equal "timed_out", json_body.fetch("state")
  end

  it "returns running after the bounded window for a live execution" do
    stub_runner(terminal_state: "running")
    stub_const("Api::WorkspacesController::EXECUTION_OBSERVATION_WINDOW_SECONDS", 0.01)
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    post "/api/workspaces/#{Workspace.last.ref}/executions", params: { command: "test" }.to_json, headers: json_headers(@raw_token)
    assert_equal "running", json_body.fetch("state")
  end
end
