require "rails_helper"

RSpec.describe "Model knowledge API", type: :request do
  before do
    @user = User.create!(username: "model-knowledge-user", password: "password123")
    @token, @raw_token = ApiToken.issue!(user: @user, name: "test client")
  end

  it "keeps the sync source inside the backend image context and matches the canonical MCP library" do
    packaged = Rails.root.join("config/standard_library/lb.js")
    canonical = Rails.root.join("../mcp/libraries/lb.js")
    expect(packaged).to be_file
    expect(File.binread(packaged)).to eq(File.binread(canonical))
    expect(File.read(Rails.root.join("Dockerfile"))).to include("COPY . .")
    expect(File.read(Rails.root.join("../.github/workflows/publish-backend.yml"))).to include("context: backend")
    expect(File.read(Rails.root.join("lib/tasks/model_libraries.rake"))).to include('"config", "standard_library", "lb.js"')
  end

  it "upserts workflows with claimed evidence and retains the prior version" do
    payload = { name: "execution.custom", description: "First", workflow: "Call tools", tools: [ "execute_workspace" ] }
    post "/api/model-workflows", params: payload.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "claimed", json_body["evidence"]
    assert_equal 1, json_body["revision"]
    post "/api/model-workflows", params: payload.merge(description: "Second").to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal 1, json_body["versions"].length
    assert_equal "First", @user.model_workflows.find_by!(name: payload[:name]).versions.first["description"]
    assert_equal 1, @user.model_workflows.find_by!(name: payload[:name]).versions.first["revision"]
    assert_equal 2, json_body["revision"]
    post "/api/model-workflows", params: payload.merge(description: "stale", expected_revision: 1).to_json, headers: json_headers(@raw_token)
    assert_response :conflict
    assert_equal "revision_conflict", json_body.dig("error", "code")
    assert_equal "Second", @user.model_workflows.find_by!(name: payload[:name]).description
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
    assert_equal 1, json_body["revision"]
    post "/api/model-libraries", params: payload.merge(source: "return { add: (a, b) => a - b }; ").to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal 2, json_body["revision"]
    post "/api/model-libraries", params: payload.merge(source: "return {};", expected_revision: 1).to_json, headers: json_headers(@raw_token)
    assert_response :conflict
    get "/api/model-libraries", params: { name: "helpers" }, headers: json_headers(@raw_token)
    assert_equal "return { add: (a, b) => a - b }; ", json_body["libraries"].first["source"]
    assert_equal payload[:source], json_body["libraries"].first["versions"].first["source"]
    assert_equal 1, json_body["libraries"].first["versions"].first["revision"]
    get "/api/model-libraries", headers: json_headers(@raw_token)
    refute json_body["libraries"].first.key?("source")
    refute json_body["libraries"].first.key?("versions")
  end

  it "accepts a zero expected revision for creation and reports precise validation errors" do
    payload = { name: "first", source: "return {};", expected_revision: 0 }
    post "/api/model-libraries", params: payload.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal 1, json_body["revision"]
    post "/api/model-libraries", params: { name: "bad name", source: "return {};" }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal [ "is invalid" ], json_body.dig("error", "details", "name")
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
