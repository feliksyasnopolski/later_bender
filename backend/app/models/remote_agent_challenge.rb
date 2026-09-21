class RemoteAgentChallenge < ApplicationRecord
  belongs_to :remote_agent

  LIFETIME = 60.seconds

  def self.issue!(remote_agent:, nonce:)
    create!(remote_agent:, challenge_id: SecureRandom.hex(16), nonce_digest: Digest::SHA256.hexdigest(nonce), expires_at: LIFETIME.from_now)
  end

  def consume!
    with_lock do
      raise ActiveRecord::RecordNotFound if consumed_at.present? || expires_at <= Time.current

      update!(consumed_at: Time.current)
    end
  end
end
