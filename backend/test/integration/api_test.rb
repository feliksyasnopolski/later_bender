require "test_helper"

class ApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "test-user", password: "password123")
    @token, @raw_token = ApiToken.issue!(user: @user, name: "test client")
    @project = @user.projects.create!(name: "Writing", slug: "writing", shorthand: "WR")
    @other_project = @user.projects.create!(name: "Other", slug: "other", shorthand: "OT")
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

  test "task tag filters match all supplied tags" do
    @project.tasks.create!(title: "Both tags", status: "backlog").tap { |task| TagReconciler.call(task, ["one", "two"]) }
    @project.tasks.create!(title: "One tag", status: "backlog").tap { |task| TagReconciler.call(task, ["one"]) }

    get "/api/projects/writing/tasks", params: { tags: "one,two", summary: true }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal ["Both tags"], json_body.map { |task| task["title"] }
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

  test "task listing uses explicit position and position updates persist" do
    later = @project.tasks.create!(title: "Later", status: "backlog", position: 2000)
    first = @project.tasks.create!(title: "First", status: "backlog", position: 1000)

    get "/api/projects/writing/tasks", headers: json_headers(@raw_token)
    assert_equal ["First", "Later"], json_body.map { |task| task["title"] }
    assert_equal [1000, 2000], json_body.map { |task| task["position"] }

    patch "/api/tasks/#{later.id}", params: { position: 500 }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal 500, json_body["position"]
    get "/api/projects/writing/tasks", headers: json_headers(@raw_token)
    assert_equal ["Later", "First"], json_body.map { |task| task["title"] }
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

  test "gets and updates an owned task by external ref" do
    task = @project.tasks.create!(title: "Ref task", status: "backlog")

    get "/api/tasks/by-ref/WR-#{task.number}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "WR-#{task.number}", json_body["ref"]
    assert_equal task.number, json_body["number"]

    patch "/api/tasks/by-ref/WR-#{task.number}", params: { status: "done" }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "done", json_body["status"]
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

  test "deletes an owned note and cascades its relationships and citations" do
    task = @project.tasks.create!(title: "Related", status: "backlog")
    file = StoredFile.new(project: @project, filename: "source.txt", media_type: "text/plain", byte_size: 12, sha256: Digest::SHA256.hexdigest("source line\n"))
    file.original.attach(io: StringIO.new("source line\n"), filename: "source.txt", content_type: "text/plain")
    file.save!
    FileReader.generate(file)
    note = @user.notes.create!(title: "Throwaway", body: "Delete me")
    citation = note.citations.create!(stored_file: file, representation_kind: "text", locator: { "kind" => "lines", "start" => 1, "end" => 1 })
    task_note = TaskNote.create!(task: task, note: note)
    file_note = FileNote.create!(stored_file: file, note: note)

    delete "/api/notes/#{note.id}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal({ "id" => note.id }, json_body)
    assert_raises(ActiveRecord::RecordNotFound) { Note.find(note.id) }
    assert_raises(ActiveRecord::RecordNotFound) { Citation.find(citation.id) }
    assert_raises(ActiveRecord::RecordNotFound) { TaskNote.find(task_note.id) }
    assert_raises(ActiveRecord::RecordNotFound) { FileNote.find(file_note.id) }
  end

  test "deleting a missing note returns the established not found error" do
    delete "/api/notes/999999", headers: json_headers(@raw_token)
    assert_response :not_found
    assert_equal "not_found", json_body.dig("error", "code")
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
