require "rails_helper"

RSpec.describe WorkspaceEventProjection do
  it "normalizes historical kinds and string timeout values to the current public shape" do
    user = User.create!(username: "event-projection-user", password: "password123")
    workspace = user.workspaces.create!(state: "ready", environment: "darwin", architecture: "arm64", os_name: "macOS", os_version: "test", shell: "/bin/bash", workspace_root: "/workspace", last_activity_at: Time.current)
    event = workspace.workspace_events.create!(sequence: 1, kind: "workspace_ready", occurred_at: Time.utc(2026, 1, 1), payload: {})
    expect(described_class.call(event)).to include("kind" => "workspace_prepared", "workspace" => workspace.ref)

    execution = workspace.workspace_events.create!(sequence: 2, kind: "execution", occurred_at: Time.utc(2026, 1, 1), payload: {
      "ref" => "WSE-1", "requested_timeout_seconds" => "1.25", "invocation" => { "kind" => "argv", "argv" => [ "/bin/pwd" ] },
      "cwd" => "/workspace", "secret_env_names" => [], "started_at" => Time.utc(2026, 1, 1), "finished_at" => nil,
      "state" => "failed_to_start", "exit_code" => nil, "terminating_signal" => nil,
      "stdout_preview" => { "format" => "text", "data" => "", "total_byte_size" => 0, "inline_complete" => true },
      "stderr_preview" => { "format" => "text", "data" => "", "total_byte_size" => 0, "inline_complete" => true }
    })
    projected = described_class.call(execution)
    expect(projected).to include("kind" => "execution", "execution" => "WSE-1", "requested_timeout_seconds" => 1.25)
  end
end
