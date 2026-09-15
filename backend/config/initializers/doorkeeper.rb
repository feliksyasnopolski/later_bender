Doorkeeper.configure do
  orm :active_record
  resource_owner_authenticator { |*| User.find(request.session["warden.user.user.key"].first.first) }

  grant_flows %w[authorization_code refresh_token]
  force_pkce
  default_scopes :mcp
  optional_scopes :mcp
  access_token_expires_in 30.days
  use_refresh_token true
  skip_authorization { |_resource_owner, _client| true }
  base_controller "ApplicationController"
  handle_auth_errors :raise
end
