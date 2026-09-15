class Tag < ApplicationRecord
  has_many :task_tags, dependent: :destroy
  has_many :tasks, through: :task_tags
  has_many :note_tags, dependent: :destroy
  has_many :notes, through: :note_tags
  before_validation :normalize_attributes
  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  private

  def normalize_attributes
    self.name = name.to_s.strip.downcase
    self.slug = name.to_s.parameterize if name.present?
  end
end
