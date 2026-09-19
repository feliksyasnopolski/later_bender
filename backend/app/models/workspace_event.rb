class WorkspaceEvent < ApplicationRecord
  belongs_to :workspace
  validates :sequence, :kind, :occurred_at, presence: true
end
