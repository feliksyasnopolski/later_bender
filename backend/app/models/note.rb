class Note < ApplicationRecord
  belongs_to :user, inverse_of: :notes
  belongs_to :project, optional: true
  has_many :note_tags, dependent: :destroy
  has_many :tags, through: :note_tags
  has_many :task_notes, dependent: :destroy
  has_many :tasks, through: :task_notes

  validates :title, presence: true
  validates :body, presence: true
  validate :project_belongs_to_user

  private

  def project_belongs_to_user
    return if project.blank? || project.user_id == user_id

    errors.add(:project, "must belong to the note's user")
  end
end
