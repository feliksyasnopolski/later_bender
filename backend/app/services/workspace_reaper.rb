class WorkspaceReaper
  def self.call(now: Time.current)
    new(now:).call
  end

  def initialize(now:)
    @now = now
  end

  def call
    Workspace.where("expires_at <= ?", @now).find_each do |workspace|
      begin
        WorkspaceRunnerClient.new.request(:delete, "/workspaces/#{workspace.runner_handle}") if workspace.runner_handle.present?
        workspace.destroy!
      rescue WorkspaceRunnerClient::Unavailable => error
        raise unless error.message == "Workspace not found"
        workspace.destroy!
      end
    end
  end
end
