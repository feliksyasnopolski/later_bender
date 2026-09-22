class RemoteAgent < ApplicationRecord
  belongs_to :user, inverse_of: :remote_agents
  has_many :remote_agent_challenges, dependent: :delete_all
  has_many :remote_agent_sessions, dependent: :delete_all
  has_many :remote_workspace_placements, dependent: :restrict_with_exception

  EXECUTORS = %w[native docker].freeze
  HEARTBEAT_TIMEOUT = 90.seconds

  before_validation :assign_ref, on: :create

  validates :ref, :name, :public_key, :platform, :architecture, presence: true
  validates :name, length: { maximum: 120 }
  validates :public_number, numericality: { only_integer: true, greater_than: 0 }, presence: true
  validate :supported_executors_are_known

  def online?
    enabled? && revoked_at.nil? && remote_agent_sessions.where(disconnected_at: nil).where("last_heartbeat_at >= ?", HEARTBEAT_TIMEOUT.ago).exists?
  end

  def revoke!
    transaction do
      update!(enabled: false, revoked_at: Time.current)
      remote_agent_sessions.where(disconnected_at: nil).update_all(disconnected_at: Time.current, updated_at: Time.current)
    end
  end

  private

  def assign_ref
    return if public_number.present? && ref.present?

    user.with_lock { self.public_number ||= user.remote_agents.maximum(:public_number).to_i + 1 }
    self.ref ||= "RA-#{public_number}"
  end

  def supported_executors_are_known
    values = Array(supported_executors)
    errors.add(:supported_executors, "contains an unsupported executor") unless values == values & EXECUTORS && values.length <= EXECUTORS.length
  end
end
