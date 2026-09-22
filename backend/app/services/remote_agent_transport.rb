class RemoteAgentTransport
  def self.operations(session)
    agent = current_agent!(session)
    placements = agent.remote_workspace_placements
      .where(state: %w[pending preparing]).includes(:workspace).order(:created_at)
    placements.each { |placement| placement.update!(state: "preparing") if placement.state == "pending" }
    executions = WorkspaceExecution.joins(workspace: :remote_workspace_placement)
      .where(remote_workspace_placements: { remote_agent_id: agent.id }, state: "running")
      .includes(workspace: :remote_workspace_placement).order(:created_at)
    data_operations = RemoteWorkspaceOperation.joins(workspace: :remote_workspace_placement)
      .where(remote_workspace_placements: { remote_agent_id: agent.id }, state: %w[pending running]).includes(:workspace).order(:created_at)
    {
      "operations" => placements.map(&:prepare_payload) + data_operations.map { |operation|
        operation.update!(state: "running") if operation.state == "pending"
        { "type" => operation.kind, "workspace" => operation.workspace.ref, "operation_id" => operation.operation_id, "spec_hash" => operation.spec_hash, "spec" => operation.spec }
      } + executions.map { |execution|
        placement = execution.workspace.remote_workspace_placement
        execution.cancel_operation_id.present? ? placement.cancel_payload(execution) : placement.execution_payload(execution)
      }
    }
  end

  def self.heartbeat(session, advertisement)
    current_agent!(session)
    session.heartbeat!(**advertisement.except(:name))
    { "ref" => session.remote_agent.ref, "last_seen_at" => session.reload.last_heartbeat_at, "availability" => "online" }
  end

  def self.result(session, operation_id, payload)
    agent = current_agent!(session)
    raise ArgumentError unless payload.fetch("operation_id") == operation_id

    placement = agent.remote_workspace_placements.find_by(operation_id:)
    if placement
      raise ArgumentError unless payload.fetch("workspace") == placement.workspace.ref
      raise ArgumentError unless payload.fetch("spec_hash") == placement.spec_hash
      apply_placement_result!(placement, payload)
      return { "operation_id" => operation_id, "workspace" => placement.workspace.ref, "state" => placement.state }
    end

    remote_operation = RemoteWorkspaceOperation.joins(workspace: :remote_workspace_placement)
      .where(operation_id:, remote_workspace_placements: { remote_agent_id: agent.id }).first
    if remote_operation
      raise ArgumentError unless payload.fetch("workspace") == remote_operation.workspace.ref
      raise ArgumentError unless payload.fetch("spec_hash") == remote_operation.spec_hash
      result = payload.except("operation_id", "workspace", "spec_hash", "status")
      result["range"] = JSON.parse(result.delete("range_json")) if result["range_json"]
      remote_operation.update!(state: payload.fetch("status") == "failed" ? "failed" : "succeeded", result:, error_message: payload["message"])
      return { "operation_id" => operation_id, "workspace" => remote_operation.workspace.ref, "state" => remote_operation.state }
    end

    execution = WorkspaceExecution.joins(workspace: :remote_workspace_placement)
      .where(remote_operation_id: operation_id, remote_workspace_placements: { remote_agent_id: agent.id }).first ||
      WorkspaceExecution.joins(workspace: :remote_workspace_placement)
        .where(cancel_operation_id: operation_id, remote_workspace_placements: { remote_agent_id: agent.id }).first
    raise ActiveRecord::RecordNotFound unless execution
    raise ArgumentError unless payload.fetch("workspace") == execution.workspace.ref
    raise ArgumentError unless payload.fetch("execution") == execution.ref
    raise ArgumentError unless payload.fetch("spec_hash") == execution.spec_hash
    apply_execution_result!(execution, payload)
    { "operation_id" => operation_id, "workspace" => execution.workspace.ref, "execution" => execution.ref, "state" => execution.state }
  end

  def self.current_agent!(session)
    session.reload
    agent = session.remote_agent
    raise SecurityError unless session.disconnected_at.nil? && agent.enabled? && agent.revoked_at.nil? && session.generation == agent.session_generation
    agent
  end

  def self.apply_placement_result!(placement, payload)
    case payload.fetch("status")
    when "prepared"
      placement.with_lock do
        placement.update!(state: "ready", provider_workspace_ref: printable_value(payload["provider_workspace_ref"], 200), prepared_at: placement.prepared_at || Time.current)
        placement.workspace.update!(state: "ready", last_activity_at: Time.current)
        placement.workspace.append_event!("workspace_prepared", {}) unless placement.workspace.workspace_events.exists?(kind: "workspace_prepared")
      end
    when "failed"
      placement.with_lock do
        placement.update!(state: "failed", error_message: printable_value(payload.fetch("message"), 500))
        placement.workspace.update!(state: "failed", last_activity_at: Time.current)
      end
    when "destroyed"
      raise ArgumentError unless placement.operation_kind == "destroy"
      placement.with_lock do
        placement.update!(state: "destroyed", prepared_at: nil)
        placement.workspace.destroy!
      end
    else
      raise ArgumentError
    end
  end

  def self.apply_execution_result!(execution, payload)
    status = payload.fetch("status")
    return if execution.state != "running" && status != "running"
    execution.stdout_data = bounded_output(payload["stdout_base64"]) if payload["stdout_base64"]
    execution.stderr_data = bounded_output(payload["stderr_base64"]) if payload["stderr_base64"]
    execution.finished_at = Time.current if %w[exited timed_out cancelled failed lost].include?(status)
    execution.state = status == "failed" ? "failed_to_start" : status if %w[running exited timed_out cancelled failed lost].include?(status)
    execution.exit_code = payload["exit_code"] if payload.key?("exit_code")
    execution.terminating_signal = printable_value(payload["terminating_signal"], 80) if payload.key?("terminating_signal")
    changed = execution.state_changed?
    execution.save!
    return unless changed
    execution.workspace.append_event!("execution", {
      "execution" => execution.ref, "invocation" => execution.invocation, "cwd" => execution.cwd,
      "secret_env_names" => execution.secret_env_names, "started_at" => execution.started_at,
      "finished_at" => execution.finished_at, "requested_timeout_seconds" => execution.requested_timeout_seconds,
      "state" => execution.state, "exit_code" => execution.exit_code, "terminating_signal" => execution.terminating_signal,
      "stdout_preview" => { "format" => "base64", "data" => "", "total_byte_size" => execution.stdout_data.to_s.bytesize, "inline_complete" => execution.state != "running" },
      "stderr_preview" => { "format" => "base64", "data" => "", "total_byte_size" => execution.stderr_data.to_s.bytesize, "inline_complete" => execution.state != "running" }
    })
  end

  def self.bounded_output(value)
    decoded = Base64.strict_decode64(value.to_s)
    decoded.byteslice(0, WorkspaceExecution::MAX_REMOTE_OUTPUT_BYTES)
  rescue ArgumentError
    raise ArgumentError
  end

  def self.printable_value(value, max)
    return nil if value.nil?
    value = value.to_s
    raise ArgumentError unless value.match?("\\A[[:print:]]{1,#{max}}\\z")
    value
  end

  private_class_method :apply_placement_result!, :apply_execution_result!, :bounded_output, :printable_value
end
