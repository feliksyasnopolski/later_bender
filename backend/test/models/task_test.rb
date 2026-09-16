require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "validates status and priority" do
    user = User.new(username: "task-user", password: "password123")
    task = Task.new(project: user.projects.build(name: "Work"), title: "Task", status: "unknown", priority: "urgent")
    assert_not task.valid?
    assert_includes task.errors[:status], "is not included in the list"
    assert_includes task.errors[:priority], "is not included in the list"
  end

  test "new tasks append within their status column" do
    user = User.create!(username: "position-user", password: "password123")
    project = user.projects.create!(name: "Work", slug: "position-work")
    first = project.tasks.create!(title: "First", status: "ready")
    second = project.tasks.create!(title: "Second", status: "ready")
    assert_equal 1000, first.position
    assert_equal 2000, second.position
  end
end
