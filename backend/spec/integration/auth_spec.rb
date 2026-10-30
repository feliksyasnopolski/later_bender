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

  it "advertises request-bound OAuth issuer identities only for the two API hosts" do
    {
      "lb-api.felix.pp.ua" => "https://lb-api.felix.pp.ua",
      "lb-api.felixworks.top" => "https://lb-api.felixworks.top"
    }.each do |host, issuer|
      get "/.well-known/oauth-authorization-server", headers: { "HTTP_HOST" => host }
      assert_response :success
      assert_equal issuer, json_body.fetch("issuer")
      assert_equal "#{issuer}/oauth/authorize", json_body.fetch("authorization_endpoint")
      assert_equal "#{issuer}/oauth/token", json_body.fetch("token_endpoint")
      assert_equal "#{issuer}/oauth/register", json_body.fetch("registration_endpoint")
    end

    get "/.well-known/oauth-authorization-server", headers: { "HTTP_HOST" => "attacker.example" }
    assert_response :bad_request

    get "/.well-known/oauth-authorization-server", headers: {
      "HTTP_HOST" => "lb-api.felix.pp.ua", "HTTP_X_FORWARDED_HOST" => "attacker.example"
    }
    assert_response :bad_request
  end

  it "completes an authorization-code flow against each advertised issuer origin" do
    user = User.create!(username: "dual-issuer", password: "password123")
    callback = "https://client.example/callback"
    verifier = "a" * 43
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    [ "lb-api.felix.pp.ua", "lb-api.felixworks.top" ].each do |host|
      host! host
      get "/.well-known/oauth-authorization-server"
      assert_response :success
      issuer = json_body.fetch("issuer")
      assert_equal "https://#{host}", issuer
      token_endpoint = json_body.fetch("token_endpoint")

      post "/oauth/register", params: { client_name: "dual issuer test", redirect_uris: [ callback ] }.to_json, headers: json_headers
      assert_response :created
      client_id = json_body.fetch("client_id")

      post "/users/sign_in", params: { user: { username: user.username, password: "password123" } }
      assert_response :redirect
      get "/oauth/authorize", params: {
        response_type: "code", client_id: client_id, redirect_uri: callback, scope: "mcp",
        code_challenge: challenge, code_challenge_method: "S256", state: "dual-#{host}"
      }
      assert_response :redirect
      callback_uri = URI(response.location)
      assert_equal callback, "#{callback_uri.scheme}://#{callback_uri.host}#{callback_uri.path}"
      code = URI.decode_www_form(callback_uri.query).to_h.fetch("code")

      assert_equal "#{issuer}/oauth/token", token_endpoint
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, client_id: client_id,
        redirect_uri: callback, code_verifier: verifier
      }
      assert_response :success
      oauth_token = json_body.fetch("access_token")
      get "/api/auth/current", headers: json_headers(oauth_token)
      assert_response :success
      assert_equal user.id, json_body.fetch("id")
    end
  end

  it "permits native-client HTTP IP-loopback redirects with PKCE" do
    [ "http://127.0.0.1:49123/callback", "http://[::1]:49124/callback" ].each do |callback|
      post "/oauth/register", params: { client_name: "native MCP client", redirect_uris: [ callback ] }.to_json, headers: json_headers
      assert_response :created
      assert_equal [ callback ], json_body.fetch("redirect_uris")
      get "/oauth/authorize", params: { response_type: "code", client_id: json_body.fetch("client_id"),
        redirect_uri: callback, scope: "mcp", code_challenge: "challenge", code_challenge_method: "S256" }
      assert_response :redirect
      assert_includes response.location, "/users/sign_in"
    end
  end

  it "rejects non-loopback HTTP redirects and URI fragments" do
    [ "http://client.example/callback", "http://localhost:49123/callback",
      "http://127.0.0.2:49123/callback", "http://[::2]:49123/callback",
      "http://127.0.0.1:49123/callback#fragment" ].each do |callback|
      post "/oauth/register", params: { client_name: "unsafe native client", redirect_uris: [ callback ] }.to_json, headers: json_headers
      assert_response :bad_request
    end
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
