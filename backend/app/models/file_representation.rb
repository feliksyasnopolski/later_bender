class FileRepresentation < ApplicationRecord
  belongs_to :stored_file
  validates :kind, :generator, :generator_version, :status, presence: true
  validates :kind, uniqueness: { scope: :stored_file_id }
  validates :status, inclusion: { in: %w[ready failed] }
end
