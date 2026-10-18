class ModelWorkflow < ApplicationRecord
  belongs_to :user
  validates :name, presence: true
  validates :name, format: { with: /\A[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*\z/ }, length: { maximum: 120 }
  validates :description, :workflow, presence: true
  validates :description, length: { maximum: 2_000 }
  validates :workflow, length: { maximum: 20_000 }
  validates :evidence, inclusion: { in: %w[claimed observed verified] }
end
