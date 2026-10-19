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

  it "deletes exact saved names only within the authenticated user's ownership" do
    workflow = @user.model_workflows.create!(name: "execution.custom", description: "Custom", workflow: "Call tools")
    library = @user.model_libraries.create!(name: "helpers", source: "return {};")
    other = User.create!(username: "other-model-knowledge-user", password: "password123")
    other.model_libraries.create!(name: "other", source: "return {};")

    delete "/api/model-workflows?name=#{workflow.name}", headers: json_headers(@raw_token)
    assert_response :no_content
    expect { @user.model_workflows.find(workflow.id) }.to raise_error(ActiveRecord::RecordNotFound)

    delete "/api/model-libraries?name=#{library.name}", headers: json_headers(@raw_token)
    assert_response :no_content
    expect { @user.model_libraries.find(library.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(other.model_libraries.find_by!(name: "other")).to be_present

    delete "/api/model-libraries?name=other", headers: json_headers(@raw_token)
    assert_response :not_found
    expect(other.model_libraries.find_by!(name: "other")).to be_present
  end

  it "returns validation details for invalid deletion names and cannot delete native workflows" do
    delete "/api/model-workflows?name=native.execution", headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    expect(json_body.dig("error", "code")).to eq("validation_failed")
    expect(json_body.dig("error", "details", "name")).to include("is reserved")

    delete "/api/model-libraries?name=..%2Fhelpers", headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    expect(json_body.dig("error", "details", "name")).to be_present
  end
end
