class WorkspaceExecution < ApplicationRecord
  belongs_to :workspace
  STATES = %w[running exited timed_out cancelled failed_to_start].freeze
  validates :ref, :state, :stdout_handle, :stderr_handle, presence: true
  validates :state, inclusion: { in: STATES }
end
