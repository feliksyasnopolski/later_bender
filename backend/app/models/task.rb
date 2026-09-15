class Task < ApplicationRecord
  belongs_to :project
  STATUSES = %w[backlog ready doing done dropped].freeze
  PRIORITIES = %w[low normal high].freeze
  has_many :task_tags, dependent: :destroy
  has_many :tags, through: :task_tags
  has_many :task_notes, dependent: :destroy
  has_many :notes, through: :task_notes

  validates :title, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
end
