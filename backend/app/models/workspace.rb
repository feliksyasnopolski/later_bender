class Workspace < ApplicationRecord
  belongs_to :user
  has_many :workspace_executions, dependent: :delete_all
  has_many :workspace_events, dependent: :delete_all

  STATES = %w[starting ready stopping failed].freeze
  validates :ref, :environment, :architecture, :os_name, :os_version, :shell, :workspace_root, :state, presence: true
  validates :state, inclusion: { in: STATES }

  def os = { name: os_name, version: os_version }

  def next_sequence
    workspace_events.maximum(:sequence).to_i + 1
  end

  def append_event!(kind, payload = {})
    with_lock { workspace_events.create!(sequence: next_sequence, kind:, payload:, occurred_at: Time.current) }
  end
end
