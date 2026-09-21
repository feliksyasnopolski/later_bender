require "rails_helper"

RSpec.describe "Workspace target contract", type: :request do
  before do
    user = User.create!(username: "workspace-targets", password: "password123")
    _token, @raw_token = ApiToken.issue!(user:, name: "workspace targets")
    @runner_workspace = {
      "ref" => "WSR-target", "runner_handle" => "WSR-target", "state" => "ready", "environment" => "linux",
      "architecture" => "arm64", "os" => { "name" => "Linux", "version" => "6.8" }, "shell" => "/bin/bash",
      "workspace_root" => "/workspace", "limits" => { "cpus" => 2, "memory_bytes" => 1024, "disk_bytes" => 2048, "pids" => 32 },
      "capabilities" => { "internet" => true }, "created_at" => "2026-01-01T00:00:00Z",
      "last_activity_at" => "2026-01-01T00:00:00Z", "expires_at" => "2026-01-02T00:00:00Z"
    }
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request) do |_, method, path, _payload = nil|
      case [ method, path ]
      when [ :get, "/capabilities" ]
        { "default_environment" => "linux", "default_architecture" => "arm64", "environments" => [ { "environment" => "linux", "architectures" => [ { "architecture" => "arm64", "os" => { "name" => "Linux", "version" => "6.8" }, "resources" => { "default" => @runner_workspace["limits"], "max" => @runner_workspace["limits"] }, "capabilities" => { "internet" => true } } ] } ] }
      when [ :post, "/workspaces" ] then @runner_workspace
      else raise "unexpected runner request #{method} #{path}"
      end
    end
  end

  it "discovers only the current hosted target" do
    get "/api/workspaces/targets", headers: json_headers(@raw_token)

    expect(response).to have_http_status(:ok)
    expect(json_body).to eq(
      "targets" => [ {
        "ref" => "hosted", "kind" => "hosted", "name" => "Hosted Workspace", "availability" => "available", "last_seen_at" => nil,
        "platform" => { "environment" => "linux", "os" => { "name" => "Linux", "version" => "6.8" }, "architectures" => [ "arm64" ] },
        "supported_executors" => [], "resources" => { "default" => @runner_workspace["limits"], "max" => @runner_workspace["limits"] },
        "capabilities" => { "internet" => true }
      } ]
    )
  end

  it "accepts the explicit hosted target and rejects unsupported executor selection" do
    post "/api/workspaces", params: { target: "hosted" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:created)

    post "/api/workspaces", params: { executor: "native" }.to_json, headers: json_headers(@raw_token)
    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "code")).to eq("executor_unsupported")
  end

  it "rejects unknown targets without provisioning" do
    post "/api/workspaces", params: { target: "RA-1", executor: "native" }.to_json, headers: json_headers(@raw_token)

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "code")).to eq("target_not_found")
  end
end
