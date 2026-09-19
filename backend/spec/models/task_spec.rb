require "rails_helper"

RSpec.describe "Task model" do
  it "validates status and priority" do
    user = User.new(username: "task-user", password: "password123")
    task = Task.new(project: user.projects.build(name: "Work"), title: "Task", status: "unknown", priority: "urgent")
    assert_not task.valid?
    assert_includes task.errors[:status], "is not included in the list"
    assert_includes task.errors[:priority], "is not included in the list"
  end

  it "new tasks append within their status column" do
    user = User.create!(username: "position-user", password: "password123")
    project = user.projects.create!(name: "Work", slug: "position-work")
    first = project.tasks.create!(title: "First", status: "ready")
    second = project.tasks.create!(title: "Second", status: "ready")
    assert_equal 1000, first.position
    assert_equal 2000, second.position
  end

  it "allocates immutable project-local numbers from the project counter" do
    user = User.create!(username: "number-user", password: "password123")
    project = user.projects.create!(name: "Work", slug: "number-work", shorthand: "NW", next_task_number: 10)
    first = project.tasks.create!(title: "First", status: "ready")
    second = project.tasks.create!(title: "Second", status: "ready")

    assert_equal [ 10, 11 ], [ first.number, second.number ]
    assert_equal [ "NW-10", "NW-11" ], [ first.ref, second.ref ]
    assert_equal 12, project.reload.next_task_number
    second.number = 99
    assert_not second.valid?
    assert_includes second.errors[:number], "cannot be changed"
  end

  it "allocates numbers independently for each project" do
    user = User.create!(username: "local-number-user", password: "password123")
    first_project = user.projects.create!(name: "First", slug: "first-local", shorthand: "FL")
    second_project = user.projects.create!(name: "Second", slug: "second-local", shorthand: "SL")

    first_task = first_project.tasks.create!(title: "First task")
    second_task = second_project.tasks.create!(title: "Second task")

    assert_equal 1, first_task.number
    assert_equal 1, second_task.number
    assert_equal "FL-1", first_task.ref
    assert_equal "SL-1", second_task.ref
  end
end
