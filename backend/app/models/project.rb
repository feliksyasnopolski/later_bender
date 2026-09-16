class Project < ApplicationRecord
  update_index("search_documents") { tasks + notes }
  belongs_to :user, inverse_of: :projects
  has_many :tasks, dependent: :restrict_with_exception
  has_many :notes, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :shorthand, presence: true, uniqueness: true, format: { with: /\A[A-Z][A-Z0-9]{0,11}\z/ }
  before_validation :set_slug, if: -> { slug.blank? && name.present? }
  before_validation :normalize_shorthand
  validate :shorthand_is_immutable, on: :update

  private

  def set_slug
    self.slug = name.to_s.parameterize
  end

  def normalize_shorthand
    self.shorthand = shorthand.to_s.upcase.presence || name.to_s.upcase.scan(/[A-Z0-9]+/).map { |word| word[0] }.join[0, 12].presence || name.to_s.parameterize.upcase[0, 12]
  end

  def shorthand_is_immutable
    errors.add(:shorthand, "cannot be changed") if shorthand_changed?
  end
end
