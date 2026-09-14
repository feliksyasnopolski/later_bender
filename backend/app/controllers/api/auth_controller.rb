module Api
  class AuthController < BaseController
    skip_before_action :authenticate_user!, only: %i[login recover]

    def login
      user = User.find_for_database_authentication(username: request_payload["username"])
      return invalid_credentials unless user&.valid_password?(request_payload["password"].to_s)

      render_session(user)
    end

    def current
      render json: serialize_user(current_user)
    end

    def logout
      current_api_token&.revoke!
      head :no_content
    end

    def recover
      payload = request_payload
      username = payload["username"].to_s
      unless RecoveryRateLimiter.allowed?(request.remote_ip, username)
        return render json: { error: "Recovery is temporarily unavailable" }, status: :too_many_requests
      end

      user = User.find_for_database_authentication(username: username)
      credential = user&.totp_credentials&.where.not(confirmed_at: nil)&.detect { |item| item.verify(payload["code"]) }
      unless credential && payload["password"].to_s == payload["password_confirmation"].to_s
        return render json: { error: "Recovery code is invalid or recovery is unavailable" }, status: :unauthorized
      end

      user.password = payload["password"].to_s
      user.password_confirmation = payload["password_confirmation"].to_s
      return render_errors(user) unless user.save

      ApiToken.revoke_all_for!(user)
      render_session(user)
    end

    private

    def render_session(user)
      _token, raw_token = ApiToken.issue!(user: user, name: "Browser session")
      render json: { user: serialize_user(user), token: raw_token }, status: :created
    end

    def serialize_user(user)
      { id: user.id, username: user.username }
    end

    def invalid_credentials
      render json: { error: "Invalid username or password" }, status: :unauthorized
    end
  end
end
