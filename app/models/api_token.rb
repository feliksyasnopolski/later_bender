class ApiToken < ApplicationRecord
  belongs_to :user, inverse_of: :api_tokens

  class << self
    def issue!(user:, name:)
      raw_token = SecureRandom.hex(32)
      token = create!(user: user, name: name, token_digest: digest(raw_token))
      [ token, raw_token ]
    end

    def authenticate(raw_token)
      return if raw_token.blank?
      find_by({ token_digest: digest(raw_token), revoked_at: nil })&.tap do |token|
        token.update_column(:last_used_at, Time.current)
      end
    end

    def revoke_all_for!(user)
      where(user: user, revoked_at: nil).update_all(revoked_at: Time.current, updated_at: Time.current)
    end

    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :user, presence: true

  def revoke!
    update!(revoked_at: Time.current)
  end
end
