class WorkContext < ApplicationRecord
  belongs_to :user
  belongs_to :task, optional: true

  validates :scratchpad, length: { maximum: 1.megabyte }
  validate :task_belongs_to_user

  scope :current, -> { where(ended_at: nil, finished_at: nil) }
  scope :recent, -> { includes(:task).order(id: :desc) }

  def current?
    ended_at.nil? && finished_at.nil?
  end

  def state
    return "current" if current?
    return "finished" if finished_at.present?

    "inactive"
  end

  private

  def task_belongs_to_user
    return if task.nil? || task.project.user_id == user_id

    errors.add(:task, "must belong to the current user")
  end
end
