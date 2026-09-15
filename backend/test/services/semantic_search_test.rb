require "test_helper"

class SemanticSearchTest < ActiveSupport::TestCase
  test "keeps a short record in one chunk" do
    note = Note.new(title: "Decision", body: "alpha beta gamma")
    assert_equal [ "Decision\n\nalpha beta gamma" ], SemanticChunker.for(note)
  end

  test "chunks long prose with deterministic token overlap" do
    note = Note.new(title: "Decision", body: ("alpha " * 700))
    chunks = SemanticChunker.for(note)
    assert_operator chunks.length, :>, 1
    assert_includes chunks.first, "Decision"
    assert_equal chunks, SemanticChunker.for(note)
    assert_operator SemanticChunker.new(note).send(:approximate_tokens, chunks.first), :<=, SemanticChunker::TARGET_TOKENS
    assert_equal "alpha", chunks.second.split[1]
  end

  test "keeps line-oriented records ordered and intact where practical" do
    lines = (1..80).map { |n| "event=#{n} status=complete command=deploy" }.join("\n")
    chunks = SemanticChunker.for(Note.new(title: "Session", body: lines))

    assert_operator chunks.length, :>, 1
    numbers = chunks.join("\n").scan(/event=(\d+)/).flatten.map(&:to_i)
    assert_equal (1..80).to_a, numbers.uniq
    assert_includes chunks.first, "event=1"
    assert_includes chunks.last, "event=80"
  end

  test "collapses multiple semantic chunks to one parent" do
    service = SearchService.new(user: User.new, q: "query")
    hits = [
      { "kind" => "task", "parent_id" => 7, "title" => "Task", "chunk_text" => "first", "created_at" => nil, "updated_at" => nil },
      { "kind" => "task", "parent_id" => 7, "title" => "Task", "chunk_text" => "second", "created_at" => nil, "updated_at" => nil },
      { "kind" => "note", "parent_id" => 7, "title" => "Note", "chunk_text" => "note", "created_at" => nil, "updated_at" => nil }
    ]

    results = service.send(:semantic_results, hits)

    assert_equal [ [ "task", 7 ], [ "note", 7 ] ], results.map { |result| [ result[:kind], result[:id] ] }
  end

  test "semantic indexing replaces the old chunk set" do
    note = Note.new(id: 7, title: "Session", body: "short")
    note.define_singleton_method(:tags) { [] }
    client = RecordingSemanticClient.new
    embeddings = RecordingEmbeddingClient.new

    SemanticIndexer.call(note, embedding_client: embeddings, client: client)
    note.body = ("line " * 700)
    SemanticIndexer.call(note, embedding_client: embeddings, client: client)

    assert_equal 2, client.delete_requests.length
    assert_operator client.bulk_requests.first.length, :<, client.bulk_requests.second.length
    assert_equal client.bulk_requests.second.length, embeddings.calls.last.length
  end

  test "chunks task title, context, and intended direction" do
    task = Task.new(title: "Ship", context: "The cause", intended_direction: "The next move")
    assert_equal "Ship\n\nThe cause\n\nThe next move", SemanticChunker.new(task).send(:source_text)
  end

  test "RRF is deterministic and rewards agreement" do
    assert_equal %w[task-1 task-2 task-3], RrfFuser.call(%w[task-1 task-2], %w[task-1 task-3], limit: 3)
    assert_equal %w[task-2 task-1], RrfFuser.call(%w[task-1 task-2], %w[task-2], limit: 2)
  end
end

class RecordingSemanticClient
  attr_reader :delete_requests, :bulk_requests

  def initialize
    @delete_requests = []
    @bulk_requests = []
  end

  def delete_by_query(**request)
    @delete_requests << request
  end

  def bulk(body:, **)
    @bulk_requests << body
  end
end

class RecordingEmbeddingClient
  attr_reader :calls

  def initialize
    @calls = []
  end

  def embed(texts, mode:)
    @calls << texts
    Array.new(texts.length) { Array.new(256, 0.1) }
  end
end
