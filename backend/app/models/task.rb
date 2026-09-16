class Task < ApplicationRecord
  update_index("search_documents") { self }
  after_commit :index_semantic_content, on: %i[create update destroy]
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
  validates :position, numericality: { only_integer: true }
  before_validation :set_defaults

  private

  def set_defaults
    self.status ||= "backlog"
    self.priority ||= "normal"
    self.position ||= next_position
  end

  def next_position
    (project&.tasks&.where(status: status).maximum(:position) || 0) + 1000
  end

  def index_semantic_content
    SemanticIndexer.call(self)
  rescue StandardError => e
    Rails.logger.warn("semantic indexing deferred for Task #{id}: #{e.class}: #{e.message}")
  end
end
