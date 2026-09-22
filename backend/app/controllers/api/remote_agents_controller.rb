module Api
  class RemoteAgentsController < BaseController
    def enrollment_token
      token, raw = RemoteAgentEnrollmentToken.issue!(user: current_user)
      render json: { token: raw, expires_at: token.expires_at }, status: :created
    end

    def index
      render json: { agents: current_user.remote_agents.order(:public_number).map { |agent| projection(agent) } }
    end

    def revoke
      current_user.remote_agents.find_by!(ref: params[:ref]).revoke!
      LiveEvents.publish(user: current_user, type: "remote_agent.updated", ref: params[:ref])
      render json: { ref: params[:ref], revoked: true }
    end

    def update
      agent = current_user.remote_agents.find_by!(ref: params[:ref])
      agent.update!(name: params.require(:name).to_s.strip)
      LiveEvents.publish(user: current_user, type: "remote_agent.updated", ref: agent.ref)
      render json: { agent: projection(agent) }
    end

    private

    def projection(agent)
      { ref: agent.ref, name: agent.name, enabled: agent.enabled?, revoked: agent.revoked_at.present?, platform: agent.platform, architecture: agent.architecture, supported_executors: agent.supported_executors, capabilities: agent.capabilities, last_seen_at: agent.last_seen_at, availability: agent.online? ? "online" : "offline", created_at: agent.created_at, updated_at: agent.updated_at }
    end
  end
end
