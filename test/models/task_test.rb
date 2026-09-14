require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "validates status and priority" do
    task = Task.new(project: Project.new(name: "Work"), title: "Task", status: "unknown", priority: "urgent")
    assert_not task.valid?
    assert_includes task.errors[:status], "is not included in the list"
    assert_includes task.errors[:priority], "is not included in the list"
  end
end
