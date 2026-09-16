class FileTask < ApplicationRecord
  belongs_to :stored_file
  belongs_to :task
  validates :task_id, uniqueness: { scope: :stored_file_id }
end
