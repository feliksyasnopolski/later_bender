class TotpCredential < ApplicationRecord
  belongs_to :user, inverse_of: :totp_credentials
  encrypts :secret

  validates :label, presence: true, length: { maximum: 80 }
  validates :secret, presence: true

  def confirmed?
    confirmed_at.present?
  end

  def verify(code, now: Time.current)
    counter = now.to_i / 30
    return false if last_used_counter && counter <= last_used_counter

    totp = ROTP::TOTP.new(secret, issuer: "Later, Bender", period: 30, digits: 6)
    return false unless totp.verify(code.to_s, drift_behind: 30, drift_ahead: 30, at: now)

    update!(last_used_counter: counter, last_used_at: now)
    true
  end
end
