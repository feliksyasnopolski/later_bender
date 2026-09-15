require "test_helper"

class SemanticSearchTest < ActiveSupport::TestCase
  test "chunks note title and body with overlap" do
    note = Note.new(title: "Decision", body: ("alpha " * 700))
    chunks = SemanticChunker.for(note)
    assert_operator chunks.length, :>, 1
    assert_includes chunks.first, "Decision"
    assert_equal chunks.first.split.last(100), chunks.second.split.first(100)
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
