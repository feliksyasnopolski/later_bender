class User < ApplicationRecord
  devise :database_authenticatable

  has_many :projects, dependent: :destroy, inverse_of: :user
  has_many :notes, dependent: :destroy, inverse_of: :user
  has_many :api_tokens, dependent: :destroy, inverse_of: :user
  has_many :totp_credentials, dependent: :destroy, inverse_of: :user
  has_many :workspaces, dependent: :delete_all
  has_many :credentials, dependent: :destroy, inverse_of: :user

  validates :username, presence: true, length: { in: 1..80 }, uniqueness: { case_sensitive: false }
  validates :password, confirmation: true, length: { minimum: 8 }, allow_nil: true
  validate :username_is_printable
  validate :password_is_present, on: :create

  def self.find_for_database_authentication(conditions)
    where("LOWER(username) = LOWER(?)", conditions[:username].to_s).first
  end

  private

  def username_is_printable
    errors.add(:username, "must contain printable characters only") unless username.to_s.match?(/\A[[:print:]]+\z/)
  end

  def password_is_present
    errors.add(:password, "can't be blank") if password.blank?
  end
end
