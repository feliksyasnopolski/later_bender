class RemoteAgentSession < ApplicationRecord
  belongs_to :remote_agent

  def self.issue!(remote_agent:)
    raw = SecureRandom.hex(32)
    session = create!(remote_agent:, token_digest: Digest::SHA256.hexdigest(raw), connected_at: Time.current, last_heartbeat_at: Time.current)
    [ session, raw ]
  end

  def self.authenticate(raw)
    return if raw.blank?

    find_by(token_digest: Digest::SHA256.hexdigest(raw), disconnected_at: nil)
  end

  def heartbeat!(platform:, architecture:, supported_executors:, capabilities:)
    transaction do
      remote_agent.update!(platform:, architecture:, supported_executors:, capabilities:, last_seen_at: Time.current)
      update!(last_heartbeat_at: Time.current)
    end
  end
end
