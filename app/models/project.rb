class Project < ApplicationRecord
  has_many :tasks, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  before_validation :set_slug, if: -> { slug.blank? && name.present? }

  private

  def set_slug
    self.slug = name.to_s.parameterize
  end
end
