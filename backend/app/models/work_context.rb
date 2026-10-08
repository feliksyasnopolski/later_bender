class WorkContext < ApplicationRecord
  belongs_to :user
  belongs_to :task, optional: true

  validates :scratchpad, length: { maximum: 1.megabyte }
  validate :task_belongs_to_user

  scope :current, -> { where(ended_at: nil) }

  def current?
    ended_at.nil?
  end

  private

  def task_belongs_to_user
    return if task.nil? || task.project.user_id == user_id

    errors.add(:task, "must belong to the current user")
  end
end
