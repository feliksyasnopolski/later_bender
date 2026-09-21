class RemoteWorkspacePlacement < ApplicationRecord
  belongs_to :workspace
  belongs_to :remote_agent

  STATES = %w[pending preparing ready failed cleanup_pending destroyed].freeze
  EXECUTORS = %w[native docker].freeze

  validates :executor, inclusion: { in: EXECUTORS }
  validates :state, inclusion: { in: STATES }
  validates :operation_id, :spec_hash, :spec, presence: true

  def prepare_payload
    {
      "type" => self.operation_kind == "destroy" ? "destroy_workspace" : "prepare_workspace",
      "workspace" => workspace.ref,
      "operation_id" => operation_id,
      "executor" => executor,
      "spec" => spec,
      "spec_hash" => spec_hash,
      "expires_at" => workspace.expires_at&.iso8601
    }
  end

  def replace_operation!(kind:)
    update!(operation_kind: kind, operation_id: "WSOP-#{SecureRandom.hex(16)}", state: "pending", error_message: nil)
  end
end
