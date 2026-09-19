require "rails_helper"

RSpec.describe "Task number allocation", use_transactional_fixtures: false do
  it "keeps project-local numbers unique under concurrent creation" do
    user = User.create!(username: "concurrent-task-user", password: "password123")
    project = user.projects.create!(name: "Concurrent", slug: "concurrent-tasks", shorthand: "CT")
    barrier = Queue.new

    threads = 4.times.map do |index|
      Thread.new do
        barrier.pop
        project.tasks.create!(title: "Task #{index}")
      end
    end
    4.times { barrier << true }
    tasks = threads.map(&:value)

    expect(tasks.map(&:number).sort).to eq([ 1, 2, 3, 4 ])
    expect(project.tasks.pluck(:number).sort).to eq([ 1, 2, 3, 4 ])
  ensure
    user&.projects&.each { |owned_project| Task.where(project_id: owned_project.id).delete_all; owned_project.destroy! }
    user&.destroy!
  end
end
