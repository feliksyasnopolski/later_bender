module Api
  class OauthController < BaseController
    def token_info
      return render json: { error: "Authentication required" }, status: :unauthorized unless current_oauth_token

      render json: { active: current_oauth_token.accessible?, user_id: current_user.id, client_id: current_oauth_token.application.uid, scope: current_oauth_token.scopes.to_s, exp: current_oauth_token.expires_at.to_i }
    end
  end
end
