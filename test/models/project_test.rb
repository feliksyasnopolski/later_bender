require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "generates a predictable slug and enforces uniqueness" do
    user = User.create!(username: "project-user", password: "password123")
    first = user.projects.create!(name: "My Writing Backlog")
    assert_equal "my-writing-backlog", first.slug

    duplicate = user.projects.new(name: "Other", slug: first.slug)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end
end
