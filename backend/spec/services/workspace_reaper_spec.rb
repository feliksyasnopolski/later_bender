require "rails_helper"

RSpec.describe WorkspaceReaper do
  it "removes the Rails record when the runner already reaped its container" do
    workspace = Workspace.create!(
      user: create(:user), ref: "WSR-expired", environment: "linux", architecture: "arm64",
      os_name: "Linux", os_version: "test", shell: "/bin/bash", workspace_root: "/workspace",
      state: "ready", runner_handle: "WSR-expired", last_activity_at: 1.minute.ago, expires_at: 1.minute.ago
    )
    allow_any_instance_of(WorkspaceRunnerClient).to receive(:request).and_raise(WorkspaceRunnerClient::Unavailable, "Workspace not found")

    expect { described_class.call }.to change(Workspace, :count).by(-1)
  end
end
