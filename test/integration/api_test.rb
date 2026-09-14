require "test_helper"

class ApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "test-user", password: "password123")
    @token, @raw_token = ApiToken.issue!(user: @user, name: "test client")
    @project = @user.projects.create!(name: "Writing", slug: "writing")
    @other_project = @user.projects.create!(name: "Other", slug: "other")
  end

  test "rejects missing and revoked bearer tokens" do
    get "/api/projects", headers: json_headers
    assert_response :unauthorized

    @token.update!(revoked_at: Time.current)
    get "/api/projects", headers: json_headers(@raw_token)
    assert_response :unauthorized
  end

  test "creates a project through the authenticated API" do
    post "/api/projects", params: { name: "New Project", description: "A backlog" }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    assert_equal "new-project", json_body["slug"]
  end

  test "creates a task with tags and replaces tags on update" do
    post "/api/projects/writing/tasks", params: {
      title: "Ship API", status: "backlog", priority: "high", tags: [ "Rails", "deployment" ]
    }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    assert_equal %w[deployment rails], json_body["tags"]
    assert_equal 2, Tag.count

    task_id = json_body["id"]
    patch "/api/projects/writing/tasks/#{task_id}", params: { tags: [ "auth" ] }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ "auth" ], json_body["tags"]
    assert_equal 3, Tag.count
    assert_equal [ "auth" ], Task.find(task_id).tags.pluck(:name)
  end

  test "nested listing is project scoped and global search filters tasks" do
    @project.tasks.create!(title: "Find this prose", status: "ready", context: "important writing")
    @other_project.tasks.create!(title: "Do not leak", status: "ready")

    get "/api/projects/writing/tasks", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ "Find this prose" ], json_body.map { |task| task["title"] }

    get "/api/tasks", params: { project: "writing", q: "important" }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ "Find this prose" ], json_body.map { |task| task["title"] }
  end

  test "returns structured validation errors" do
    post "/api/projects/writing/tasks", params: { title: "", status: "later" }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "validation_failed", json_body.dig("error", "code")
    assert json_body.dig("error", "details", "status")
  end

  test "does not allow a nested route to reach another project's task" do
    task = @other_project.tasks.create!(title: "Private", status: "backlog")
    get "/api/projects/writing/tasks/#{task.id}", headers: json_headers(@raw_token)
    assert_response :not_found
  end
end
