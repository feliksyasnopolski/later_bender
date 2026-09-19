require "rails_helper"

RSpec.describe "Search API contract", type: :request do
  class DeterministicSearchQuery
    attr_reader :filters

    def initialize(hits)
      @hits = hits
      @filters = nil
    end

    def query(bool:)
      @filters = bool.fetch(:filter)
      self
    end

    def highlight(_options)
      self
    end

    def limit(_value)
      self
    end

    def to_a
      user_id = filters.find { |filter| filter.dig(:term, :user_id) }&.dig(:term, :user_id)
      @hits.select { |hit| (hit.project&.user_id || hit.record.user_id) == user_id }
    end
  end

  it "serializes a real mixed Task, Note, and File search contract without leaking another user" do
    fixture = JSON.parse(File.read(Rails.root.join("..", "test", "fixtures", "rails_search_response.json")))
    user = create(:user)
    other_user = create(:user)
    project = create(:project, user:, name: "Contract Project", slug: "contract-project", shorthand: "CP")
    other_project = create(:project, user: other_user, name: "Other Contract Project", slug: "other-contract", shorthand: "OC")
    task = create(:task, project:, title: "Ship contract task")
    note = create(:note, user:, project: nil, title: "Contract note", body: "A global contract note")
    file = create(:stored_file, project:, filename: "contract-evidence.txt", contents: "contract evidence\nsecond line\n")
    file.representations.find_or_initialize_by(kind: "text").update!(media_type: file.media_type, generator: "spec", generator_version: "1", status: "ready", content: "contract evidence\nsecond line\n", metadata: { "coordinate" => "lines" })
    other_task = create(:task, project: other_project, title: "Private contract task")

    hits = [
      SearchHit.new(record: task, kind: "task", title_highlights: [ "Ship contract task" ]),
      SearchHit.new(record: note, kind: "note", body_highlights: [ "A global contract note" ]),
      SearchHit.new(record: file, kind: "file", representation: "text", locator: { "kind" => "lines", "start" => 1, "end" => 2 }, body_highlights: [ "contract evidence" ]),
      SearchHit.new(record: other_task, kind: "task", title_highlights: [ "Private contract task" ])
    ]
    query = DeterministicSearchQuery.new(hits)
    allow(SearchDocumentsIndex).to receive(:all).and_return(query)
    token, raw_token = ApiToken.issue!(user:, name: "search contract")

    get "/api/search", params: { q: "", mode: "lexical" }, headers: json_headers(raw_token)

    assert_response :success
    body = json_body
    assert_equal 3, body["total"]
    assert_equal %w[task note file], body["results"].map { |result| result["kind"] }
    assert_equal fixture["results"].map { |result| result["kind"] }, body["results"].map { |result| result["kind"] }
    assert_equal [ task.ref, note.id, file.ref ], body["results"].map { |result| result["ref"] || result["id"] }

    task_result, note_result, file_result = body["results"]
    assert_equal({ "id" => project.id, "name" => project.name, "slug" => project.slug, "shorthand" => project.shorthand }, task_result["project"])
    assert_nil note_result["project"]
    assert_equal({ "id" => project.id, "name" => project.name, "slug" => project.slug, "shorthand" => project.shorthand }, file_result["project"])
    assert_equal "text", file_result.dig("match", "representation")
    assert_equal({ "kind" => "lines", "start" => 1, "end" => 2 }, file_result.dig("match", "locator"))
    assert_equal "Ship contract task", task_result["snippet"]
    assert_equal "A global contract note", note_result["snippet"]
    assert_equal "contract evidence", file_result["snippet"]
    assert_equal "contract evidence", file_result.dig("highlights", 0, "fragments", 0)
    refute body.to_s.include?(other_task.ref)
    assert_includes query.filters, { term: { user_id: user.id } }
  end
end
