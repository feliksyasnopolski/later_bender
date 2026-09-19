# frozen_string_literal: true

require "rails_helper"

RSpec.configure do |config|
  # Specify a root folder where Swagger JSON files are generated
  # NOTE: If you're using the rswag-api to serve API descriptions, you'll need
  # to ensure that it's configured to serve Swagger from the same folder
  config.openapi_root = Rails.root.join("openapi").to_s

  # Keep the generated document's route inventory aligned with Rails, while
  # request specs below replace these placeholders with executable contracts.
  resource_schema = lambda do |route_path, verb|
    if verb == "delete"
      return { "$ref" => "#/components/schemas/NoteDeleteAck" } if route_path.include?("/notes/")
      return { "$ref" => "#/components/schemas/FileDeleteAck" } if route_path.include?("/files/by-ref/")
      return nil
    end
    return { "$ref" => "#/components/schemas/FileDownload" } if route_path.end_with?("/download")
    return { "$ref" => "#/components/schemas/Session" } if [ "/api/auth/login", "/api/auth/recover" ].include?(route_path)
    return { "$ref" => "#/components/schemas/TokenInfo" } if route_path == "/api/oauth/token_info"
    return { type: "array", items: { "$ref" => "#/components/schemas/ApiToken" } } if route_path == "/api/tokens" && verb == "get"
    return { "$ref" => "#/components/schemas/ApiTokenWithSecret" } if route_path == "/api/tokens" && verb == "post"
    return { "$ref" => "#/components/schemas/TotpList" } if route_path == "/api/account/totp" && verb == "get"
    return { "$ref" => "#/components/schemas/TotpCreate" } if route_path == "/api/account/totp" && verb == "post"
    return { "$ref" => "#/components/schemas/TotpConfirmation" } if route_path.include?("/account/totp/") && verb == "post"
    return { "$ref" => "#/components/schemas/ProjectList" } if route_path == "/api/projects" && verb == "get"
    return { "$ref" => "#/components/schemas/Project" } if route_path.match?(%r{\A/api/projects(?:/\{slug\})?\z})
    return { "$ref" => "#/components/schemas/TaskList" } if route_path == "/api/tasks" && verb == "get" || route_path.end_with?("/tasks") && verb == "get"
    return { "$ref" => "#/components/schemas/Task" } if route_path.include?("/tasks")
    return { "$ref" => "#/components/schemas/NoteList" } if route_path.end_with?("/notes") && verb == "get"
    return { "$ref" => "#/components/schemas/Note" } if route_path.include?("/notes")
    return { "$ref" => "#/components/schemas/SearchResponse" } if route_path == "/api/search"
    return { "$ref" => "#/components/schemas/FileList" } if route_path.end_with?("/files") && verb == "get"
    return { "$ref" => "#/components/schemas/ArchiveEntryRead" } if route_path.end_with?("/archive/entry")
    return { "$ref" => "#/components/schemas/FileRead" } if route_path.end_with?("/read")
    return { "$ref" => "#/components/schemas/FileReadBatch" } if route_path.end_with?("/read-batch")
    return { "$ref" => "#/components/schemas/FileEgress" } if route_path.end_with?("/egress")
    return { "$ref" => "#/components/schemas/ArchiveList" } if route_path.end_with?("/archive")
    return { "$ref" => "#/components/schemas/FileRefAck" } if route_path.end_with?("/files") && verb == "post" || route_path.end_with?("/extract") || route_path.include?("/files/by-ref/") && verb == "patch"
    return { "$ref" => "#/components/schemas/StoredFile" } if route_path.include?("/files/by-ref/")
    { type: "object", additionalProperties: true }
  end

  request_schema = lambda do |route_path, verb|
    return { "$ref" => "#/components/schemas/SessionInput" } if route_path == "/api/auth/recover"
    return { "$ref" => "#/components/schemas/TokenCreateInput" } if route_path == "/api/tokens" && verb == "post"
    return { "$ref" => "#/components/schemas/TotpCreateInput" } if route_path == "/api/account/totp" && verb == "post"
    return { "$ref" => "#/components/schemas/TotpConfirmInput" } if route_path.include?("/account/totp/")
    return { "$ref" => "#/components/schemas/ProjectInput" } if route_path.match?(%r{\A/api/projects/\{slug\}\z})
    return { "$ref" => "#/components/schemas/TaskInput" } if route_path.include?("/tasks")
    return { "$ref" => "#/components/schemas/NoteInput" } if route_path.include?("/notes")
    return { "$ref" => "#/components/schemas/FileCreateInput" } if route_path.end_with?("/files") && verb == "post"
    return { "$ref" => "#/components/schemas/FileReadBatchInput" } if route_path.end_with?("/read-batch")
    return { "$ref" => "#/components/schemas/ArchiveExtractInput" } if route_path.end_with?("/archive/extract")
    return { "$ref" => "#/components/schemas/FileUpdateInput" } if route_path.include?("/files/by-ref/") && verb != "post"
    { type: "object", additionalProperties: true }
  end

  api_route_paths = Hash.new { |hash, key| hash[key] = {} }
  fully_specified_paths = [
    "/api/auth/login", "/api/auth/current", "/api/projects", "/api/projects/{project_slug}/tasks",
    "/api/search", "/api/notes/{id}/edit"
  ]
  Rails.application.routes.routes.each do |route|
    route_path = route.path.spec.to_s.sub("(.:format)", "").gsub(/:([a-z_]+)/, '{\\1}')
    next unless route_path.start_with?("/api/")

    route.verb.split("|").each do |verb|
      creates_resource = verb.downcase == "post" && (
        [ "/api/auth/login", "/api/auth/recover", "/api/tokens", "/api/account/totp", "/api/projects" ].include?(route_path) ||
        route_path.end_with?("/tasks", "/notes", "/files", "/archive/extract")
      )
      success_code = creates_resource ? "201" : "200"
      success_response = resource_schema.call(route_path, verb.downcase)
      responses = {
        success_code => {
          description: success_code == "201" ? "created" : "successful",
          content: success_response ? { (route_path.end_with?("/download") ? "application/octet-stream" : "application/json") => { schema: success_response } } : nil
        },
        "401" => { description: "authentication required", content: { "application/json" => { schema: { "$ref" => "#/components/schemas/Error" } } } }
      }
      if verb.downcase == "delete"
        if success_response
          responses.delete("204")
        else
          responses.delete("200")
          responses["204"] = { description: "no content" }
        end
      end
      responses["404"] = { description: "owned resource not found", content: { "application/json" => { schema: { "$ref" => "#/components/schemas/Error" } } } } if route_path.match?(%r{\{(id|ref|slug)\}})
      responses["422"] = { description: "validation failed", content: { "application/json" => { schema: { "$ref" => "#/components/schemas/Error" } } } } if %w[post patch put].include?(verb.downcase)
      operation = {
        summary: "#{route.defaults[:controller]}##{route.defaults[:action]}",
        tags: [ route.defaults[:controller].to_s.delete_prefix("api/").split("/").first.capitalize ],
        responses: responses
      }
      operation[:security] = [ { bearerAuth: [] } ] unless [ "/api/auth/login", "/api/auth/recover" ].include?(route_path)
      unless fully_specified_paths.include?(route_path)
        operation[:parameters] = case route_path
        when "/api/tasks"
          %w[project status priority tag tags q limit summary paginated cursor].map { |name| { name: name, in: "query", schema: { type: %w[limit].include?(name) ? "integer" : "string" } } }
        when "/api/notes"
          %w[project projectless scope tag limit summary paginated cursor sort order].map { |name| { name: name, in: "query", schema: { type: %w[limit].include?(name) ? "integer" : "string" } } }
        when "/api/projects/{project_slug}/files"
          %w[tag tags limit paginated cursor sort order].map { |name| { name: name, in: "query", schema: { type: %w[limit].include?(name) ? "integer" : "string" } } }
        when %r{\A/api/files/by-ref/\{ref\}/archive\z}
          %w[path depth limit paginated cursor].map { |name| { name: name, in: "query", schema: { type: %w[depth limit].include?(name) ? "integer" : "string" } } }
        when %r{/api/files/by-ref/\{ref\}/read\z}, %r{/api/files/by-ref/\{ref\}/archive/entry\z}
          %w[representation locator path].map { |name| { name: name, in: "query", required: name == "path", schema: { type: "string" } } }
        else
          []
        end
        operation[:requestBody] = { required: true, content: { "application/json" => { schema: request_schema.call(route_path, verb.downcase) } } } if %w[post patch put].include?(verb.downcase)
      end
      api_route_paths[route_path][verb.downcase] = operation
    end

    path_parameters = route_path.scan(/\{([^}]+)\}/).flatten.map do |name|
      { name: name, in: "path", required: true, schema: { type: name == "id" ? "integer" : "string" } }
    end
    api_route_paths[route_path][:parameters] = path_parameters if path_parameters.any?
  end

  # Define one or more Swagger documents and provide global metadata for each one
  # When you run the 'rswag:specs:swaggerize' rake task, the complete Swagger will
  # be generated at the provided relative path under openapi_root
  # By default, the operations defined in spec files are added to the first
  # document below. You can override this behavior by adding a openapi_spec tag to the
  # the root example_group in your specs, e.g. describe '...', openapi_spec: 'v2/swagger.json'
  config.openapi_specs = {
    "v1.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Later, Bender browser API",
        version: "2026-09-17",
        description: "Generated from the Rails request contract specs."
      },
      paths: api_route_paths,
      servers: [
        {
          url: "https://{host}",
          variables: { host: { default: "laterbender.example" } }
        }
      ],
      tags: [
        { name: "Authentication" },
        { name: "Projects" },
        { name: "Tasks" },
        { name: "Notes" },
        { name: "Files" },
        { name: "Search" }
      ],
      components: {
        securitySchemes: {
          bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "opaque token" }
        },
        schemas: {
          Error: {
            type: "object",
            required: [ "error" ],
            properties: {
              error: {
                oneOf: [
                  { type: "string" },
                  {
                    type: "object",
                    required: [ "code", "message" ],
                    properties: {
                      code: { type: "string" },
                      message: { type: "string" },
                      details: { type: "object", additionalProperties: { type: "array", items: { type: "string" } } }
                    }
                  }
                ]
              }
            }
          },
          User: {
            type: "object",
            required: [ "id", "username" ],
            properties: { id: { type: "integer" }, username: { type: "string" } }
          },
          Session: {
            type: "object",
            required: [ "user", "token" ],
            properties: {
              user: { "$ref": "#/components/schemas/User" },
              token: { type: "string" }
            }
          },
          Project: {
            type: "object",
            required: [ "id", "name", "slug", "shorthand" ],
            properties: {
              id: { type: "integer" }, name: { type: "string" }, slug: { type: "string" },
              shorthand: { type: "string" }, description: { type: "string", nullable: true },
              archived_at: { type: "string", nullable: true, format: "date-time" }, task_count: { type: "integer" },
              created_at: { type: "string", format: "date-time" }, updated_at: { type: "string", format: "date-time" }
            }
          },
          Task: {
            type: "object",
            required: [ "id", "ref", "number", "title", "status", "position", "priority", "tags", "project" ],
            properties: {
              id: { type: "integer" }, ref: { type: "string" }, number: { type: "integer" }, title: { type: "string" },
              status: { type: "string", enum: [ "backlog", "ready", "doing", "done", "dropped" ] },
              position: { type: "integer" }, priority: { type: "string", enum: [ "low", "normal", "high" ] },
              context: { type: "string", nullable: true }, intended_direction: { type: "string", nullable: true },
              tags: { type: "array", items: { type: "string" } }, related_note_ids: { type: "array", items: { type: "integer" } },
              project: { "$ref": "#/components/schemas/Project" },
              created_at: { type: "string", format: "date-time" }, updated_at: { type: "string", format: "date-time" }
            }
          },
          Note: {
            type: "object",
            required: [ "id", "title", "body", "tags" ],
            properties: {
              id: { type: "integer" }, title: { type: "string" }, body: { type: "string" },
              tags: { type: "array", items: { type: "string" } }, project: { "$ref": "#/components/schemas/Project", nullable: true },
              created_at: { type: "string", format: "date-time" }, updated_at: { type: "string", format: "date-time" }
            }
          },
          SessionInput: { type: "object", required: %w[username code password password_confirmation], properties: { username: { type: "string" }, code: { type: "string" }, password: { type: "string", format: "password" }, password_confirmation: { type: "string", format: "password" } } },
          TokenCreateInput: { type: "object", properties: { name: { type: "string" } } },
          ApiToken: { type: "object", required: %w[id name created_at], properties: { id: { type: "integer" }, name: { type: "string" }, last_used_at: { type: "string", nullable: true, format: "date-time" }, revoked_at: { type: "string", nullable: true, format: "date-time" }, created_at: { type: "string", format: "date-time" } } },
          ApiTokenWithSecret: { allOf: [ { "$ref" => "#/components/schemas/ApiToken" }, { type: "object", required: [ "token" ], properties: { token: { type: "string" } } } ] },
          TotpCreateInput: { type: "object", required: [ "password" ], properties: { password: { type: "string", format: "password" }, label: { type: "string" } } },
          TotpConfirmInput: { type: "object", required: %w[password code], properties: { password: { type: "string", format: "password" }, code: { type: "string" } } },
          TotpCredential: { type: "object", required: %w[id label created_at], properties: { id: { type: "integer" }, label: { type: "string" }, created_at: { type: "string", format: "date-time" } } },
          TotpList: { type: "object", required: [ "credentials" ], properties: { credentials: { type: "array", items: { "$ref" => "#/components/schemas/TotpCredential" } } } },
          TotpCreate: { type: "object", required: %w[credential secret provisioning_uri qr_svg_base64], properties: { credential: { type: "object", properties: { id: { type: "integer" }, label: { type: "string" } } }, secret: { type: "string" }, provisioning_uri: { type: "string" }, qr_svg_base64: { type: "string" } } },
          TotpConfirmation: { type: "object", required: [ "credential" ], properties: { credential: { "$ref" => "#/components/schemas/TotpCredential" } } },
          TokenInfo: { type: "object", required: %w[active user_id client_id scope exp], properties: { active: { type: "boolean" }, user_id: { type: "integer" }, client_id: { type: "string" }, scope: { type: "string" }, exp: { type: "integer" } } },
          ProjectInput: { type: "object", properties: { name: { type: "string" }, slug: { type: "string" }, shorthand: { type: "string" }, description: { type: "string" }, archived_at: { type: "string", nullable: true, format: "date-time" } } },
          TaskInput: { type: "object", properties: { title: { type: "string" }, status: { type: "string" }, position: { type: "integer" }, priority: { type: "string" }, context: { type: "string" }, intended_direction: { type: "string" }, tags: { type: "array", items: { type: "string" } }, related_note_ids: { type: "array", items: { type: "integer" } }, citations: { type: "array", items: { type: "object", additionalProperties: true } } } },
          NoteInput: { type: "object", properties: { title: { type: "string" }, body: { type: "string" }, project: { type: "string", nullable: true }, tags: { type: "array", items: { type: "string" } }, citations: { type: "array", items: { type: "object", additionalProperties: true } } } },
          FileCreateInput: { type: "object", properties: { file: { type: "object", additionalProperties: true }, url: { type: "string", format: "uri" }, filename: { type: "string" }, tags: { type: "array", items: { type: "string" } }, related_task_refs: { type: "array", items: { type: "string" } }, related_note_ids: { type: "array", items: { type: "integer" } }, citations: { type: "array", items: { type: "object", additionalProperties: true } } } },
          FileUpdateInput: { type: "object", properties: { filename: { type: "string" }, tags: { type: "array", items: { type: "string" } }, related_task_refs: { type: "array", items: { type: "string" } }, related_note_ids: { type: "array", items: { type: "integer" } }, citations: { type: "array", items: { type: "object", additionalProperties: true } } } },
          ArchiveExtractInput: { type: "object", required: [ "path" ], properties: { path: { type: "string" }, filename: { type: "string" }, tags: { type: "array", items: { type: "string" } } } },
          FileRefAck: { type: "object", required: %w[ref updated_at], properties: { ref: { type: "string" }, updated_at: { type: "string", format: "date-time" } } },
          FileDeleteAck: { type: "object", required: [ "ref" ], properties: { ref: { type: "string" } } },
          NoteDeleteAck: { type: "object", required: [ "id" ], properties: { id: { type: "integer" } } },
          SearchResult: { type: "object", required: %w[id kind title tags snippet], properties: { id: { type: "integer" }, ref: { type: "string", nullable: true }, number: { type: "integer", nullable: true }, kind: { type: "string", enum: %w[task note file] }, title: { type: "string" }, filename: { type: "string", nullable: true }, media_type: { type: "string", nullable: true }, project: { "$ref" => "#/components/schemas/Project", nullable: true }, tags: { type: "array", items: { type: "string" } }, status: { type: "string", nullable: true }, priority: { type: "string", nullable: true }, snippet: { type: "string" }, highlights: { type: "array", items: { type: "object", additionalProperties: true } }, created_at: { type: "string", format: "date-time" }, updated_at: { type: "string", format: "date-time" } } },
          SearchResponse: { type: "object", required: %w[results total], properties: { results: { type: "array", items: { "$ref" => "#/components/schemas/SearchResult" } }, total: { type: "integer" } } },
          FileSummary: { type: "object", required: %w[ref filename media_type byte_size sha256 tags project], properties: { ref: { type: "string" }, number: { type: "integer" }, filename: { type: "string" }, media_type: { type: "string" }, byte_size: { type: "integer" }, sha256: { type: "string" }, tags: { type: "array", items: { type: "string" } }, project: { type: "object", required: %w[slug shorthand name], properties: { slug: { type: "string" }, shorthand: { type: "string" }, name: { type: "string" } } }, created_at: { type: "string", format: "date-time" }, updated_at: { type: "string", format: "date-time" } } },
          StoredFile: { allOf: [ { "$ref" => "#/components/schemas/FileSummary" }, { type: "object", properties: { related_task_refs: { type: "array", items: { type: "string" } }, related_note_ids: { type: "array", items: { type: "integer" } }, representations: { type: "array", items: { type: "object", additionalProperties: true } }, provenance: { type: "object", nullable: true, additionalProperties: true } } } ] },
          FileRead: { type: "object", required: %w[kind representation], properties: { kind: { type: "string" }, representation: { type: "string" }, coordinate: { type: "string", nullable: true }, locator: { type: "object", nullable: true, additionalProperties: true }, media_type: { type: "string", nullable: true }, content: { type: "string", nullable: true }, metadata: { type: "object", additionalProperties: true }, source: { type: "object", required: %w[kind ref], properties: { kind: { type: "string" }, ref: { type: "string" } } } } },
          ArchiveEntryRead: { type: "object", required: [ "read" ], properties: { read: { "$ref" => "#/components/schemas/FileRead" } } },
          FileReadBatch: { type: "object", required: [ "results" ], properties: { results: { type: "array", items: { type: "object", required: %w[ref read], additionalProperties: true } } } },
          FileReadBatchInput: { type: "object", required: [ "reads" ], properties: { reads: { type: "array", items: { type: "object", required: [ "ref" ], properties: { ref: { type: "string" }, representation: { type: "string" }, locator: { type: "object", additionalProperties: true } } } } } },
          FileEgress: { type: "object", required: [ "file" ], properties: { file: { type: "object", required: %w[ref filename media_type byte_size sha256 download_path], properties: { ref: { type: "string" }, filename: { type: "string" }, media_type: { type: "string" }, byte_size: { type: "integer" }, sha256: { type: "string" }, download_path: { type: "string" } } } } },
          FileDownload: { type: "string", format: "binary" },
          ArchiveList: { oneOf: [ { type: "array", items: { type: "object", additionalProperties: true } }, { type: "object", required: %w[entries next_cursor], properties: { entries: { type: "array", items: { type: "object", additionalProperties: true } }, next_cursor: { type: "string", nullable: true } } } ] },
          ProjectList: { oneOf: [ { type: "array", items: { "$ref" => "#/components/schemas/Project" } }, { type: "object", required: %w[projects next_cursor], properties: { projects: { type: "array", items: { "$ref" => "#/components/schemas/Project" } }, next_cursor: { type: "string", nullable: true } } } ] },
          TaskList: { oneOf: [ { type: "array", items: { "$ref" => "#/components/schemas/Task" } }, { type: "object", required: %w[tasks next_cursor], properties: { tasks: { type: "array", items: { "$ref" => "#/components/schemas/Task" } }, next_cursor: { type: "string", nullable: true } } } ] },
          NoteList: { oneOf: [ { type: "array", items: { "$ref" => "#/components/schemas/Note" } }, { type: "object", required: %w[notes next_cursor], properties: { notes: { type: "array", items: { "$ref" => "#/components/schemas/Note" } }, next_cursor: { type: "string", nullable: true } } } ] },
          FileList: { oneOf: [ { type: "array", items: { "$ref" => "#/components/schemas/FileSummary" } }, { type: "object", required: %w[files next_cursor], properties: { files: { type: "array", items: { "$ref" => "#/components/schemas/FileSummary" } }, next_cursor: { type: "string", nullable: true } } } ] },
          CursorPage: {
            type: "object",
            required: [ "next_cursor" ],
            properties: { next_cursor: { type: "string", nullable: true } },
            additionalProperties: true
          }
        }
      }
    }
  }

  # Specify the format of the output Swagger file when running 'rswag:specs:swaggerize'.
  # The openapi_specs configuration option has the filename including format in
  # the key, this may want to be changed to avoid putting yaml in json files.
  # Defaults to json. Accepts ':json' and ':yaml'.
  config.openapi_format = :yaml
end
