class ApiToken < ApplicationRecord
  class << self
    def issue!(name:)
      raw_token = SecureRandom.hex(32)
      token = create!(name: name, token_digest: digest(raw_token))
      [ token, raw_token ]
    end

    def authenticate(raw_token)
      return if raw_token.blank?
      find_by({ token_digest: digest(raw_token), revoked_at: nil })&.tap { |token| token.touch(:last_used_at) }
    end

    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
end
