class FileNote < ApplicationRecord
  belongs_to :stored_file
  belongs_to :note
  validates :note_id, uniqueness: { scope: :stored_file_id }
end
