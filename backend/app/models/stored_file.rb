class StoredFile < ApplicationRecord
  belongs_to :project
  has_one_attached :original
  has_many :file_tags, dependent: :destroy
  has_many :tags, through: :file_tags
  has_many :file_tasks, dependent: :destroy
  has_many :tasks, through: :file_tasks
  has_many :file_notes, dependent: :destroy
  has_many :notes, through: :file_notes

  validates :number, presence: true, numericality: { only_integer: true }, uniqueness: { scope: :project_id }
  validates :filename, presence: true
  validates :byte_size, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sha256, presence: true, format: { with: /\A\h{64}\z/ }
  validate :number_is_immutable, on: :update
  validate :original_is_attached
  before_validation :allocate_number, on: :create

  def ref
    "#{project.shorthand}-F#{number}"
  end

  private

  def allocate_number
    return unless project&.persisted?
    project.with_lock do
      self.number ||= project.next_file_number
      project.update_columns(next_file_number: [ project.next_file_number, number + 1 ].max, updated_at: Time.current)
    end
  end

  def number_is_immutable
    errors.add(:number, "cannot be changed") if number_changed?
  end

  def original_is_attached
    errors.add(:original, "must be attached") unless original.attached? || new_record?
  end
end
