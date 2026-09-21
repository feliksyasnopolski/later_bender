require "rails_helper"

RSpec.describe "Remote Agent contract", type: :request do
  let!(:user) { User.create!(username: "remote-agent-user", password: "password123") }
  let!(:other_user) { User.create!(username: "other-remote-user", password: "password123") }
  let!(:runner_capabilities) do
    { "environments" => [ { "environment" => "linux", "architectures" => [ { "architecture" => "arm64", "os" => { "name" => "Linux", "version" => "6.8" }, "resources" => {}, "capabilities" => {} } ] } ] }
  end
  let(:key) { Ed25519::SigningKey.generate }
  let(:advertisement) { { "name" => "Felix Mac", "platform" => "macos", "architecture" => "arm64", "supported_executors" => [ "native" ], "capabilities" => { "process_control" => "process_group" } } }

  before do
    _token, @raw_token = ApiToken.issue!(user:, name: "remote agent test")
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request).with(:get, "/capabilities", anything).and_return(runner_capabilities)
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request).with(:get, "/capabilities").and_return(runner_capabilities)
  end

  it "requires authentication to mint an enrollment token and stores only a public key on enrollment" do
    post "/api/remote-agents/enrollment-tokens", headers: json_headers
    expect(response).to have_http_status(:unauthorized)

    post "/api/remote-agents/enrollment-tokens", headers: json_headers(@raw_token)
    expect(response).to have_http_status(:created)
    token = json_body.fetch("token")
    expect(token).to match(/\A[0-9a-f]{64}\z/)
    expect(RemoteAgentEnrollmentToken.last.token_digest).not_to eq(token)

    post "/api/remote-agent/enroll", params: advertisement.merge("enrollment_token" => token, "public_key" => Base64.strict_encode64(key.verify_key.to_bytes)).to_json, headers: json_headers
    expect(response).to have_http_status(:created)
    expect(json_body.fetch("ref")).to eq("RA-1")
    agent = user.remote_agents.first
    expect(agent.public_key).to eq(Base64.strict_encode64(key.verify_key.to_bytes))
    expect(agent.attributes.keys).not_to include("private_key")

    post "/api/remote-agent/enroll", params: advertisement.merge("enrollment_token" => token, "public_key" => Base64.strict_encode64(key.verify_key.to_bytes)).to_json, headers: json_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.remote_agents.count).to eq(1)
  end

  it "authenticates a signed challenge, replaces sessions, refreshes capabilities, and projects truthful targets" do
    agent = enroll_agent
    post "/api/remote-agent/challenge", params: { agent: agent.ref }.to_json, headers: json_headers
    challenge = json_body
    signature = key.sign(challenge.fetch("signed_bytes"))
    post "/api/remote-agent/authenticate", params: { agent: agent.ref, challenge_id: challenge.fetch("challenge_id"), nonce: challenge.fetch("nonce"), signature: Base64.strict_encode64(signature) }.to_json, headers: json_headers
    expect(response).to have_http_status(:ok)
    session_token = json_body.fetch("session_token")

    post "/api/remote-agent/heartbeat", params: advertisement.merge("name" => "Felix Mac Updated").to_json, headers: json_headers(session_token)
    expect(response).to have_http_status(:ok)
    expect(agent.reload.capabilities).to eq("process_control" => "process_group")

    get "/api/workspaces/targets", headers: json_headers(@raw_token)
    remote = json_body.fetch("targets").find { |target| target["ref"] == agent.ref }
    expect(remote).to include("name" => "Felix Mac", "availability" => "available", "supported_executors" => [ "native" ])
    expect(remote).not_to have_key("session_token")

    post "/api/remote-agents/#{agent.ref}/revoke", headers: json_headers(@raw_token)
    expect(response).to have_http_status(:ok)
    post "/api/remote-agent/heartbeat", params: advertisement.to_json, headers: json_headers(session_token)
    expect(response).to have_http_status(:unauthorized)
    get "/api/workspaces/targets", headers: json_headers(@raw_token)
    expect(json_body.fetch("targets").map { |target| target["ref"] }).not_to include(agent.ref)
  end

  it "rejects a replayed challenge and an expired enrollment token" do
    post "/api/remote-agents/enrollment-tokens", headers: json_headers(@raw_token)
    enrollment_token = json_body.fetch("token")
    RemoteAgentEnrollmentToken.last.update!(expires_at: 1.second.ago)
    post "/api/remote-agent/enroll", params: advertisement.merge("enrollment_token" => enrollment_token, "public_key" => Base64.strict_encode64(key.verify_key.to_bytes)).to_json, headers: json_headers
    expect(response).to have_http_status(:unprocessable_content)

    agent = enroll_agent
    post "/api/remote-agent/challenge", params: { agent: agent.ref }.to_json, headers: json_headers
    challenge = json_body
    params = { agent: agent.ref, challenge_id: challenge.fetch("challenge_id"), nonce: challenge.fetch("nonce"), signature: Base64.strict_encode64(key.sign(challenge.fetch("signed_bytes"))) }
    post "/api/remote-agent/authenticate", params: params.to_json, headers: json_headers
    expect(response).to have_http_status(:ok)
    post "/api/remote-agent/authenticate", params: params.to_json, headers: json_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects the wrong key and cross-user access" do
    agent = enroll_agent
    post "/api/remote-agent/challenge", params: { agent: agent.ref }.to_json, headers: json_headers
    challenge = json_body
    wrong_key = Ed25519::SigningKey.generate
    post "/api/remote-agent/authenticate", params: { agent: agent.ref, challenge_id: challenge.fetch("challenge_id"), nonce: challenge.fetch("nonce"), signature: Base64.strict_encode64(wrong_key.sign(challenge.fetch("signed_bytes"))) }.to_json, headers: json_headers
    expect(response).to have_http_status(:unauthorized)

    _other_token, other_raw = ApiToken.issue!(user: other_user, name: "other")
    post "/api/remote-agents/#{agent.ref}/revoke", headers: json_headers(other_raw)
    expect(response).to have_http_status(:not_found)
  end

  it "allocates the canonical Workspace before exposing an idempotent prepare operation" do
    stub_const("Api::WorkspacesController::REMOTE_OPERATION_OBSERVATION_WINDOW_SECONDS", 0)
    agent = enroll_agent
    session_token = authenticate_agent(agent)

    post "/api/workspaces", params: { target: agent.ref, executor: "native", label: "remote test" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:created)
    workspace = Workspace.find_by!(ref: json_body.fetch("ref"))
    placement = workspace.remote_workspace_placement
    expect(placement).to be_present
    expect(workspace.state).to eq("starting")

    get "/api/remote-agent/operations", headers: json_headers(session_token)
    operation = json_body.fetch("operations").sole
    expect(operation).to include("workspace" => workspace.ref, "operation_id" => placement.operation_id, "executor" => "native")

    post "/api/remote-agent/operations/#{placement.operation_id}/result", params: operation.merge("status" => "prepared", "provider_workspace_ref" => "local-#{workspace.ref}").to_json, headers: json_headers(session_token)
    expect(response).to have_http_status(:ok)
    expect(workspace.reload.state).to eq("ready")
    expect(workspace.remote_workspace_placement.reload.state).to eq("ready")

    post "/api/remote-agent/operations/#{placement.operation_id}/result", params: operation.merge("status" => "prepared").to_json, headers: json_headers(session_token)
    expect(response).to have_http_status(:ok)
    expect(workspace.reload.remote_workspace_placement.state).to eq("ready")

    get "/api/workspaces/#{workspace.ref}", headers: json_headers(@raw_token)
    expect(json_body).to include("target" => agent.ref, "executor" => "native", "availability" => "online")
  end

  it "does not fail over or create a Workspace when the selected Agent is offline" do
    agent = enroll_agent
    post "/api/workspaces", params: { target: agent.ref, executor: "native" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:service_unavailable)
    expect(json_body.dig("error", "code")).to eq("workspace_unavailable")
    expect(user.workspaces).to be_empty
  end

  it "allocates WSE identity before dispatch and projects native output" do
    stub_const("Api::WorkspacesController::REMOTE_OPERATION_OBSERVATION_WINDOW_SECONDS", 0)
    agent = enroll_agent
    session_token = authenticate_agent(agent)
    post "/api/workspaces", params: { target: agent.ref, executor: "native" }.to_json, headers: json_headers(@raw_token)
    workspace = Workspace.find_by!(ref: json_body.fetch("ref"))
    placement = workspace.remote_workspace_placement
    post "/api/remote-agent/operations/#{placement.operation_id}/result", params: { operation_id: placement.operation_id, workspace: workspace.ref, spec_hash: placement.spec_hash, status: "prepared", provider_workspace_ref: workspace.ref }.to_json, headers: json_headers(session_token)

    post "/api/workspaces/#{workspace.ref}/executions", params: { command: "printf remote" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:created)
    execution = workspace.workspace_executions.last
    expect(execution).to be_present
    expect(execution.state).to eq("running")

    get "/api/remote-agent/operations", headers: json_headers(session_token)
    operation = json_body.fetch("operations").find { |item| item["type"] == "start_execution" }
    expect(operation).to include("execution" => execution.ref, "operation_id" => execution.remote_operation_id)
    result = operation.merge("status" => "running", "execution" => execution.ref, "stdout_base64" => Base64.strict_encode64("remote"), "stderr_base64" => "")
    post "/api/remote-agent/operations/#{execution.remote_operation_id}/result", params: result.to_json, headers: json_headers(session_token)
    expect(response).to have_http_status(:ok)

    post "/api/remote-agent/operations/#{execution.remote_operation_id}/result", params: result.merge("status" => "exited", "exit_code" => 0).to_json, headers: json_headers(session_token)
    expect(response).to have_http_status(:ok)
    get "/api/workspace-executions/#{execution.ref}", headers: json_headers(@raw_token)
    expect(json_body).to include("state" => "exited", "exit_code" => 0)
    post "/api/workspace-executions/#{execution.ref}/output", params: { stream: "stdout", format: "text" }.to_json, headers: json_headers(@raw_token)
    expect(json_body).to include("data" => "remote", "stream_complete" => true)
  end

  it "collapses remote create and execution fast paths within the bounded wait" do
    agent = enroll_agent
    session_token = authenticate_agent(agent)
    allow_any_instance_of(Api::WorkspacesController).to receive(:remote_observation_sleep) do
      workspace = Workspace.last
      if workspace.state == "starting"
        workspace.remote_workspace_placement.update!(state: "ready", prepared_at: Time.current)
        workspace.update!(state: "ready")
      elsif workspace.remote_workspace_placement&.operation_kind == "destroy"
        workspace.destroy!
      elsif (execution = workspace.workspace_executions.last)&.state == "running"
        execution.update!(state: "exited", finished_at: Time.current, exit_code: 0, stdout_data: "remote fast")
      end
    end

    post "/api/workspaces", params: { target: agent.ref, executor: "native" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:created)
    workspace = Workspace.find_by!(ref: json_body.fetch("ref"))
    expect(json_body).to include("state" => "ready", "limits" => { "cpus" => nil, "memory_bytes" => nil, "disk_bytes" => nil, "pids" => nil })

    post "/api/workspaces/#{workspace.ref}/executions", params: { command: "printf remote fast" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:created)
    expect(json_body).to include("state" => "exited", "exit_code" => 0)
    expect(json_body.dig("stdout", "data")).to eq("remote fast")
    expect(session_token).to be_present

    ActiveRecord::Base.cache do
      delete "/api/workspaces/#{workspace.ref}", headers: json_headers(@raw_token)
    end
    expect(response).to have_http_status(:ok)
    expect(json_body).to include("ref" => workspace.ref, "destroyed" => true)
  end

  it "keeps remote create and destroy asynchronous when the bounded wait expires" do
    stub_const("Api::WorkspacesController::REMOTE_OPERATION_OBSERVATION_WINDOW_SECONDS", 0)
    agent = enroll_agent
    authenticate_agent(agent)

    post "/api/workspaces", params: { target: agent.ref, executor: "native" }.to_json, headers: json_headers(@raw_token)
    expect(json_body).to include("state" => "starting")
    workspace = Workspace.find_by!(ref: json_body.fetch("ref"))

    delete "/api/workspaces/#{workspace.ref}", headers: json_headers(@raw_token)
    expect(response).to have_http_status(:accepted)
    expect(json_body).to include("ref" => workspace.ref, "destroyed" => false, "state" => "stopping")
  end

  private

  def enroll_agent
    post "/api/remote-agents/enrollment-tokens", headers: json_headers(@raw_token)
    enrollment_token = json_body.fetch("token")
    post "/api/remote-agent/enroll", params: advertisement.merge("enrollment_token" => enrollment_token, "public_key" => Base64.strict_encode64(key.verify_key.to_bytes)).to_json, headers: json_headers
    user.remote_agents.first
  end

  def authenticate_agent(agent)
    post "/api/remote-agent/challenge", params: { agent: agent.ref }.to_json, headers: json_headers
    challenge = json_body
    post "/api/remote-agent/authenticate", params: { agent: agent.ref, challenge_id: challenge.fetch("challenge_id"), nonce: challenge.fetch("nonce"), signature: Base64.strict_encode64(key.sign(challenge.fetch("signed_bytes"))) }.to_json, headers: json_headers
    json_body.fetch("session_token")
  end
end
