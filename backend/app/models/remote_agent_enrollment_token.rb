class RemoteAgentEnrollmentToken < ApplicationRecord
  belongs_to :user, inverse_of: :remote_agent_enrollment_tokens

  LIFETIME = 10.minutes

  validates :token_digest, :expires_at, presence: true

  def self.issue!(user:)
    raw = SecureRandom.hex(32)
    token = create!(user:, token_digest: digest(raw), expires_at: LIFETIME.from_now)
    [ token, raw ]
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def consume!
    with_lock do
      raise ActiveRecord::RecordNotFound if consumed_at.present? || expires_at <= Time.current

      update!(consumed_at: Time.current)
    end
  end
end
