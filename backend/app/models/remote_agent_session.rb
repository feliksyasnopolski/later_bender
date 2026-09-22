class RemoteAgentSession < ApplicationRecord
  belongs_to :remote_agent

  def self.issue!(remote_agent:)
    raw = SecureRandom.hex(32)
    session = nil
    remote_agent.with_lock do
      generation = remote_agent.session_generation.to_i + 1
      remote_agent.update!(session_generation: generation)
      remote_agent.remote_agent_sessions.where(disconnected_at: nil).update_all(disconnected_at: Time.current, updated_at: Time.current)
      session = create!(remote_agent:, generation:, token_digest: Digest::SHA256.hexdigest(raw), connected_at: Time.current, last_heartbeat_at: Time.current)
    end
    [ session, raw ]
  end

  def self.authenticate(raw)
    return if raw.blank?

    joins(:remote_agent).where(token_digest: Digest::SHA256.hexdigest(raw), disconnected_at: nil)
      .where("remote_agent_sessions.generation = remote_agents.session_generation").first
  end

  def heartbeat!(platform:, architecture:, supported_executors:, capabilities:)
    transaction do
      remote_agent.update!(platform:, architecture:, supported_executors:, capabilities:, last_seen_at: Time.current)
      update!(last_heartbeat_at: Time.current)
    end
  end
end
