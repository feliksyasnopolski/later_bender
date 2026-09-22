class Workspace < ApplicationRecord
  belongs_to :user
  has_many :workspace_executions, dependent: :delete_all
  has_many :workspace_events, dependent: :delete_all
  has_one :remote_workspace_placement, dependent: :destroy
  has_many :remote_workspace_operations, dependent: :delete_all

  encrypts :credential_snapshot

  before_validation :assign_public_identity, on: :create

  STATES = %w[starting ready stopping failed].freeze
  validates :ref, :environment, :architecture, :os_name, :os_version, :shell, :workspace_root, :state, presence: true
  validates :state, inclusion: { in: STATES }
  validates :public_number, numericality: { only_integer: true, greater_than: 0 }, presence: true

  def self.find_by_public_ref(ref)
    where(ref:).or(where(legacy_ref: ref)).first
  end

  def os = { name: os_name, version: os_version }

  def next_sequence
    workspace_events.maximum(:sequence).to_i + 1
  end

  def append_event!(kind, payload = {})
    with_lock { workspace_events.create!(sequence: next_sequence, kind:, payload:, occurred_at: Time.current) }
  end

  private

  def assign_public_identity
    return if public_number.present? && ref.present?

    user.with_lock { self.public_number ||= user.workspaces.maximum(:public_number).to_i + 1 }
    self.ref ||= "WS-#{public_number}"
  end
end
