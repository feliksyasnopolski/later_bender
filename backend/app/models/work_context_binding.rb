class WorkContextBinding < ApplicationRecord
  belongs_to :user
  belongs_to :work_context

  validates :actor_key, presence: true
  validates :conversation_key, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :context_matches_actor

  private

  def context_matches_actor
    return if work_context.nil? || (user_id == work_context.user_id && actor_key == work_context.actor_key)

    errors.add(:work_context, "must belong to the same authenticated actor")
  end
end
