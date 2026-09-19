module Api
  class WorkspacesController < BaseController
    require "base64"
    EXECUTION_OBSERVATION_WINDOW_SECONDS = 5.0
    before_action :set_workspace, only: %i[show destroy put_file read_file promote_file execute execution output cancel transcript promote_transcript]

    def capabilities
      render json: runner.request(:get, "/capabilities")
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
      offering = runner.request(:post, "/workspaces", payload)
      workspace = current_user.workspaces.create!(workspace_attributes(offering, payload))
      workspace.append_event!("workspace_created", {})
      render json: full(workspace), status: :created
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def show = render json: full(@workspace)

    def destroy
      runner.request(:delete, "/workspaces/#{@workspace.runner_handle}") if @workspace.runner_handle.present?
      @workspace.update!(state: "stopping")
      @workspace.destroy!
      render json: { ref: @workspace.ref, destroyed: true }
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def put_file
      payload = request_payload
      file = find_file(payload.fetch("file"))
      result = runner.request(:post, "/workspaces/#{@workspace.runner_handle}/files", payload.merge("bytes_base64" => Base64.strict_encode64(file.original.download), "filename" => file.filename, "media_type" => file.media_type))
      @workspace.append_event!("file_imported", result.merge("file" => file.ref))
      render json: result.merge("workspace" => @workspace.ref, "file" => file.ref)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def read_file
      render json: runner.request(:post, "/workspaces/#{@workspace.runner_handle}/file-read", request_payload).merge("workspace" => @workspace.ref)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end
    def promote_file
      payload = request_payload
      result = runner.request(:post, "/workspaces/#{@workspace.runner_handle}/file-promote", payload)
      project = current_user.projects.find_by!(slug: payload.fetch("project"))
      bytes = Base64.strict_decode64(result.fetch("bytes_base64"))
      file = StoredFileBytesCreator.call(project:, bytes:, filename: result["filename"] || payload["filename"] || File.basename(payload.fetch("path")), media_type: result["media_type"], tags: payload["tags"])
      @workspace.append_event!("file_promoted", payload.merge("file" => file.ref, "path" => payload.fetch("path")))
      render json: { ref: file.ref, filename: file.filename, media_type: file.media_type, byte_size: file.byte_size, sha256: file.sha256 }
    rescue ArgumentError
      render json: { error: { code: "validation_failed", message: "Invalid file bytes" } }, status: :unprocessable_content
    end

    def execute
      result = runner.request(:post, "/workspaces/#{@workspace.runner_handle}/executions", request_payload)
      execution = @workspace.workspace_executions.create!(execution_attributes(result))
      @workspace.append_event!("execution", transcript_execution_payload(result, execution))
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
      render json: runner.request(:post, "/executions/#{execution.ref}/output", request_payload)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def cancel
      execution = @workspace.workspace_executions.find_by!(ref: params[:execution_ref])
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
      render json: runner.request(:post, "/executions/#{execution.ref}/output", request_payload)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    def cancel_by_ref
      execution = find_execution_by_ref
      @workspace = execution.workspace
      previous_state = execution.state
      result = runner.request(:post, "/executions/#{execution.ref}/cancel")
      execution.update!(execution_attributes(result))
      @workspace.append_event!("execution", transcript_execution_payload(result, execution)) if previous_state != execution.state
      render json: execution_json(execution)
    rescue WorkspaceRunnerClient::Unavailable => e
      render_runner_error(e)
    end

    private

    def runner = (@runner ||= WorkspaceRunnerClient.new)
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
    def refresh_workspace_executions!
      @workspace.workspace_executions.where(state: "running").find_each { |execution| refresh_execution!(execution) }
    end
    def set_workspace = @workspace = current_user.workspaces.find_by_public_ref(params[:ref] || params[:workspace_ref]) || raise(ActiveRecord::RecordNotFound)

    def workspace_attributes(result, payload)
      result = result.fetch("workspace", result)
      { label: payload["label"], state: result.fetch("state", "ready"), environment: result.fetch("environment", payload["environment"] || "linux"), architecture: result.fetch("architecture", payload["architecture"] || "arm64"), os_name: result.dig("os", "name") || "Linux", os_version: result.dig("os", "version") || "unknown", shell: result.fetch("shell", "/bin/bash"), workspace_root: result.fetch("workspace_root", "/workspace"), limits: result.fetch("limits", {}), capabilities: result.fetch("capabilities", {}), runner_handle: result["runner_handle"] || result["ref"], last_activity_at: Time.current, expires_at: result["expires_at"] }
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
    def full(workspace) = { ref: workspace.ref, label: workspace.label, state: workspace.state, environment: workspace.environment, architecture: workspace.architecture, os: workspace.os, shell: workspace.shell, workspace_root: workspace.workspace_root, limits: workspace.limits, capabilities: workspace.capabilities, created_at: workspace.created_at, last_activity_at: workspace.last_activity_at, expires_at: workspace.expires_at }
    def execution_json(execution) = { ref: execution.ref, workspace: @workspace.ref, sequence: execution.sequence, state: execution.state, invocation: execution.invocation, cwd: execution.cwd, env: execution.env, secret_env_names: execution.secret_env_names, started_at: execution.started_at, finished_at: execution.finished_at, exit_code: execution.exit_code, terminating_signal: execution.terminating_signal, requested_timeout_seconds: timeout_seconds_value(execution.requested_timeout_seconds), stdout: stream_projection(execution, :stdout), stderr: stream_projection(execution, :stderr) }
    def timeout_seconds_value(value) = value.nil? ? nil : value.to_f
    def stream_projection(execution, stream)
      result = runner.request(:post, "/executions/#{execution.ref}/output", "stream" => stream.to_s, "format" => "auto")
      { format: result.fetch("format"), data: result.fetch("data"), total_byte_size: result.fetch("total_byte_size", result.fetch("chunk_byte_size", 0)), inline_complete: result.fetch("stream_complete", false) }
    rescue WorkspaceRunnerClient::Unavailable
      { format: "base64", data: "", total_byte_size: 0, inline_complete: false }
    end
    def render_runner_error(error)
      code = error.respond_to?(:code) && error.code.present? ? error.code : "workspace_unavailable"
      status = %w[invalid_range invalid_cursor not_text path_invalid path_not_found path_exists path_not_file].include?(code) ? :unprocessable_content : :service_unavailable
      render json: { error: { code:, message: error.message } }, status:
    end
  end
end
