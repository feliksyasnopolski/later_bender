class FileTag < ApplicationRecord
  belongs_to :stored_file
  belongs_to :tag
  validates :tag_id, uniqueness: { scope: :stored_file_id }
end
