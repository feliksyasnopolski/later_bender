module Api
  class WorkspacesController < BaseController
    require "base64"
    EXECUTION_OBSERVATION_WINDOW_SECONDS = 5.0
    REMOTE_OPERATION_OBSERVATION_WINDOW_SECONDS = 6.5
    REMOTE_EXECUTION_OBSERVATION_WINDOW_SECONDS = 2.5
    REMOTE_OBSERVATION_INTERVAL_SECONDS = 0.1
    before_action :set_workspace, only: %i[show destroy put_file read_file promote_file execute execution output cancel transcript promote_transcript]

    def capabilities
      render json: runner.request(:get, "/capabilities")
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def targets
      capabilities = runner.request(:get, "/capabilities")
      render json: { targets: [ hosted_target(capabilities), *remote_agent_targets ] }
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def index
      scope = current_user.workspaces.where.not(state: "stopping").order(:created_at, :id)
      scope = scope.where(state: params[:state]) if params[:state].present?
      render json: { workspaces: scope.limit(params.fetch(:limit, 100).to_i.clamp(1, 100)).map { |w| summary(w) }, next_cursor: nil }
    end

    def create
      payload = request_payload
      validate_target_selection!(payload)
      return create_remote_workspace(payload) if payload["target"].present? && payload["target"] != "hosted"

      refs = Array(payload["credentials"])
      raise WorkspaceRunnerClient::Unavailable.new("Credential was not found", code: "credential_not_found") if refs.length > 32 || refs.uniq.length != refs.length
      credentials = current_user.credentials.where(ref: refs).index_by(&:ref)
      raise WorkspaceRunnerClient::Unavailable.new("Credential was not found", code: "credential_not_found") unless credentials.length == refs.length
      bindings = credentials.values.map(&:metadata)
      validate_binding_conflicts!(bindings)
      injections = credentials.values.map { |credential| credential.metadata.merge("secret" => credential.secret) }
      offering = runner.request(:post, "/workspaces", payload.except("credentials", "target", "executor").merge("credential_injections" => injections))
      result = offering.fetch("workspace", offering)
      applied = Array(result["credential_injections_applied"] || offering["credential_injections_applied"])
      expected = bindings.map { |binding| binding.except("name") }.sort_by { |binding| binding["ref"] }
      unless refs.empty? || applied.map { |item| item.slice("ref", "kind", "env_name", "file_path", "file_mode") }.sort_by { |item| item["ref"] } == expected
        runner.request(:delete, "/workspaces/#{result["runner_handle"] || result["ref"]}") rescue nil
        raise WorkspaceRunnerClient::Unavailable.new("Credential injection acknowledgement was invalid", code: "credential_injection_failed")
      end
      workspace = nil
      current_user.workspaces.transaction do
        workspace = current_user.workspaces.create!(workspace_attributes(offering, payload).merge(credential_bindings: bindings))
        workspace.append_event!("workspace_created", {})
      end
      LiveEvents.publish(user: current_user, type: "workspace.updated", ref: workspace.ref)
      render json: full(workspace), status: :created
    rescue ActiveRecord::RecordInvalid
      runner.request(:delete, "/workspaces/#{offering.dig("workspace", "runner_handle") || offering.dig("workspace", "ref") || offering["runner_handle"] || offering["ref"]}") rescue nil
      raise
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def show = render json: full(@workspace)

    def destroy
      if (placement = @workspace.remote_workspace_placement)
        raise WorkspaceRunnerClient::Unavailable.new("Remote Workspace target is offline", code: "workspace_unavailable") unless placement.remote_agent.online?

        workspace_ref = @workspace.ref
        placement.replace_operation!(kind: "destroy")
        @workspace.update!(state: "stopping")
        @workspace.append_event!("workspace_destroy_requested", { "operation_id" => placement.operation_id })
        return render json: { ref: workspace_ref, destroyed: true } if wait_for_remote_destruction!(workspace_ref)

        return render json: { ref: workspace_ref, destroyed: false, state: "stopping" }, status: :accepted
      end
      runner.request(:delete, "/workspaces/#{@workspace.runner_handle}") if @workspace.runner_handle.present?
      @workspace.update!(state: "stopping")
      @workspace.destroy!
      LiveEvents.publish(user: current_user, type: "workspace.updated", ref: @workspace.ref)
      render json: { ref: @workspace.ref, destroyed: true }
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def put_file
      payload = request_payload
      file = find_file(payload.fetch("file"))
      path = payload["path"].presence || "/workspace/#{file.filename}"
      return remote_file_operation("put_file", payload.merge("path" => path, "file" => file.ref, "filename" => file.filename, "media_type" => file.media_type, "byte_size" => file.byte_size, "sha256" => file.sha256)) if @workspace.remote_workspace_placement.present?
      result = runner.request(:post, "/workspaces/#{@workspace.runner_handle}/files", payload.merge("bytes_base64" => Base64.strict_encode64(file.original.download), "filename" => file.filename, "media_type" => file.media_type))
      @workspace.append_event!("file_imported", result.merge("file" => file.ref))
      render json: result.merge("workspace" => @workspace.ref, "file" => file.ref)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def read_file
      return remote_file_operation("read_file", request_payload) if @workspace.remote_workspace_placement.present?
      render json: runner.request(:post, "/workspaces/#{@workspace.runner_handle}/file-read", request_payload).merge("workspace" => @workspace.ref)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end
    def promote_file
      payload = request_payload
      return remote_file_operation("promote_file", payload.merge("path" => workspace_relative_path(payload.fetch("path")))) if @workspace.remote_workspace_placement.present?
      promotion_payload = payload.merge("path" => workspace_relative_path(payload.fetch("path")))
      result = runner.request(:post, "/workspaces/#{@workspace.runner_handle}/file-promote", promotion_payload)
      project = current_user.projects.find_by!(slug: payload.fetch("project"))
      bytes = Base64.strict_decode64(result.fetch("bytes_base64"))
      file = StoredFileBytesCreator.call(project:, bytes:, filename: result["filename"] || payload["filename"] || File.basename(payload.fetch("path")), media_type: result["media_type"], tags: payload["tags"])
      @workspace.append_event!("file_promoted", promotion_payload.merge("file" => file.ref))
      render json: { ref: file.ref, filename: file.filename, media_type: file.media_type, byte_size: file.byte_size, sha256: file.sha256 }
    rescue ArgumentError
      render json: { error: { code: "validation_failed", message: "Invalid file bytes" } }, status: :unprocessable_content
    end

    def execute
      return execute_remote if @workspace.remote_workspace_placement.present?
      result = runner.request(:post, "/workspaces/#{@workspace.runner_handle}/executions", request_payload)
      execution = @workspace.workspace_executions.create!(execution_attributes(result))
      @workspace.append_event!("execution", transcript_execution_payload(result, execution))
      LiveEvents.publish(user: current_user, type: "workspace_execution.updated", ref: execution.ref, workspace_ref: @workspace.ref)
      observe_execution!(execution)
      render json: execution_json(execution), status: :created
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def execution
      execution = @workspace.workspace_executions.find_by!(ref: params[:execution_ref])
      refresh_execution!(execution)
      render json: execution_json(execution)
    end

    def output
      execution = @workspace.workspace_executions.find_by!(ref: params[:execution_ref])
      return render json: remote_output(execution, request_payload) if @workspace.remote_workspace_placement.present?
      render json: runner.request(:post, "/executions/#{execution.ref}/output", request_payload)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def cancel
      execution = @workspace.workspace_executions.find_by!(ref: params[:execution_ref])
      return cancel_remote(execution) if @workspace.remote_workspace_placement.present?
      previous_state = execution.state
      result = runner.request(:post, "/executions/#{execution.ref}/cancel")
      execution.update!(execution_attributes(result))
      @workspace.append_event!("execution", transcript_execution_payload(result, execution)) if previous_state != execution.state
      render json: execution_json(execution)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def transcript
      refresh_workspace_executions!
      events = @workspace.workspace_events.order(:sequence)
      render json: { workspace: @workspace.ref, events: events.map { |event| event.payload.merge("kind" => event.kind, "sequence" => event.sequence, "occurred_at" => event.occurred_at.iso8601, "workspace" => @workspace.ref) }, next_cursor: nil }
    end

    def promote_transcript
      refresh_workspace_executions!
      payload = request_payload
      from = payload["from_sequence"].to_i if payload["from_sequence"]
      to = payload["to_sequence"].to_i if payload["to_sequence"]
      events = @workspace.workspace_events.order(:sequence).select { |event| (!from || event.sequence >= from) && (!to || event.sequence <= to) }
      last_execution_events = events.each_with_object({}) do |event, last|
        next unless event.kind == "execution"

        execution_ref = event.payload["execution"] || event.payload["ref"]
        last[execution_ref] = event.sequence if execution_ref
      end
      body = events.map do |event|
        event_payload = event.payload.deep_dup
        event_payload.delete("stdout_preview")
        event_payload.delete("stderr_preview")
        lines = [ "## #{event.kind} (#{event.sequence})", "", JSON.pretty_generate(event_payload) ]
        if event.kind == "execution" && last_execution_events[event.payload["execution"] || event.payload["ref"]] == event.sequence
          execution_ref = event.payload["execution"] || event.payload["ref"]
          %w[stdout stderr].each do |stream|
            bytes = read_all_runner_output(execution_ref, stream)
            lines.concat([ "", "### #{stream}", "", "```", bytes.force_encoding("UTF-8").scrub, "```" ])
          end
        end
        lines.join("\n")
      end.join("\n\n")
      project = current_user.projects.find_by!(slug: payload.fetch("project"))
      file = StoredFileBytesCreator.call(project:, bytes: "# Workspace transcript\n\n#{body}\n".b, filename: payload["filename"].presence || "workspace-transcript.md", media_type: "text/markdown", tags: payload["tags"])
      @workspace.append_event!("transcript_promoted", "file" => file.ref)
      render json: { ref: file.ref, filename: file.filename, media_type: file.media_type, byte_size: file.byte_size, sha256: file.sha256 }
    rescue KeyError
      render json: { error: { code: "validation_failed", message: "project is required" } }, status: :unprocessable_content
    end

    def execution_by_ref
      execution = current_user.workspaces.joins(:workspace_executions).merge(WorkspaceExecution.where(ref: params[:ref])).first!.workspace_executions.find_by!(ref: params[:ref])
      @workspace = execution.workspace
      refresh_execution!(execution)
      render json: execution_json(execution)
    end

    def output_by_ref
      execution = find_execution_by_ref
      return render json: remote_output(execution, request_payload) if execution.workspace.remote_workspace_placement.present?
      render json: runner.request(:post, "/executions/#{execution.ref}/output", request_payload)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def cancel_by_ref
      execution = find_execution_by_ref
      @workspace = execution.workspace
      return cancel_remote(execution) if @workspace.remote_workspace_placement.present?
      previous_state = execution.state
      result = runner.request(:post, "/executions/#{execution.ref}/cancel")
      execution.update!(execution_attributes(result))
      @workspace.append_event!("execution", transcript_execution_payload(result, execution)) if previous_state != execution.state
      render json: execution_json(execution)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    private

    def execute_remote
      payload = request_payload
      placement = @workspace.remote_workspace_placement
      raise WorkspaceRunnerClient::Unavailable.new("Workspace is not ready", code: "workspace_not_ready") unless @workspace.state == "ready" && placement&.state == "ready"
      raise WorkspaceRunnerClient::Unavailable.new("Remote Workspace target is offline", code: "workspace_unavailable") unless placement.remote_agent.online?
      raise WorkspaceRunnerClient::Unavailable.new("Exactly one of command or argv is required", code: "invalid_invocation") unless payload.key?("command") ^ payload.key?("argv")

      invocation = payload.key?("command") ? { "kind" => "shell", "command" => payload.fetch("command") } : { "kind" => "argv", "argv" => Array(payload.fetch("argv")) }
      env = payload["env"] || {}
      secret_env = payload["secret_env"] || {}
      raise WorkspaceRunnerClient::Unavailable.new("Invalid secret environment", code: "invalid_invocation") unless secret_env.is_a?(Hash) && secret_env.keys.all? { |key| key.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) } && secret_env.values.all? { |value| value.is_a?(String) }
      cwd = payload["cwd"] || "/workspace"
      spec = { "invocation" => invocation, "cwd" => cwd, "env" => env, "secret_env_names" => secret_env.keys.map(&:to_s).sort, "stdin" => payload["stdin"], "timeout_seconds" => payload["timeout_seconds"] }
      execution = nil
      @workspace.with_lock do
        sequence = @workspace.workspace_executions.maximum(:sequence).to_i + 1
        ref = "WSE-#{SecureRandom.hex(12)}"
        operation_id = "WSOP-#{SecureRandom.hex(16)}"
        spec_hash = Digest::SHA256.hexdigest(JSON.generate(spec))
        execution = @workspace.workspace_executions.create!(ref:, sequence:, state: "running", invocation:, cwd:, env:, secret_env_names: secret_env.keys.map(&:to_s).sort, secret_env_snapshot: JSON.generate(secret_env), started_at: Time.current, requested_timeout_seconds: payload["timeout_seconds"], stdout_handle: "#{ref}:stdout", stderr_handle: "#{ref}:stderr", remote_operation_id: operation_id, spec_hash:, remote_spec: spec)
        @workspace.append_event!("execution", transcript_execution_payload(execution.attributes, execution))
      end
      observe_remote_execution!(execution)
      render json: execution_json(execution), status: :created
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def cancel_remote(execution)
      unless execution.state == "running"
        return render json: execution_json(execution)
      end
      execution.update!(cancel_operation_id: "WSOP-#{SecureRandom.hex(16)}") unless execution.cancel_operation_id.present?
      render json: execution_json(execution)
    end

    def remote_output(execution, payload)
      stream = payload["stream"].to_s
      raise WorkspaceRunnerClient::Unavailable.new("Invalid output stream", code: "invalid_range") unless %w[stdout stderr].include?(stream)
      bytes = execution.public_send("#{stream}_data").to_s.b
      offset = Integer(payload["cursor"].presence || 0)
      raise WorkspaceRunnerClient::Unavailable.new("Invalid output cursor", code: "invalid_cursor") if offset.negative? || offset > bytes.bytesize
      chunk = bytes.byteslice(offset, 64 * 1024) || "".b
      format = payload["format"].to_s
      format = "text" if format == "auto" && utf8_text?(chunk)
      format = "base64" unless %w[text base64].include?(format)
      encoded = format == "text" ? chunk.force_encoding(Encoding::UTF_8).scrub : Base64.strict_encode64(chunk)
      terminal = execution.state != "running"
      { "execution" => execution.ref, "stream" => stream, "format" => format, "data" => encoded, "chunk_byte_size" => chunk.bytesize, "total_byte_size" => bytes.bytesize, "next_cursor" => terminal && offset + chunk.bytesize >= bytes.bytesize ? nil : (offset + chunk.bytesize).to_s, "stream_complete" => terminal && offset + chunk.bytesize >= bytes.bytesize, "state" => execution.state }
    rescue ArgumentError
      raise WorkspaceRunnerClient::Unavailable.new("Invalid output cursor", code: "invalid_cursor")
    end

    def utf8_text?(bytes)
      bytes.force_encoding(Encoding::UTF_8).valid_encoding? && !bytes.include?("\x00")
    end

    def runner = (@runner ||= WorkspaceRunnerClient.new)

    def remote_file_operation(kind, payload)
      placement = @workspace.remote_workspace_placement
      raise WorkspaceRunnerClient::Unavailable.new("Workspace is not ready", code: "workspace_not_ready") unless @workspace.state == "ready" && placement&.state == "ready"
      raise WorkspaceRunnerClient::Unavailable.new("Remote Workspace target is offline", code: "workspace_unavailable") unless placement.remote_agent.online?
      spec = payload.stringify_keys
      operation = @workspace.remote_workspace_operations.create!(operation_id: "WSOP-#{SecureRandom.hex(16)}", kind:, spec_hash: Digest::SHA256.hexdigest(JSON.generate(spec)), spec:)
      observe_remote_operation(window: REMOTE_OPERATION_OBSERVATION_WINDOW_SECONDS) { operation.reload; %w[succeeded failed].include?(operation.state) }
      operation.reload
      raise WorkspaceRunnerClient::Unavailable.new(operation.error_message.presence || "Remote Workspace operation failed", code: operation.result["code"] || "workspace_unavailable") if operation.state == "failed"
      result = operation.result.merge("workspace" => @workspace.ref)
      if kind == "put_file"
        result.merge!("file" => payload["file"], "path" => payload["path"])
        @workspace.append_event!("file_imported", result.slice("file", "path", "byte_size", "sha256"))
      elsif kind == "promote_file"
        @workspace.append_event!("file_promoted", result.slice("ref", "path", "byte_size", "sha256"))
      end
      render json: result
    rescue ActiveRecord::RecordInvalid => e
      raise WorkspaceRunnerClient::Unavailable.new(e.message, code: "validation_failed")
    end

    def find_execution_by_ref = current_user.workspaces.joins(:workspace_executions).merge(WorkspaceExecution.where(ref: params[:ref])).first!.workspace_executions.find_by!(ref: params[:ref])
    def find_file(ref)
      shorthand, number = ref.to_s.split("-F", 2)
      current_user.projects.where(shorthand: shorthand.to_s.upcase).joins(:stored_files).merge(StoredFile.where(number: number)).first!.stored_files.find_by!(number: number)
    end

    def read_all_runner_output(execution_ref, stream)
      return "" if execution_ref.blank?
      result = +""
      cursor = nil
      loop do
        payload = { "stream" => stream, "format" => "base64" }
        payload["cursor"] = cursor if cursor
        chunk = runner.request(:post, "/executions/#{execution_ref}/output", payload)
        result << Base64.strict_decode64(chunk.fetch("data"))
        cursor = chunk["next_cursor"]
        break if cursor.nil?
      end
      result
    end

    def refresh_execution!(execution)
      return execution unless execution.state == "running" || execution.finished_at.nil?
      result = runner.request(:get, "/executions/#{execution.ref}")
      previous_state = execution.state
      execution.update!(execution_attributes(result))
      @workspace.append_event!("execution", transcript_execution_payload(result, execution)) if previous_state != execution.state
      execution
    rescue WorkspaceRunnerClient::Unavailable
      execution
    end
    def observe_execution!(execution)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + EXECUTION_OBSERVATION_WINDOW_SECONDS
      loop do
        result = runner.request(:get, "/executions/#{execution.ref}")
        previous_state = execution.state
        execution.update!(execution_attributes(result))
        @workspace.append_event!("execution", transcript_execution_payload(result, execution)) if previous_state != execution.state
        break unless execution.state == "running"
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.1
      end
      execution
    end
    def observe_remote_execution!(execution)
      observe_remote_operation(window: REMOTE_EXECUTION_OBSERVATION_WINDOW_SECONDS) do
        execution.reload
        execution.state != "running"
      end
      execution
    end
    def wait_for_remote_workspace!(workspace)
      observe_remote_operation do
        workspace.reload
        placement = workspace.remote_workspace_placement
        placement&.state == "ready" || placement&.state == "failed" || workspace.state == "failed"
      end
      workspace.reload
    end
    def wait_for_remote_destruction!(workspace_ref)
      observe_remote_operation do
        workspace = Workspace.uncached { Workspace.find_by(ref: workspace_ref) }
        workspace.nil? || workspace.remote_workspace_placement&.state == "destroyed"
      end
    end
    def observe_remote_operation(window: REMOTE_OPERATION_OBSERVATION_WINDOW_SECONDS)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + window
      loop do
        return true if yield
        return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        remote_observation_sleep
      end
    end
    def remote_observation_sleep = sleep(REMOTE_OBSERVATION_INTERVAL_SECONDS)
    def refresh_workspace_executions!
      @workspace.workspace_executions.where(state: "running").find_each { |execution| refresh_execution!(execution) }
    end
    def set_workspace = @workspace = current_user.workspaces.find_by_public_ref(params[:ref] || params[:workspace_ref]) || raise(ActiveRecord::RecordNotFound)

    def workspace_relative_path(path)
      path.to_s.delete_prefix("/workspace/")
    end

    def workspace_attributes(result, payload)
      result = result.fetch("workspace", result)
      { label: payload["label"], state: result.fetch("state", "ready"), environment: result.fetch("environment", payload["environment"] || "linux"), architecture: result.fetch("architecture", payload["architecture"] || "arm64"), os_name: result.dig("os", "name") || "Linux", os_version: result.dig("os", "version") || "unknown", shell: result.fetch("shell", "/bin/bash"), workspace_root: result.fetch("workspace_root", "/workspace"), limits: result.fetch("limits", {}), capabilities: result.fetch("capabilities", {}), runner_handle: result["runner_handle"] || result["ref"], last_activity_at: Time.current, expires_at: result["expires_at"] }
    end

    def create_remote_workspace(payload)
      agent = current_user.remote_agents.find_by(ref: payload.fetch("target"))
      raise WorkspaceRunnerClient::Unavailable.new("Workspace target is not available: #{payload["target"]}", code: "target_not_found") unless agent&.enabled? && agent.revoked_at.nil?
      raise WorkspaceRunnerClient::Unavailable.new("Workspace target is offline", code: "workspace_unavailable") unless agent.online?

      executor = payload["executor"].presence || "native"
      unless agent.supported_executors.include?(executor)
        raise WorkspaceRunnerClient::Unavailable.new("Executor #{executor} is not supported by #{agent.ref}", code: "executor_unsupported")
      end
      requested_architecture = payload["architecture"].presence
      if requested_architecture.present? && requested_architecture != agent.architecture
        raise WorkspaceRunnerClient::Unavailable.new("Workspace target does not satisfy the requested architecture", code: "capability_unavailable")
      end
      capabilities = Array(payload["required_capabilities"]).map(&:to_s)
      missing = capabilities.reject { |capability| agent.capabilities[capability] == true || agent.capabilities[capability].to_s == "true" }
      raise WorkspaceRunnerClient::Unavailable.new("Workspace target is missing required capabilities: #{missing.join(", ")}", code: "capability_unavailable") if missing.any?

      spec = {
        "environment" => payload["environment"].presence || agent.platform,
        "architecture" => agent.architecture,
        "resources" => payload["resources"] || {},
        "required_capabilities" => capabilities,
        "label" => payload["label"]
      }
      digest = Digest::SHA256.hexdigest(JSON.generate(spec))
      workspace = nil
      current_user.workspaces.transaction do
        workspace = current_user.workspaces.create!(
          label: payload["label"], state: "starting", environment: spec["environment"], architecture: agent.architecture,
          os_name: agent.platform, os_version: "unknown", shell: "/bin/bash", workspace_root: "/workspace",
          limits: { "cpus" => nil, "memory_bytes" => nil, "disk_bytes" => nil, "pids" => nil }, capabilities: agent.capabilities, last_activity_at: Time.current, expires_at: payload["ttl_seconds"].present? ? payload["ttl_seconds"].to_i.seconds.from_now : nil
        )
        refs = Array(payload["credentials"])
        raise WorkspaceRunnerClient::Unavailable.new("Credential was not found", code: "credential_not_found") if refs.length > 32 || refs.uniq.length != refs.length
        credentials = current_user.credentials.where(ref: refs).index_by(&:ref)
        raise WorkspaceRunnerClient::Unavailable.new("Credential was not found", code: "credential_not_found") unless credentials.length == refs.length
        bindings = credentials.values.map(&:metadata)
        validate_binding_conflicts!(bindings)
        workspace.update!(credential_bindings: bindings, credential_snapshot: JSON.generate(credentials.values.index_by(&:ref).transform_values { |credential| { "metadata" => credential.metadata, "secret" => credential.secret } }))
        spec["credential_bindings"] = bindings
        placement = workspace.create_remote_workspace_placement!(remote_agent: agent, executor:, operation_id: "WSOP-#{SecureRandom.hex(16)}", spec_hash: Digest::SHA256.hexdigest(JSON.generate(spec)), spec:)
        workspace.append_event!("workspace_created", { "target" => agent.ref, "executor" => executor, "operation_id" => placement.operation_id })
      end
      wait_for_remote_workspace!(workspace)
      render json: full(workspace), status: :created
    rescue ActiveRecord::RecordInvalid
      raise
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def validate_binding_conflicts!(bindings)
      raise WorkspaceRunnerClient::Unavailable.new("Credential conflict", code: "credential_conflict") if bindings.map { |b| b["ref"] }.uniq.length != bindings.length
      env_names = bindings.filter_map { |b| b["env_name"] }
      paths = bindings.filter_map { |b| b["file_path"] }
      if env_names.length != env_names.uniq.length || paths.length != paths.uniq.length
        raise WorkspaceRunnerClient::Unavailable.new("Credential conflict", code: "credential_conflict")
      end
    end

    def validate_target_selection!(payload)
      target = payload["target"].presence || "hosted"
      return if target != "hosted"
      return if payload["executor"].blank?

      raise WorkspaceRunnerClient::Unavailable.new("Executor #{payload["executor"]} is not supported by the hosted target", code: "executor_unsupported")
    end

    def hosted_target(capabilities)
      offering = Array(capabilities["environments"]).first || {}
      architecture = Array(offering["architectures"]).first || {}
      {
        ref: "hosted",
        kind: "hosted",
        name: "Hosted Workspace",
        availability: "available",
        last_seen_at: nil,
        platform: {
          environment: offering["environment"],
          os: architecture["os"],
          architectures: Array(offering["architectures"]).filter_map { |item| item["architecture"] }
        },
        supported_executors: [],
        resources: architecture["resources"],
        capabilities: architecture["capabilities"] || {}
      }
    end

    def remote_agent_targets
      current_user.remote_agents.where(enabled: true, revoked_at: nil).order(:public_number).map do |agent|
        {
          ref: agent.ref,
          kind: "remote_agent",
          name: agent.name,
          availability: agent.online? ? "available" : "unavailable",
          last_seen_at: agent.last_seen_at,
          platform: { environment: agent.platform, os: { name: agent.platform, version: "unknown" }, architectures: [ agent.architecture ] },
          resources: nil,
          supported_executors: agent.supported_executors,
          capabilities: agent.capabilities
        }
      end
    end

    def execution_attributes(result)
      result = result.fetch("execution", result)
      { ref: result.fetch("ref"), sequence: result.fetch("sequence", @workspace.workspace_executions.maximum(:sequence).to_i + 1), state: result.fetch("state", "running"), invocation: result.fetch("invocation", {}), cwd: result.fetch("cwd", "/workspace"), env: result.fetch("env", {}), secret_env_names: result.fetch("secret_env_names", []), started_at: result.fetch("started_at", Time.current), finished_at: result["finished_at"], exit_code: result["exit_code"], terminating_signal: result["terminating_signal"], requested_timeout_seconds: result["requested_timeout_seconds"], stdout_handle: result.fetch("stdout_handle", SecureRandom.hex(8)), stderr_handle: result.fetch("stderr_handle", SecureRandom.hex(8)) }
    end

    def transcript_execution_payload(result, execution)
      result = result.fetch("execution", result)
      { "execution" => execution.ref, "invocation" => result.fetch("invocation", execution.invocation), "cwd" => result.fetch("cwd", execution.cwd), "secret_env_names" => result.fetch("secret_env_names", execution.secret_env_names), "started_at" => result.fetch("started_at", execution.started_at), "finished_at" => result["finished_at"] || execution.finished_at, "requested_timeout_seconds" => timeout_seconds_value(result["requested_timeout_seconds"] || execution.requested_timeout_seconds), "state" => result.fetch("state", execution.state), "exit_code" => result["exit_code"] || execution.exit_code, "terminating_signal" => result["terminating_signal"] || execution.terminating_signal, "stdout_preview" => result.fetch("stdout", stream_projection(execution, :stdout)), "stderr_preview" => result.fetch("stderr", stream_projection(execution, :stderr)) }
    end

    def summary(workspace) = full(workspace).slice(:ref, :label, :state, :environment, :architecture, :created_at, :last_activity_at, :expires_at)
    def full(workspace)
      placement = workspace.remote_workspace_placement
      { ref: workspace.ref, label: workspace.label, state: workspace.state, environment: workspace.environment, architecture: workspace.architecture, os: workspace.os, shell: workspace.shell, workspace_root: workspace.workspace_root, limits: workspace.limits, capabilities: workspace.capabilities, credential_bindings: workspace.credential_bindings, created_at: workspace.created_at, last_activity_at: workspace.last_activity_at, expires_at: workspace.expires_at,
        target: placement&.remote_agent&.ref || "hosted", executor: placement&.executor, availability: placement ? (placement.remote_agent.online? ? "online" : "offline") : "available" }
    end
    def execution_json(execution) = { ref: execution.ref, workspace: @workspace.ref, sequence: execution.sequence, state: execution.state, invocation: execution.invocation, cwd: execution.cwd, env: execution.env, secret_env_names: execution.secret_env_names, started_at: execution.started_at, finished_at: execution.finished_at, exit_code: execution.exit_code, terminating_signal: execution.terminating_signal, requested_timeout_seconds: timeout_seconds_value(execution.requested_timeout_seconds), stdout: stream_projection(execution, :stdout), stderr: stream_projection(execution, :stderr) }
    def timeout_seconds_value(value) = value.nil? ? nil : value.to_f
    def stream_projection(execution, stream)
      if execution.workspace.remote_workspace_placement.present?
        result = remote_output(execution, "stream" => stream.to_s, "format" => "auto")
        return { format: result.fetch("format"), data: result.fetch("data"), total_byte_size: result.fetch("total_byte_size"), inline_complete: result.fetch("stream_complete") }
      end
      result = runner.request(:post, "/executions/#{execution.ref}/output", "stream" => stream.to_s, "format" => "auto")
      { format: result.fetch("format"), data: result.fetch("data"), total_byte_size: result.fetch("total_byte_size", result.fetch("chunk_byte_size", 0)), inline_complete: result.fetch("stream_complete", false) }
    rescue WorkspaceRunnerClient::Unavailable
      { format: "base64", data: "", total_byte_size: 0, inline_complete: false }
    end
    def render_runner_error(error)
      code = error.respond_to?(:code) && error.code.present? ? error.code : "workspace_unavailable"
      status = %w[invalid_range invalid_cursor invalid_invocation not_text path_invalid path_not_found path_exists path_not_file credential_not_found credential_conflict credential_injection_failed target_not_found executor_unsupported capability_unavailable].include?(code) ? :unprocessable_content : :service_unavailable
      render json: { error: { code:, message: error.message } }, status:
    end
  end
end
