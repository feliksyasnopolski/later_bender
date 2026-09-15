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

  test "reuses an existing tag when creating a task" do
    Tag.create!(name: "deployment", slug: "deployment")

    post "/api/projects/writing/tasks", params: {
      title: "Reuse tag", status: "backlog", tags: [ "deployment" ]
    }.to_json, headers: json_headers(@raw_token)

    assert_response :created
    assert_equal [ "deployment" ], json_body["tags"]
    assert_equal 1, Tag.count
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

  test "gets and updates an owned task by global id and keeps task lists compact" do
    task = @project.tasks.create!(title: "Detailed task", status: "backlog", context: "Long context that belongs only in exact reads")

    get "/api/tasks/#{task.id}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "Long context that belongs only in exact reads", json_body["context"]

    patch "/api/tasks/#{task.id}", params: { status: "doing" }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "doing", json_body["status"]

    get "/api/projects/writing/tasks", params: { summary: true }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "Detailed task", json_body.first["title"]
    assert_nil json_body.first["context"]
  end

  test "creates, lists, reads, and updates global and project notes" do
    post "/api/notes", params: { title: "Decision", body: "Keep the API boring", tags: [ "Context" ] }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    global_id = json_body["id"]
    assert_nil json_body["project"]
    assert_equal [ "context" ], json_body["tags"]

    post "/api/projects/writing/notes", params: { title: "Idea", body: "A project detail" }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    project_id = json_body["id"]
    assert_equal "writing", json_body.dig("project", "slug")

    get "/api/notes", params: { projectless: true }, headers: json_headers(@raw_token)
    assert_equal [ global_id ], json_body.map { |note| note["id"] }
    get "/api/projects/writing/notes", headers: json_headers(@raw_token)
    assert_equal [ project_id ], json_body.map { |note| note["id"] }

    patch "/api/notes/#{global_id}", params: { title: "Updated", project: "writing", tags: [] }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "Updated", json_body["title"]
    assert_equal "writing", json_body.dig("project", "slug")
    assert_equal [], json_body["tags"]
    patch "/api/notes/#{global_id}", params: { project: nil }.to_json, headers: json_headers(@raw_token)
    assert_nil json_body["project"]
  end

  test "does not expose another user's notes or permit cross-user task relations" do
    other = User.create!(username: "other-user", password: "password123")
    other_project = other.projects.create!(name: "Private", slug: "private")
    other_note = other.notes.create!(title: "Private note", body: "Secret", project: other_project)
    other_task = other_project.tasks.create!(title: "Private task", status: "backlog")

    get "/api/notes/#{other_note.id}", headers: json_headers(@raw_token)
    assert_response :not_found
    patch "/api/notes/#{other_note.id}", params: { title: "Nope" }.to_json, headers: json_headers(@raw_token)
    assert_response :not_found

    get "/api/tasks/#{other_task.id}", headers: json_headers(@raw_token)
    assert_response :not_found
    patch "/api/tasks/#{other_task.id}", params: { title: "Nope" }.to_json, headers: json_headers(@raw_token)
    assert_response :not_found

    post "/api/projects/writing/tasks", params: { title: "Relate", status: "backlog", related_note_ids: [ other_note.id ] }.to_json, headers: json_headers(@raw_token)
    assert_response :not_found
    assert_empty other_task.notes
  end

  test "task related notes replace, clear, and preserve predictably" do
    first = @user.notes.create!(title: "First", body: "One")
    second = @user.notes.create!(title: "Second", body: "Two")
    post "/api/projects/writing/tasks", params: { title: "Relate", status: "backlog", related_note_ids: [ first.id, second.id ] }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    task_id = json_body["id"]
    assert_equal [ first.id, second.id ], json_body["related_note_ids"]

    patch "/api/projects/writing/tasks/#{task_id}", params: { title: "Changed", related_note_ids: [ second.id ] }.to_json, headers: json_headers(@raw_token)
    assert_equal [ second.id ], json_body["related_note_ids"]
    patch "/api/projects/writing/tasks/#{task_id}", params: { title: "Changed again" }.to_json, headers: json_headers(@raw_token)
    assert_equal [ second.id ], json_body["related_note_ids"]
    patch "/api/projects/writing/tasks/#{task_id}", params: { related_note_ids: [] }.to_json, headers: json_headers(@raw_token)
    assert_equal [], json_body["related_note_ids"]
  end
end
