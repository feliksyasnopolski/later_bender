class RemoteWorkspaceOperation < ApplicationRecord
  belongs_to :workspace

  STATES = %w[pending running succeeded failed].freeze
  KINDS = %w[put_file read_file promote_file].freeze

  validates :operation_id, :kind, :spec_hash, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }
end
