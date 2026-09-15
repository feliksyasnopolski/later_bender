class TaskNote < ApplicationRecord
  update_index("search_documents", if: -> { task.present? && note.present? && !task.destroyed? && !note.destroyed? }) { task }
  belongs_to :task
  belongs_to :note
  validates :note_id, uniqueness: { scope: :task_id }
  validate :same_user

  private

  def same_user
    return if task.blank? || note.blank? || task.project.user_id == note.user_id

    errors.add(:base, "task and note must belong to the same user")
  end
end
