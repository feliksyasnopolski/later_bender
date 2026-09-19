require "rails_helper"

RSpec.describe "Note model" do
  it "requires a user-owned project when scoped" do
    user = User.create!(username: "note-user", password: "password123")
    other = User.create!(username: "note-other", password: "password123")
    note = user.notes.new(title: "Decision", body: "Context", project: other.projects.create!(name: "Other"))

    assert_not note.valid?
    assert_includes note.errors[:project], "must belong to the note's user"
  end

  it "shares the existing tag model" do
    user = User.create!(username: "tag-note-user", password: "password123")
    note = user.notes.create!(title: "Decision", body: "Context")
    TagReconciler.call(note, [ "Rails", "rails" ])

    assert_equal [ "rails" ], note.tags.pluck(:name)
    assert_equal 1, Tag.count
  end

  it "rejects a task and note owned by different users" do
    user = User.create!(username: "task-note-user", password: "password123")
    other = User.create!(username: "task-note-other", password: "password123")
    task = user.projects.create!(name: "Work").tasks.create!(title: "Task", status: "backlog")
    note = other.notes.create!(title: "Note", body: "Context")

    relation = TaskNote.new(task: task, note: note)
    assert_not relation.valid?
    assert_includes relation.errors[:base], "task and note must belong to the same user"
  end
end
