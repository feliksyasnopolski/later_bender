class Credential < ApplicationRecord
  belongs_to :user, inverse_of: :credentials
  encrypts :secret

  KINDS = %w[env file].freeze
  ENV_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  before_validation :assign_ref, on: :create
  validates :ref, :name, :kind, :secret, presence: true
  validates :kind, inclusion: { in: KINDS }
  validate :kind_is_immutable, on: :update
  validate :metadata_matches_kind
  validates :name, length: { in: 1..120 }

  def metadata
    result = { "ref" => ref, "name" => name, "kind" => kind }
    if kind == "env"
      result["env_name"] = env_name
    else
      result["file_path"] = file_path
      result["file_mode"] = file_mode
    end
    result
  end

  private

  def assign_ref
    return if ref.present? || user.blank?

    user.with_lock do
      self.public_number = user.credentials.maximum(:public_number).to_i + 1
      self.ref = "CRED-#{public_number}"
    end
  end

  def kind_is_immutable
    errors.add(:kind, "cannot be changed") if will_save_change_to_kind?
  end

  def metadata_matches_kind
    if kind == "env"
      errors.add(:env_name, "is invalid") unless env_name.to_s.match?(ENV_NAME)
      errors.add(:file_path, "must be blank") if file_path.present?
      errors.add(:file_mode, "must be blank") if file_mode.present?
    elsif kind == "file"
      parts = file_path.to_s.split("/")
      errors.add(:file_path, "is invalid") unless file_path.to_s.start_with?("/root/") && parts.drop(1).none? { |part| part.blank? || part == "." || part == ".." }
      errors.add(:file_mode, "must be 0400 or 0600") unless [ 400, 600 ].include?(file_mode)
      errors.add(:env_name, "must be blank") if env_name.present?
    end
  end
end
