require "rails_helper"

RSpec.describe "Auth API", type: :request do
  it "logs in, manages own bearer tokens, and logs out" do
    User.create!(username: "Alice", password: "password123")

    post "/api/auth/login", params: { username: "alice", password: "password123" }.to_json, headers: json_headers
    assert_response :created
    session_token = json_body.fetch("token")
    assert_not_includes json_body.to_json, ApiToken.last.token_digest

    get "/api/tokens", headers: json_headers(session_token)
    assert_response :success
    assert_equal [ "Browser session" ], json_body.map { |token| token["name"] }

    post "/api/tokens", params: { name: "connector" }.to_json, headers: json_headers(session_token)
    assert_response :created
    raw_token = json_body.fetch("token")
    token_id = json_body.fetch("id")
    assert_not_includes json_body.to_json, ApiToken.find(token_id).token_digest

    delete "/api/tokens/#{token_id}", headers: json_headers(session_token)
    assert_response :no_content
    get "/api/auth/current", headers: json_headers(raw_token)
    assert_response :unauthorized

    delete "/api/auth/logout", headers: json_headers(session_token)
    assert_response :no_content
    assert_nil ApiToken.authenticate(session_token)
  end

  it "uses confirmed TOTP for one-time password recovery" do
    user = User.create!(username: "recoverable", password: "password123")
    _session, old_token = ApiToken.issue!(user: user, name: "old")
    credential = user.totp_credentials.create!(secret: ROTP::Base32.random, confirmed_at: Time.current)
    code = ROTP::TOTP.new(credential.secret).at(Time.current)

    post "/api/auth/recover", params: { username: "recoverable", code: code, password: "newpassword", password_confirmation: "newpassword" }.to_json, headers: json_headers
    assert_response :created
    fresh_token = json_body.fetch("token")
    assert_nil ApiToken.authenticate(old_token)
    assert User.find(user.id).valid_password?("newpassword")

    post "/api/auth/recover", params: { username: "recoverable", code: code, password: "anotherpass", password_confirmation: "anotherpass" }.to_json, headers: json_headers
    assert_response :unauthorized
    get "/api/auth/current", headers: json_headers(fresh_token)
    assert_response :success
  end

  it "accepts a valid Doorkeeper bearer token through the existing API" do
    user = User.create!(username: "oauth-api", password: "password123")
    application = Doorkeeper::Application.create!(name: "MCP API test", redirect_uri: "https://client.example/callback", confidential: false, scopes: "mcp")
    oauth_token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: "mcp", expires_in: 30.days.to_i)

    get "/api/auth/current", headers: json_headers(oauth_token.token)
    assert_response :success
    assert_equal user.id, json_body.fetch("id")
  end

  it "redirects an unauthenticated OAuth authorization request to login" do
    payload = {
      client_name: "MCP authorization test",
      redirect_uris: [ "https://chatgpt.com/connector/oauth/test" ],
      grant_types: [ "authorization_code", "refresh_token" ],
      response_types: [ "code" ],
      token_endpoint_auth_method: "none",
      scope: "mcp"
    }
    post "/oauth/register", params: payload.to_json, headers: json_headers
    assert_response :created
    client_id = json_body.fetch("client_id")

    get "/oauth/authorize", params: {
      response_type: "code",
      client_id: client_id,
      redirect_uri: "https://chatgpt.com/connector/oauth/test",
      scope: "mcp",
      code_challenge: "challenge",
      code_challenge_method: "S256"
    }
    assert_response :redirect
    assert_includes response.location, "/users/sign_in"
  end

  it "returns to OAuth authorization after web login" do
    user = User.create!(username: "oauth-login", password: "password123")
    payload = {
      client_name: "MCP callback test",
      redirect_uris: [ "https://chatgpt.com/connector/oauth/callback" ],
      grant_types: [ "authorization_code", "refresh_token" ],
      response_types: [ "code" ],
      token_endpoint_auth_method: "none",
      scope: "mcp"
    }
    post "/oauth/register", params: payload.to_json, headers: json_headers
    client_id = json_body.fetch("client_id")
    authorization_params = {
      response_type: "code", client_id: client_id,
      redirect_uri: "https://chatgpt.com/connector/oauth/callback", scope: "mcp",
      code_challenge: "challenge", code_challenge_method: "S256", state: "state-123"
    }

    get "/oauth/authorize", params: authorization_params
    assert_response :redirect
    assert_includes response.location, "/users/sign_in"

    post "/users/sign_in", params: { user: { username: user.username, password: "password123" } }
    assert_response :redirect
    assert_match %r{/oauth/authorize\?}, response.location

    get URI(response.location).request_uri
    assert_response :redirect
    assert_match %r{https?://chatgpt\.com/connector/oauth/callback\?code=}, response.location
    assert_includes response.location, "state=state-123"
  end
end
