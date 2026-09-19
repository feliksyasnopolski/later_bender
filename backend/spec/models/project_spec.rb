require "rails_helper"

RSpec.describe "Project model" do
  it "generates a predictable slug and enforces uniqueness" do
    user = User.create!(username: "project-user", password: "password123")
    first = user.projects.create!(name: "My Writing Backlog")
    assert_equal "my-writing-backlog", first.slug

    duplicate = user.projects.new(name: "Other", slug: first.slug)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"

    other_user_project = User.create!(username: "other-slug-user", password: "password123").projects.create!(name: "Other", slug: first.slug)
    assert_equal first.slug, other_user_project.slug
  end

  it "normalizes shorthand and enforces per-user uniqueness" do
    user = User.create!(username: "shorthand-user", password: "password123")
    project = user.projects.create!(name: "Writing", shorthand: "wr")
    assert_equal "WR", project.shorthand

    duplicate = user.projects.new(name: "Other", shorthand: "wr")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:shorthand], "has already been taken"

    other_user_project = User.create!(username: "other-shorthand-user", password: "password123").projects.create!(name: "Other", shorthand: "wr")
    assert_equal "WR", other_user_project.shorthand
  end
end
