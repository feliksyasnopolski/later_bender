class WorkspaceEventProjection
  LEGACY_KINDS = {
    "workspace_ready" => "workspace_prepared",
    "workspace_provision_failed" => "workspace_failed"
  }.freeze

  def self.call(event)
    kind = LEGACY_KINDS.fetch(event.kind, event.kind)
    payload = event.payload.deep_stringify_keys
    if kind == "execution"
      payload["execution"] ||= payload.delete("ref")
      payload["requested_timeout_seconds"] = timeout_value(payload["requested_timeout_seconds"])
    end
    payload.merge("kind" => kind, "sequence" => event.sequence, "occurred_at" => event.occurred_at.iso8601, "workspace" => event.workspace.ref)
  end

  def self.timeout_value(value)
    return nil if value.nil?

    number = Float(value)
    number.positive? && number.finite? ? number : nil
  rescue ArgumentError, TypeError
    nil
  end
  private_class_method :timeout_value
end
