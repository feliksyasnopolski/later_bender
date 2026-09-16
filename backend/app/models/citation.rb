class Citation < ApplicationRecord
  belongs_to :citing, polymorphic: true
  belongs_to :stored_file
  validates :representation_kind, :locator, presence: true
  validate :locator_is_valid

  private

  def locator_is_valid
    errors.add(:locator, "must identify a valid range") unless FileReader.valid_locator?(stored_file, representation_kind, locator)
  end
end
