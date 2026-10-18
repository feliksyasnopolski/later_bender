class ModelLibrary < ApplicationRecord
  belongs_to :user
  validates :name, presence: true
  validates :name, format: { with: /\A[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*\z/ }, length: { maximum: 120 }
  validates :source, presence: true, length: { maximum: 100_000 }
  validates :description, length: { maximum: 2_000 }, allow_nil: true
end
