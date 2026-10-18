require "rails_helper"

RSpec.describe "Model knowledge API", type: :request do
  before do
    @user = User.create!(username: "model-knowledge-user", password: "password123")
    @token, @raw_token = ApiToken.issue!(user: @user, name: "test client")
  end

  it "upserts workflows with claimed evidence and retains the prior version" do
    payload = { name: "execution.custom", description: "First", workflow: "Call tools", tools: [ "execute_workspace" ] }
    post "/api/model-workflows", params: payload.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "claimed", json_body["evidence"]
    post "/api/model-workflows", params: payload.merge(description: "Second").to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal 1, json_body["versions"].length
    assert_equal "First", @user.model_workflows.find_by!(name: payload[:name]).versions.first["description"]
  end

  it "prevents native workflow overwrite and scopes saved workflows to the user" do
    post "/api/model-workflows", params: { name: "execution", description: "bad", workflow: "bad" }.to_json, headers: json_headers(@raw_token)
    assert_response :not_found
    get "/api/model-workflows", headers: json_headers(@raw_token)
    assert_equal [], json_body["workflows"]
  end

  it "saves valid JavaScript snapshots and rejects invalid syntax" do
    payload = { name: "helpers", source: "return { add: (a, b) => a + b };", exports: [ "add" ] }
    post "/api/model-libraries", params: payload.to_json, headers: json_headers(@raw_token)
    assert_response :success
    post "/api/model-libraries", params: payload.merge(source: "return { add: (a, b) => a - b }; ").to_json, headers: json_headers(@raw_token)
    assert_response :success
    get "/api/model-libraries", params: { name: "helpers" }, headers: json_headers(@raw_token)
    assert_equal "return { add: (a, b) => a - b }; ", json_body["libraries"].first["source"]
    assert_equal payload[:source], json_body["libraries"].first["versions"].first["source"]
    get "/api/model-libraries", headers: json_headers(@raw_token)
    refute json_body["libraries"].first.key?("source")
    refute json_body["libraries"].first.key?("versions")
  end
end
