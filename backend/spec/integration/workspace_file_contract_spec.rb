require "rails_helper"

RSpec.describe "Workspace file and transcript contracts", type: :request do
  before do
    user = User.create!(username: "workspace-contract", password: "password123")
    _token, @raw_token = ApiToken.issue!(user:, name: "workspace contract")
    @project = user.projects.create!(name: "Workspace contract", slug: "workspace-contract", shorthand: "WC")
    @promotion_payload = nil
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request) do |_, method, path, payload = nil|
      case [ method, path ]
      when [ :post, "/workspaces" ]
        { "ref" => "WSR-contract", "runner_handle" => "WSR-contract", "state" => "ready", "environment" => "linux", "architecture" => "arm64", "os" => { "name" => "Linux", "version" => "test" }, "shell" => "/bin/bash", "workspace_root" => "/workspace", "limits" => { "cpus" => 2, "memory_bytes" => 1024, "disk_bytes" => 2048, "pids" => 32 }, "capabilities" => { "internet" => true }, "created_at" => "2026-01-01T00:00:00Z", "last_activity_at" => "2026-01-01T00:00:00Z", "expires_at" => "2026-01-02T00:00:00Z" }
      when [ :post, "/workspaces/WSR-contract/executions" ]
        execution_result("running")
      when [ :get, "/executions/WSE-contract" ]
        execution_result("exited")
      when [ :post, "/executions/WSE-contract/output" ]
        output_result(payload.fetch("stream"))
      when [ :post, "/workspaces/WSR-contract/file-promote" ]
        @promotion_payload = payload
        { "filename" => "artifact.bin", "media_type" => "application/octet-stream", "bytes_base64" => Base64.strict_encode64("\x00\x01\xffABC".b), "byte_size" => 6, "sha256" => Digest::SHA256.hexdigest("\x00\x01\xffABC".b) }
      when [ :post, "/workspaces/WSR-contract/file-read" ]
        file_read_result(payload)
      when [ :post, "/workspaces/WSR-contract/files" ]
        data = Base64.strict_decode64(payload.fetch("bytes_base64"))
        { "workspace" => "WSR-contract", "path" => "input.bin", "byte_size" => data.bytesize, "sha256" => Digest::SHA256.hexdigest(data) }
      else
        raise "unexpected runner request #{method} #{path}"
      end
    end
  end

  it "returns verified file metadata from the hosted runner" do
    bytes = "\x00\xffhosted".b
    file = create_file(bytes)
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request).with(:post, "/workspaces/WSR-contract/files", anything) do |_, _, _, payload|
      expect(Base64.strict_decode64(payload.fetch("bytes_base64"))).to eq(bytes)
      { "workspace" => "WSR-contract", "path" => "input.bin", "byte_size" => bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(bytes) }
    end

    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    post "/api/workspaces/#{json_body.fetch("ref")}/files", params: { file: file.ref, path: "input.bin" }.to_json, headers: json_headers(@raw_token)

    expect(response).to have_http_status(:ok)
    expect(json_body).to include("file" => file.ref, "path" => "input.bin", "byte_size" => bytes.bytesize, "sha256" => file.sha256)
  end

  it "normalizes the Remote Agent byte-size string only after matching its integrity acknowledgement" do
    bytes = "remote bytes".b
    file = create_file(bytes)
    workspace = create_remote_workspace
    allow_any_instance_of(Api::WorkspacesController).to receive(:observe_remote_operation) do |_controller, **_kwargs, &condition|
      operation = workspace.remote_workspace_operations.order(:created_at).last
      operation.update!(state: "succeeded", result: { "byte_size" => bytes.bytesize.to_s, "sha256" => file.sha256 })
      condition.call
    end

    post "/api/workspaces/#{workspace.ref}/files", params: { file: file.ref, path: "input.bin" }.to_json, headers: json_headers(@raw_token)

    expect(response).to have_http_status(:ok)
    expect(json_body).to include("file" => file.ref, "path" => "input.bin", "byte_size" => bytes.bytesize, "sha256" => file.sha256)
    expect(workspace.workspace_events.last.payload).to include("byte_size" => bytes.bytesize, "sha256" => file.sha256)
  end

  it "rejects malformed hosted integrity acknowledgements without recording an import" do
    bytes = "hosted bytes".b
    file = create_file(bytes)
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request).with(:post, "/workspaces/WSR-contract/files", anything)
      .and_return("workspace" => "WSR-contract", "path" => "input.bin", "byte_size" => bytes.bytesize)

    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    workspace_ref = json_body.fetch("ref")
    post "/api/workspaces/#{workspace_ref}/files", params: { file: file.ref }.to_json, headers: json_headers(@raw_token)

    expect(response).to have_http_status(:service_unavailable)
    expect(json_body.dig("error", "code")).to eq("workspace_unavailable")
    expect(Workspace.find_by!(ref: workspace_ref).workspace_events.where(kind: "file_imported")).to be_empty
  end

  it "promotes one complete output copy for running and terminal lifecycle events" do
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    workspace_ref = json_body.fetch("ref")
    post "/api/workspaces/#{workspace_ref}/executions", params: { command: "test" }.to_json, headers: json_headers(@raw_token)
    post "/api/workspaces/#{workspace_ref}/transcript-promote", params: { project: @project.slug, filename: "transcript.md" }.to_json, headers: json_headers(@raw_token)
    assert_response :ok
    file = @project.stored_files.find_by(filename: "transcript.md")
    body = file.original.download
    assert_equal 1, body.scan("### stdout").length
    assert_equal 1, body.scan("### stderr").length
    assert_not_includes body.lines.grep(/stdout_preview|stderr_preview/), "earlier lifecycle events must remain metadata-only"
    assert_equal 1, body.scan('"state": "running"').length
    assert_equal 1, body.scan('"state": "exited"').length
  end

  it "returns binary Workspace promotions with their exact non-text media type and sha" do
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    workspace_ref = json_body.fetch("ref")
    post "/api/workspaces/#{workspace_ref}/file-promote", params: { project: @project.slug, path: "/workspace/artifact.bin" }.to_json, headers: json_headers(@raw_token)
    assert_response :ok
    assert_equal "artifact.bin", @promotion_payload.fetch("path")
    assert_equal "application/octet-stream", json_body.fetch("media_type")
    assert_equal Digest::SHA256.hexdigest("\x00\x01\xffABC".b), json_body.fetch("sha256")
  end

  it "returns stable text and line-range errors from the runner" do
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    workspace_ref = json_body.fetch("ref")

    post "/api/workspaces/#{workspace_ref}/file-read", params: { path: "bad.bin" }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "not_text", json_body.dig("error", "code")

    post "/api/workspaces/#{workspace_ref}/file-read", params: { path: "text.txt", locator: { kind: "lines", start: 3, end: 2 } }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "invalid_range", json_body.dig("error", "code")
  end

  it "does not let a malformed historical event poison transcript reads" do
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    workspace = Workspace.find_by!(ref: json_body.fetch("ref"))
    workspace.workspace_events.create!(sequence: workspace.next_sequence, kind: "file_imported", occurred_at: Time.current, payload: { "file" => "LB-F1", "path" => "/workspace/bad", "byte_size" => "not-a-number", "sha256" => "a" * 64 })

    post "/api/workspaces/#{workspace.ref}/transcript", params: {}.to_json, headers: json_headers(@raw_token)
    assert_response :ok
    assert_equal [], json_body.fetch("events").select { |event| event["sequence"] == 2 }
  end

  it "supports bounded transcript reads without duplicating cursor pages" do
    post "/api/workspaces", params: {}.to_json, headers: json_headers(@raw_token)
    workspace_ref = json_body.fetch("ref")
    workspace = Workspace.find_by!(ref: workspace_ref)
    3.times { |index| workspace.append_event!("workspace_prepared", { "marker" => index }) }

    post "/api/workspaces/#{workspace_ref}/transcript", params: { limit: 2 }.to_json, headers: json_headers(@raw_token)
    assert_response :ok
    first = json_body
    assert_equal 2, first.fetch("events").length
    refute_nil first.fetch("next_cursor")

    post "/api/workspaces/#{workspace_ref}/transcript", params: { cursor: first.fetch("next_cursor"), limit: 2 }.to_json, headers: json_headers(@raw_token)
    assert_response :ok
    second = json_body
    assert_empty(first.fetch("events").map { |event| event.fetch("sequence") } & second.fetch("events").map { |event| event.fetch("sequence") })
  end

  private

  def create_file(bytes)
    file = @project.stored_files.create!(filename: "input.bin", media_type: "application/octet-stream", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: file.filename, content_type: file.media_type)
    file
  end

  def create_remote_workspace
    user = User.find_by!(username: "workspace-contract")
    agent = user.remote_agents.create!(name: "Contract Agent", public_number: 1, public_key: Base64.strict_encode64(Ed25519::SigningKey.generate.verify_key.to_bytes), platform: "macos", architecture: "arm64", supported_executors: [ "native" ], capabilities: {})
    allow_any_instance_of(RemoteAgent).to receive(:online?).and_return(true)
    workspace = user.workspaces.create!(state: "ready", environment: "macos", architecture: "arm64", os_name: "macOS", os_version: "unknown", shell: "/bin/bash", workspace_root: "/workspace", last_activity_at: Time.current)
    workspace.create_remote_workspace_placement!(remote_agent: agent, executor: "native", operation_id: "WSOP-test", spec_hash: "a" * 64, spec: { "ready" => true }, state: "ready")
    workspace
  end

  def execution_result(state)
    { "ref" => "WSE-contract", "workspace" => "WSR-contract", "sequence" => 1, "state" => state, "invocation" => { "kind" => "shell", "command" => "test" }, "cwd" => "/workspace", "env" => {}, "secret_env_names" => [], "started_at" => "2026-01-01T00:00:00Z", "finished_at" => state == "running" ? nil : "2026-01-01T00:00:01Z", "exit_code" => state == "exited" ? 0 : nil, "terminating_signal" => nil, "requested_timeout_seconds" => nil, "stdout_handle" => "stdout", "stderr_handle" => "stderr" }
  end

  def output_result(stream)
    data = stream == "stdout" ? "stdout-data" : "stderr-data"
    { "format" => "base64", "data" => Base64.strict_encode64(data), "chunk_byte_size" => data.bytesize, "total_byte_size" => data.bytesize, "next_cursor" => nil, "stream_complete" => true }
  end

  def file_read_result(payload)
    case payload.fetch("path")
    when "bad.bin" then raise WorkspaceRunnerClient::Unavailable.new("invalid UTF-8", code: "not_text")
    when "text.txt" then raise WorkspaceRunnerClient::Unavailable.new("invalid line range", code: "invalid_range")
    end
  end
end
