require "swagger_helper"

RSpec.describe "Browser API contract", type: :request do
  let(:user) { User.create!(username: "contract-user", password: "password123") }
  let(:token_pair) { ApiToken.issue!(user: user, name: "contract") }
  let(:token) { token_pair.last }
  let(:Authorization) { "Bearer #{token}" }
  let(:project) { user.projects.create!(name: "Writing", slug: "writing", shorthand: "WR") }

  before do
    allow(SearchService).to receive(:new).and_return(instance_double(SearchService, call: []))
  end

  path "/api/auth/login" do
    post "Log in" do
      tags "Authentication"
      consumes "application/json"
      produces "application/json"
      parameter name: :login, in: :body, required: true, schema: {
        type: :object, required: %w[username password],
        properties: { username: { type: :string }, password: { type: :string, format: :password } }
      }
      response 201, "session created" do
        let(:login) { { username: user.username, password: "password123" } }
        schema "$ref" => "#/components/schemas/Session"
        run_test!
      end
      response 401, "invalid credentials" do
        let(:login) { { username: "contract-user", password: "wrong" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/auth/current" do
    get "Get the current user" do
      tags "Authentication"
      produces "application/json"
      security [ bearerAuth: [] ]
      response 200, "authenticated user" do
        schema "$ref" => "#/components/schemas/User"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/projects" do
    get "List projects" do
      tags "Projects"
      produces "application/json"
      security [ bearerAuth: [] ]
      response 200, "projects" do
        schema "$ref" => "#/components/schemas/ProjectList"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Create a project" do
      tags "Projects"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :project_input, in: :body, required: true, schema: {
        type: :object, required: [ "name" ],
        properties: { name: { type: :string }, slug: { type: :string }, shorthand: { type: :string }, description: { type: :string } }
      }
      let(:project_input) { nil }
      response 201, "project created" do
        let(:project_input) { { name: "New Project", description: "A backlog" } }
        schema "$ref" => "#/components/schemas/Project"
        run_test!
      end
      response 422, "validation failed" do
        let(:project_input) { { name: "" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/projects/{project_slug}/tasks" do
    parameter name: :project_slug, in: :path, required: true, schema: { type: :string, example: "writing" }

    get "List project tasks" do
      tags "Tasks"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :summary, in: :query, schema: { type: :boolean }
      parameter name: :status, in: :query, schema: { type: :string, enum: [ "backlog", "ready", "doing", "done", "dropped" ] }
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }
      let(:project_slug) { project.slug }
      let(:summary) { nil }
      let(:status) { nil }
      let(:limit) { nil }
      response 200, "tasks" do
        let(:project_slug) { project.slug }
        let(:summary) { nil }
        let(:status) { nil }
        let(:limit) { nil }
        schema "$ref" => "#/components/schemas/TaskList"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Create a task" do
      tags "Tasks"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :task_input, in: :body, required: true, schema: {
        type: :object, required: [ "title" ],
        properties: {
          title: { type: :string }, status: { type: :string }, priority: { type: :string },
          context: { type: :string }, intended_direction: { type: :string }, tags: { type: :array, items: { type: :string } }
        }
      }
      let(:project_slug) { project.slug }
      let(:task_input) { nil }
      response 201, "task created" do
        let(:project_slug) { project.slug }
        let(:task_input) { { title: "Ship contract", status: "backlog", tags: [ "api" ] } }
        schema "$ref" => "#/components/schemas/Task"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/search" do
    get "Search tasks and notes" do
      tags "Search"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :q, in: :query, required: true, schema: { type: :string }
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }
      parameter name: :project, in: :query, schema: { type: :string }
      parameter name: :scope, in: :query, schema: { type: :string }
      parameter name: :kinds, in: :query, schema: { type: :string }
      parameter name: :kind, in: :query, schema: { type: :string }
      parameter name: :tags, in: :query, schema: { type: :string }
      parameter name: :tag, in: :query, schema: { type: :string }
      parameter name: :task_statuses, in: :query, schema: { type: :string }
      parameter name: :status, in: :query, schema: { type: :string }
      parameter name: :task_priorities, in: :query, schema: { type: :string }
      parameter name: :priority, in: :query, schema: { type: :string }
      let(:q) { "contract" }
      let(:limit) { nil }
      let(:project) { nil }
      let(:scope) { nil }
      let(:kinds) { nil }
      let(:kind) { nil }
      let(:tags) { nil }
      let(:tag) { nil }
      let(:task_statuses) { nil }
      let(:status) { nil }
      let(:task_priorities) { nil }
      let(:priority) { nil }
      response 200, "ranked search results" do
        let(:q) { "contract" }
        let(:limit) { nil }
        let(:project) { nil }
        let(:scope) { nil }
        let(:kinds) { nil }
        let(:kind) { nil }
        let(:tags) { nil }
        let(:tag) { nil }
        let(:task_statuses) { nil }
        let(:status) { nil }
        let(:task_priorities) { nil }
        let(:priority) { nil }
        schema "$ref" => "#/components/schemas/SearchResponse"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/notes/{id}/edit" do
    parameter name: :id, in: :path, required: true, schema: { type: :integer }
    patch "Apply an atomic note edit" do
      tags "Notes"
      consumes "application/json"
      produces "application/json"
      security [ bearerAuth: [] ]
      parameter name: :edit_input, in: :body, required: true, schema: {
        type: :object, required: [ "operations" ],
        properties: { operations: { type: :array, minItems: 1, items: { type: :object, additionalProperties: true } }, expected_updated_at: { type: :string, format: "date-time" } }
      }
      let(:id) { user.notes.create!(title: "Contract", body: "Old").id }
      let(:edit_input) { nil }
      response 200, "note edited" do
        let(:id) { user.notes.create!(title: "Contract", body: "Old").id }
        let(:edit_input) { { operations: [ { operation: "append", text: " text" } ] } }
        schema "$ref" => "#/components/schemas/Note"
        run_test!
      end
      response 422, "edit validation or concurrency failure" do
        let(:id) { user.notes.create!(title: "Contract", body: "Old").id }
        let(:edit_input) { { operations: [] } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
      response 401, "authentication required" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end
