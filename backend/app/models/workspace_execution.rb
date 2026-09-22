class WorkspaceExecution < ApplicationRecord
  belongs_to :workspace
  MAX_REMOTE_OUTPUT_BYTES = 1.megabyte
  STATES = %w[running exited timed_out cancelled failed_to_start lost].freeze
  validates :ref, :state, :stdout_handle, :stderr_handle, presence: true
  validates :state, inclusion: { in: STATES }

  encrypts :secret_env_snapshot
end
