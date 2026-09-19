namespace :workspaces do
  desc "Destroy expired transient Workspaces and their runner containers"
  task reap: :environment do
    WorkspaceReaper.call
  end
end
