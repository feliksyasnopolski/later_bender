require "rails_helper"

RSpec.describe "Api API", type: :request do
  before do
    @user = User.create!(username: "test-user", password: "password123")
    @token, @raw_token = ApiToken.issue!(user: @user, name: "test client")
    @project = @user.projects.create!(name: "Writing", slug: "writing", shorthand: "WR")
    @other_project = @user.projects.create!(name: "Other", slug: "other", shorthand: "OT")
  end

  it "rejects missing and revoked bearer tokens" do
    get "/api/projects", headers: json_headers
    assert_response :unauthorized

    @token.update!(revoked_at: Time.current)
    get "/api/projects", headers: json_headers(@raw_token)
    assert_response :unauthorized
  end

  it "creates a project through the authenticated API" do
    post "/api/projects", params: { name: "New Project", description: "A backlog" }.to_json, headers: json_headers(@raw_token)
    assert_response :created
    assert_equal "new-project", json_body["slug"]
  end

  it "creates a task with tags and replaces tags on update" do
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

  it "task tag filters match all supplied tags" do
    @project.tasks.create!(title: "Both tags", status: "backlog").tap { |task| TagReconciler.call(task, [ "one", "two" ]) }
    @project.tasks.create!(title: "One tag", status: "backlog").tap { |task| TagReconciler.call(task, [ "one" ]) }

    get "/api/projects/writing/tasks", params: { tags: "one,two", summary: true }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ "Both tags" ], json_body.map { |task| task["title"] }
  end

  it "reuses an existing tag when creating a task" do
    Tag.create!(name: "deployment", slug: "deployment")

    post "/api/projects/writing/tasks", params: {
      title: "Reuse tag", status: "backlog", tags: [ "deployment" ]
    }.to_json, headers: json_headers(@raw_token)

    assert_response :created
    assert_equal [ "deployment" ], json_body["tags"]
    assert_equal 1, Tag.count
  end

  it "nested listing is project scoped and global search filters tasks" do
    @project.tasks.create!(title: "Find this prose", status: "ready", context: "important writing")
    @other_project.tasks.create!(title: "Do not leak", status: "ready")

    get "/api/projects/writing/tasks", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ "Find this prose" ], json_body.map { |task| task["title"] }

    get "/api/tasks", params: { project: "writing", q: "important" }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ "Find this prose" ], json_body.map { |task| task["title"] }
  end

  it "task listing uses explicit position and position updates persist" do
    later = @project.tasks.create!(title: "Later", status: "backlog", position: 2000)
    first = @project.tasks.create!(title: "First", status: "backlog", position: 1000)

    get "/api/projects/writing/tasks", headers: json_headers(@raw_token)
    assert_equal [ "First", "Later" ], json_body.map { |task| task["title"] }
    assert_equal [ 1000, 2000 ], json_body.map { |task| task["position"] }

    patch "/api/tasks/#{later.id}", params: { position: 500 }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal 500, json_body["position"]
    get "/api/projects/writing/tasks", headers: json_headers(@raw_token)
    assert_equal [ "Later", "First" ], json_body.map { |task| task["title"] }
  end

  it "returns structured validation errors" do
    post "/api/projects/writing/tasks", params: { title: "", status: "later" }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "validation_failed", json_body.dig("error", "code")
    assert json_body.dig("error", "details", "status")
  end

  it "does not allow a nested route to reach another project's task" do
    task = @other_project.tasks.create!(title: "Private", status: "backlog")
    get "/api/projects/writing/tasks/#{task.id}", headers: json_headers(@raw_token)
    assert_response :not_found
  end

  it "gets and updates an owned task by global id and keeps task lists compact" do
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

  it "gets and updates an owned task by external ref" do
    task = @project.tasks.create!(title: "Ref task", status: "backlog")

    get "/api/tasks/by-ref/WR-#{task.number}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "WR-#{task.number}", json_body["ref"]
    assert_equal task.number, json_body["number"]

    patch "/api/tasks/by-ref/WR-#{task.number}", params: { status: "done" }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "done", json_body["status"]
  end

  it "resolves identical task refs within the authenticated user's namespace" do
    other = User.create!(username: "other-ref-user", password: "password123")
    other_project = other.projects.create!(name: "Writing", slug: "writing", shorthand: "WR")
    own_task = @project.tasks.create!(title: "Own ref", status: "backlog")
    other_task = other_project.tasks.create!(title: "Other ref", status: "backlog")
    assert_equal own_task.ref, other_task.ref

    get "/api/tasks/by-ref/#{own_task.ref}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal own_task.id, json_body["id"]

    _other_token, other_raw_token = ApiToken.issue!(user: other, name: "other client")
    get "/api/tasks/by-ref/#{other_task.ref}", headers: json_headers(other_raw_token)
    assert_response :success
    assert_equal other_task.id, json_body["id"]

    get "/api/tasks/by-ref/#{other_task.ref}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal own_task.id, json_body["id"]

    get "/api/tasks/by-ref/WR-999999", headers: json_headers(@raw_token)
    assert_response :not_found
  end

  it "creates, lists, reads, and updates global and project notes" do
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

  it "deletes an owned note and cascades its relationships and citations" do
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

  it "deleting a missing note returns the established not found error" do
    delete "/api/notes/999999", headers: json_headers(@raw_token)
    assert_response :not_found
    assert_equal "not_found", json_body.dig("error", "code")
  end

  it "deletes an owned file through its canonical ref and returns not found afterward" do
    bytes = "throwaway file\n"
    file = StoredFile.new(project: @project, filename: "throwaway.txt", media_type: "text/plain", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: "throwaway.txt", content_type: "text/plain")
    file.save!

    delete "/api/files/by-ref/#{file.ref}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal({ "ref" => file.ref }, json_body)

    get "/api/files/by-ref/#{file.ref}", headers: json_headers(@raw_token)
    assert_response :not_found
    assert_equal "not_found", json_body.dig("error", "code")
    assert_raises(ActiveRecord::RecordNotFound) { StoredFile.find(file.id) }
  end

  it "creates a URL-backed file with structured provenance and stable source errors" do
    post "/api/projects/writing/files", params: {}.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "source_required", json_body.dig("error", "code")

    post "/api/projects/writing/files", params: { file: {}, url: "https://public.example/report.txt" }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "source_conflict", json_body.dig("error", "code")

    bytes = "downloaded evidence\n"
    origin = {
      "kind" => "url",
      "requested_url" => "https://public.example/report.txt",
      "final_url" => "https://cdn.example/report.txt",
      "fetched_at" => "2026-09-17T12:00:00.000000Z"
    }
    file = StoredFile.new(project: @project, filename: "report.txt", media_type: "text/plain", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), origin:)
    file.original.attach(io: StringIO.new(bytes), filename: "report.txt", content_type: "text/plain")
    file.save!

    get "/api/files/by-ref/#{file.ref}", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "report.txt", json_body["filename"]
    assert_equal bytes.bytesize, json_body["byte_size"]
    assert_equal Digest::SHA256.hexdigest(bytes), json_body["sha256"]
    assert_equal origin, json_body.dig("provenance", "origin")
  end

  it "issues a short-lived canonical file download and preserves exact bytes" do
    bytes = "\x89PNG\r\n\x1a\ncanonical-image".b
    file = StoredFile.new(project: @project, filename: "evidence.png", media_type: "image/png", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: "evidence.png", content_type: "image/png")
    file.save!

    get "/api/files/by-ref/#{file.ref}/egress", headers: json_headers(@raw_token)
    assert_response :success
    egress = json_body.fetch("file")
    assert_equal file.ref, egress["ref"]
    assert_equal "evidence.png", egress["filename"]
    assert_equal "image/png", egress["media_type"]
    assert_equal bytes.bytesize, egress["byte_size"]
    assert_equal Digest::SHA256.hexdigest(bytes), egress["sha256"]
    assert_match %r{\A/rails/active_storage/blobs/redirect/}, egress["download_path"]

    get egress.fetch("download_path")
    follow_redirect! while response.redirect?
    assert_response :success
    assert_equal bytes, response.body.b
    assert_equal "image/png", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/evidence\.png/, response.headers["Content-Disposition"])

    get "/api/files/by-ref/#{file.ref}/download", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal bytes, response.body.b
    assert_equal "image/png", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])
    assert_match(/evidence\.png/, response.headers["Content-Disposition"])

    get "/api/files/by-ref/#{file.ref}/download"
    assert_response :unauthorized
  end

  it "does not issue file egress for another user" do
    other = User.create!(username: "file-owner", password: "password123")
    project = other.projects.create!(name: "Private files", slug: "private-files", shorthand: "PF")
    bytes = "private"
    file = StoredFile.new(project: project, filename: "private.bin", media_type: "application/octet-stream", byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: "private.bin", content_type: "application/octet-stream")
    file.save!

    get "/api/files/by-ref/#{file.ref}/egress", headers: json_headers(@raw_token)
    assert_response :not_found
  end

  it "does not expose another user's notes or permit cross-user task relations" do
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

  it "task related notes replace, clear, and preserve predictably" do
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

  it "task pagination traverses filtered board order without duplicates and rejects mismatched cursors" do
    first = @project.tasks.create!(title: "First", status: "ready", position: 1000)
    second = @project.tasks.create!(title: "Second", status: "ready", position: 1000)
    third = @project.tasks.create!(title: "Third", status: "ready", position: 2000)
    @project.tasks.create!(title: "Filtered out", status: "done", position: 500)

    get "/api/projects/writing/tasks", params: { paginated: true, summary: true, status: "ready", limit: 2 }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ first.ref, second.ref ], json_body["tasks"].map { |task| task["ref"] }
    cursor = json_body["next_cursor"]
    assert cursor.present?

    get "/api/projects/writing/tasks", params: { paginated: true, summary: true, status: "ready", limit: 2, cursor: cursor }, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal [ third.ref ], json_body["tasks"].map { |task| task["ref"] }
    assert_nil json_body["next_cursor"]

    get "/api/projects/writing/tasks", params: { paginated: true, summary: true, status: "done", limit: 2, cursor: cursor }, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "validation_failed", json_body.dig("error", "code")
    get "/api/projects/writing/tasks", params: { paginated: true, cursor: "malformed" }, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
  end

  it "note pagination supports deterministic created and updated ordering" do
    old = @user.notes.create!(title: "Old", body: "old")
    middle = @user.notes.create!(title: "Middle", body: "middle")
    recent = @user.notes.create!(title: "Recent", body: "recent")
    old.update_columns(created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 3))
    middle.update_columns(created_at: Time.utc(2026, 1, 2), updated_at: Time.utc(2026, 1, 2))
    recent.update_columns(created_at: Time.utc(2026, 1, 3), updated_at: Time.utc(2026, 1, 1))

    get "/api/notes", params: { paginated: true, scope: "global", sort: "updated_at", order: "desc", limit: 2, summary: true }, headers: json_headers(@raw_token)
    assert_equal [ old.id, middle.id ], json_body["notes"].map { |note| note["id"] }
    cursor = json_body["next_cursor"]
    get "/api/notes", params: { paginated: true, scope: "global", sort: "updated_at", order: "desc", limit: 2, summary: true, cursor: cursor }, headers: json_headers(@raw_token)
    assert_equal [ recent.id ], json_body["notes"].map { |note| note["id"] }
    assert_nil json_body["next_cursor"]

    get "/api/notes", params: { paginated: true, scope: "global", sort: "created_at", order: "asc", summary: true }, headers: json_headers(@raw_token)
    assert_equal [ old.id, middle.id, recent.id ], json_body["notes"].map { |note| note["id"] }
  end

  it "file browse sorting supports every public sort in both directions with stable ties" do
    alpha = create_file("alpha.txt", "a")
    beta = create_file("beta.txt", "bbbb")
    gamma = create_file("gamma.txt", "cc")
    alpha.update_columns(created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 3))
    beta.update_columns(created_at: Time.utc(2026, 1, 2), updated_at: Time.utc(2026, 1, 2))
    gamma.update_columns(created_at: Time.utc(2026, 1, 2), updated_at: Time.utc(2026, 1, 1))

    expectations = {
      [ "created_at", "asc" ] => %w[alpha.txt beta.txt gamma.txt],
      [ "created_at", "desc" ] => %w[gamma.txt beta.txt alpha.txt],
      [ "updated_at", "asc" ] => %w[gamma.txt beta.txt alpha.txt],
      [ "updated_at", "desc" ] => %w[alpha.txt beta.txt gamma.txt],
      [ "filename", "asc" ] => %w[alpha.txt beta.txt gamma.txt],
      [ "filename", "desc" ] => %w[gamma.txt beta.txt alpha.txt],
      [ "size", "asc" ] => %w[alpha.txt gamma.txt beta.txt],
      [ "size", "desc" ] => %w[beta.txt gamma.txt alpha.txt]
    }
    expectations.each do |(sort, order), filenames|
      get "/api/projects/writing/files", params: { paginated: true, sort: sort, order: order }, headers: json_headers(@raw_token)
      assert_response :success
      assert_equal filenames, json_body["files"].map { |file| file["filename"] }, "#{sort} #{order}"
    end

    get "/api/projects/writing/files", params: { paginated: true, sort: "created_at", order: "desc", limit: 2 }, headers: json_headers(@raw_token)
    first_page = json_body
    get "/api/projects/writing/files", params: { paginated: true, sort: "created_at", order: "desc", limit: 2, cursor: first_page["next_cursor"] }, headers: json_headers(@raw_token)
    assert_equal %w[gamma.txt beta.txt alpha.txt], first_page["files"].map { |file| file["filename"] } + json_body["files"].map { |file| file["filename"] }
    assert_nil json_body["next_cursor"]
  end

  it "targeted note edits apply in order atomically and honor optimistic concurrency" do
    note = @user.notes.create!(title: "Durable", body: "alpha beta")
    expected = note.updated_at.as_json
    patch "/api/notes/#{note.id}/edit", params: { operations: [ { operation: "replace", old_text: "alpha", new_text: "one" }, { operation: "append", text: "\nmore" } ], expected_updated_at: expected }.to_json, headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "one beta\nmore", note.reload.body

    unchanged = note.body
    patch "/api/notes/#{note.id}/edit", params: { operations: [ { operation: "append", text: " temporary" }, { operation: "replace", old_text: "missing", new_text: "never" } ] }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal unchanged, note.reload.body

    note.update!(body: "same same")
    patch "/api/notes/#{note.id}/edit", params: { operations: [ { operation: "replace", old_text: "same", new_text: "once" } ] }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "same same", note.reload.body

    patch "/api/notes/#{note.id}/edit", params: { operations: [ { operation: "append", text: " stale" } ], expected_updated_at: expected }.to_json, headers: json_headers(@raw_token)
    assert_response :unprocessable_content
    assert_equal "same same", note.reload.body
  end

  it "file reads identify source representation coordinate and effective locator" do
    text = create_file("source.txt", "one\ntwo\nthree\n", media_type: "text/plain")
    image = create_file("pixel.png", "png", media_type: "image/png")

    get "/api/files/by-ref/#{text.ref}/read", headers: json_headers(@raw_token)
    assert_response :success
    assert_equal "text", json_body["kind"]
    assert_equal({ "kind" => "file", "ref" => text.ref }, json_body["source"])
    assert_equal "lines", json_body["coordinate"]
    assert_equal({ "kind" => "lines", "start" => 1, "end" => 3 }, json_body["locator"])

    get "/api/files/by-ref/#{text.ref}/read", params: { locator: { kind: "lines", start: 2, end: 2 }.to_json }, headers: json_headers(@raw_token)
    assert_equal "[L2] two\n", json_body["content"]
    assert_equal({ "kind" => "lines", "start" => 2, "end" => 2 }, json_body["locator"])

    get "/api/files/by-ref/#{image.ref}/read", headers: json_headers(@raw_token)
    assert_equal "metadata", json_body["kind"]
    assert_nil json_body["coordinate"]
    assert_nil json_body["locator"]
  end

  it "archive pagination traverses deterministic paths and rejects a cursor from another view" do
    Dir.mktmpdir("later-bender-api-archive") do |source|
      %w[c.txt a.txt b.txt].each { |name| File.binwrite(File.join(source, name), name) }
      archive_path = File.join(source, "bundle.zip")
      _output, error, status = Open3.capture3("zip", "-q", archive_path, "a.txt", "b.txt", "c.txt", chdir: source)
      raise error unless status.success?
      archive = create_file("bundle.zip", File.binread(archive_path), media_type: "application/zip")

      get "/api/files/by-ref/#{archive.ref}/archive", params: { paginated: true, depth: 0, limit: 2 }, headers: json_headers(@raw_token)
      assert_response :success
      assert_equal %w[a.txt b.txt], json_body["entries"].map { |entry| entry["path"] }
      cursor = json_body["next_cursor"]
      get "/api/files/by-ref/#{archive.ref}/archive", params: { paginated: true, depth: 0, limit: 2, cursor: cursor }, headers: json_headers(@raw_token)
      assert_equal [ "c.txt" ], json_body["entries"].map { |entry| entry["path"] }
      assert_nil json_body["next_cursor"]

      get "/api/files/by-ref/#{archive.ref}/archive", params: { paginated: true, depth: 1, limit: 2, cursor: cursor }, headers: json_headers(@raw_token)
      assert_response :unprocessable_content
    end
  end

  private

  def create_file(filename, bytes, media_type: "text/plain")
    file = StoredFile.new(project: @project, filename: filename, media_type: media_type, byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes))
    file.original.attach(io: StringIO.new(bytes), filename: filename, content_type: media_type)
    file.save!
    file
  end
end
