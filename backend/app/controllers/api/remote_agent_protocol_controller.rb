module Api
  class RemoteAgentProtocolController < ActionController::API
    require "base64"
    before_action :set_session, only: %i[heartbeat operations operation_result]

    def enroll
      payload = request_payload
      token = RemoteAgentEnrollmentToken.find_by(token_digest: RemoteAgentEnrollmentToken.digest(payload.fetch("enrollment_token")))
      raise ActiveRecord::RecordNotFound unless token

      attributes = normalized_advertisement(payload)
      public_key = decode_public_key(payload.fetch("public_key"))
      agent = nil
      token.transaction do
        token.consume!
        agent = token.user.remote_agents.create!(attributes.merge(public_key: public_key))
      end
      render json: { ref: agent.ref, name: agent.name, platform: agent.platform, architecture: agent.architecture, supported_executors: agent.supported_executors, capabilities: agent.capabilities }, status: :created
    rescue KeyError, ArgumentError, ActiveRecord::RecordInvalid
      render json: { error: { code: "validation_failed", message: "Invalid enrollment" } }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotFound
      render json: { error: { code: "enrollment_invalid", message: "Enrollment token is invalid or expired" } }, status: :unprocessable_content
    end

    def challenge
      agent = RemoteAgent.find_by!(ref: request_payload.fetch("agent"))
      reject_agent!(agent)
      nonce = SecureRandom.hex(32)
      challenge = RemoteAgentChallenge.issue!(remote_agent: agent, nonce:)
      render json: { challenge_id: challenge.challenge_id, nonce:, expires_at: challenge.expires_at, signed_bytes: RemoteAgentCrypto.signed_bytes(agent.ref, challenge.challenge_id, nonce, challenge.expires_at) }
    rescue KeyError
      render json: { error: { code: "validation_failed", message: "agent is required" } }, status: :unprocessable_content
    end

    def authenticate
      payload = request_payload
      agent = RemoteAgent.find_by!(ref: payload.fetch("agent"))
      reject_agent!(agent)
      challenge = agent.remote_agent_challenges.find_by!(challenge_id: payload.fetch("challenge_id"))
      nonce = payload.fetch("nonce")
      raise RemoteAgentCrypto::InvalidSignature unless Digest::SHA256.hexdigest(nonce) == challenge.nonce_digest

      challenge.consume!
      RemoteAgentCrypto.verify!(agent.public_key, payload.fetch("signature"), RemoteAgentCrypto.signed_bytes(agent.ref, challenge.challenge_id, nonce, challenge.expires_at))
      agent.remote_agent_sessions.where(disconnected_at: nil).update_all(disconnected_at: Time.current, updated_at: Time.current)
      session, raw = RemoteAgentSession.issue!(remote_agent: agent)
      agent.update!(last_seen_at: Time.current)
      render json: { session_token: raw, ref: agent.ref, connected_at: session.connected_at, heartbeat_interval_seconds: 30 }
    rescue KeyError, ActiveRecord::RecordNotFound, RemoteAgentCrypto::InvalidSignature
      render json: { error: { code: "authentication_failed", message: "Agent authentication failed" } }, status: :unauthorized
    end

    def heartbeat
      payload = request_payload
      advertisement = normalized_advertisement(payload)
      @session.heartbeat!(**advertisement.except(:name))
      render json: { ref: @session.remote_agent.ref, last_seen_at: @session.reload.last_heartbeat_at, availability: "online" }
    rescue KeyError, ActiveRecord::RecordInvalid
      render json: { error: { code: "validation_failed", message: "Invalid heartbeat" } }, status: :unprocessable_content
    end

    def operations
      operations = @session.remote_agent.remote_workspace_placements
        .where(state: %w[pending preparing]).includes(:workspace).order(:created_at)
      operations.each { |placement| placement.update!(state: "preparing") if placement.state == "pending" }
      render json: { operations: operations.map(&:prepare_payload) }
    end

    def operation_result
      placement = @session.remote_agent.remote_workspace_placements.find_by!(operation_id: params[:operation_id])
      payload = request_payload
      raise ArgumentError unless payload.fetch("operation_id") == placement.operation_id
      raise ArgumentError unless payload.fetch("workspace") == placement.workspace.ref
      raise ArgumentError unless payload.fetch("spec_hash") == placement.spec_hash

      case payload.fetch("status")
      when "prepared"
        placement.with_lock do
          placement.update!(state: "ready", provider_workspace_ref: printable_value(payload["provider_workspace_ref"], 200), prepared_at: placement.prepared_at || Time.current)
          placement.workspace.update!(state: "ready", last_activity_at: Time.current)
          placement.workspace.append_event!("workspace_prepared", {}) unless placement.workspace.workspace_events.exists?(kind: "workspace_prepared")
        end
      when "failed"
        message = printable_value(payload.fetch("message"), 500)
        placement.with_lock do
          placement.update!(state: "failed", error_message: message)
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
      render json: { operation_id: placement.operation_id, workspace: placement.workspace.ref, state: placement.state }
    rescue KeyError, ArgumentError, ActiveRecord::RecordInvalid
      render json: { error: { code: "validation_failed", message: "Invalid Workspace operation result" } }, status: :unprocessable_content
    rescue ActiveRecord::RecordNotFound
      render json: { error: { code: "operation_not_found", message: "Workspace operation was not found" } }, status: :not_found
    end

    private

    def request_payload
      return JSON.parse(request.raw_post) if request.content_mime_type == Mime[:json]

      params.to_unsafe_h
    end

    def set_session
      @session = RemoteAgentSession.authenticate(request.headers["Authorization"].to_s.delete_prefix("Bearer "))
      return if @session&.remote_agent&.enabled? && @session.remote_agent.revoked_at.nil?

      render json: { error: { code: "authentication_required", message: "Authenticated Agent session required" } }, status: :unauthorized
    end

    def reject_agent!(agent)
      raise ActiveRecord::RecordNotFound unless agent.enabled? && agent.revoked_at.nil?
    end

    def decode_public_key(value)
      bytes = Base64.strict_decode64(value.to_s)
      raise ArgumentError unless bytes.bytesize == Ed25519::KEY_SIZE

      Base64.strict_encode64(Ed25519::VerifyKey.new(bytes).to_bytes)
    rescue ArgumentError, TypeError
      raise ArgumentError
    end

    def normalized_advertisement(payload)
      platform = payload.fetch("platform").to_s
      architecture = payload.fetch("architecture").to_s
      executors = Array(payload.fetch("supported_executors")).map(&:to_s).uniq
      capabilities = payload.fetch("capabilities", {})
      raise ArgumentError unless platform.match?(/\A[[:print:]]{1,80}\z/) && architecture.match?(/\A[[:print:]]{1,80}\z/)
      raise ArgumentError unless executors.length <= 2 && (executors - RemoteAgent::EXECUTORS).empty?
      raise ArgumentError unless capabilities.is_a?(Hash) && capabilities.length <= 32 && capabilities.all? { |key, value| key.to_s.match?(/\A[a-z0-9_.-]{1,64}\z/) && (value == true || value == false || value.is_a?(String) && value.bytesize <= 200) }

      { name: payload.fetch("name").to_s.match?(/\A[[:print:]]{1,120}\z/) ? payload.fetch("name").to_s : (raise ArgumentError), platform:, architecture:, supported_executors: executors, capabilities: }
    end

    def printable_value(value, max)
      return nil if value.nil?
      value = value.to_s
      raise ArgumentError unless value.match?("\\A[[:print:]]{1,#{max}}\\z")
      value
    end
  end
end
