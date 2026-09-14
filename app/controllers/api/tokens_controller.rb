module Api
  class TokensController < BaseController
    def index
      render json: current_user.api_tokens.order(created_at: :desc).map { |token| serialize(token) }
    end

    def create
      token, raw_token = ApiToken.issue!(user: current_user, name: request_payload["name"].to_s.presence || "API client")
      render json: serialize(token).merge("token" => raw_token), status: :created
    rescue ActiveRecord::RecordInvalid => error
      render_errors(error.record)
    end

    def destroy
      token = current_user.api_tokens.find_by(id: params[:id])
      return render_not_found unless token

      token.revoke!
      head :no_content
    end

    private

    def serialize(token)
      { id: token.id, name: token.name, last_used_at: token.last_used_at, revoked_at: token.revoked_at, created_at: token.created_at }
    end
  end
end
