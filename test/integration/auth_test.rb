require "test_helper"

class AuthTest < ActionDispatch::IntegrationTest
  test "logs in, manages own bearer tokens, and logs out" do
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

  test "uses confirmed TOTP for one-time password recovery" do
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
end
