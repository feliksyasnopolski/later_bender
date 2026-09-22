# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_22_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
    t.index ["record_type", "record_id", "name"], name: "index_active_storage_attachments_lookup"
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "citations", force: :cascade do |t|
    t.bigint "citing_id", null: false
    t.string "citing_type", null: false
    t.datetime "created_at", null: false
    t.jsonb "locator", default: {}, null: false
    t.string "representation_kind", null: false
    t.bigint "stored_file_id", null: false
    t.datetime "updated_at", null: false
    t.index ["citing_type", "citing_id"], name: "index_citations_on_citing"
    t.index ["citing_type", "citing_id"], name: "index_citations_on_citing_type_and_citing_id"
    t.index ["stored_file_id"], name: "index_citations_on_stored_file_id"
  end

  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "env_name"
    t.integer "file_mode"
    t.string "file_path"
    t.string "kind", null: false
    t.string "name", null: false
    t.integer "public_number", null: false
    t.string "ref", null: false
    t.text "secret", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index "user_id, lower((name)::text)", name: "index_credentials_on_user_and_lower_name", unique: true
    t.index ["ref"], name: "index_credentials_on_ref", unique: true
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "file_notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "note_id", null: false
    t.bigint "stored_file_id", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id"], name: "index_file_notes_on_note_id"
    t.index ["stored_file_id", "note_id"], name: "index_file_notes_on_stored_file_id_and_note_id", unique: true
    t.index ["stored_file_id"], name: "index_file_notes_on_stored_file_id"
  end

  create_table "file_representations", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "generator", null: false
    t.string "generator_version", null: false
    t.string "kind", null: false
    t.string "media_type"
    t.jsonb "metadata", default: {}, null: false
    t.string "status", default: "ready", null: false
    t.bigint "stored_file_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stored_file_id", "kind"], name: "index_file_representations_on_stored_file_id_and_kind", unique: true
    t.index ["stored_file_id"], name: "index_file_representations_on_stored_file_id"
  end

  create_table "file_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "stored_file_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stored_file_id", "tag_id"], name: "index_file_tags_on_stored_file_id_and_tag_id", unique: true
    t.index ["stored_file_id"], name: "index_file_tags_on_stored_file_id"
    t.index ["tag_id"], name: "index_file_tags_on_tag_id"
  end

  create_table "file_tasks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "stored_file_id", null: false
    t.bigint "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stored_file_id", "task_id"], name: "index_file_tasks_on_stored_file_id_and_task_id", unique: true
    t.index ["stored_file_id"], name: "index_file_tasks_on_stored_file_id"
    t.index ["task_id"], name: "index_file_tasks_on_task_id"
  end

  create_table "note_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "note_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id", "tag_id"], name: "index_note_tags_on_note_id_and_tag_id", unique: true
    t.index ["note_id"], name: "index_note_tags_on_note_id"
    t.index ["tag_id"], name: "index_note_tags_on_tag_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "project_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["project_id"], name: "index_notes_on_project_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "next_file_number", default: 1, null: false
    t.bigint "next_task_number", default: 1, null: false
    t.string "shorthand", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "shorthand"], name: "index_projects_on_user_id_and_shorthand", unique: true
    t.index ["user_id", "slug"], name: "index_projects_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "remote_agent_challenges", force: :cascade do |t|
    t.string "challenge_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "nonce_digest", null: false
    t.bigint "remote_agent_id", null: false
    t.datetime "updated_at", null: false
    t.index ["challenge_id"], name: "index_remote_agent_challenges_on_challenge_id", unique: true
    t.index ["remote_agent_id"], name: "index_remote_agent_challenges_on_remote_agent_id"
  end

  create_table "remote_agent_enrollment_tokens", force: :cascade do |t|
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_remote_agent_enrollment_tokens_on_digest", unique: true
    t.index ["user_id"], name: "index_remote_agent_enrollment_tokens_on_user_id"
  end

  create_table "remote_agent_sessions", force: :cascade do |t|
    t.datetime "connected_at", null: false
    t.datetime "created_at", null: false
    t.datetime "disconnected_at"
    t.bigint "generation", default: 0, null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "remote_agent_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["remote_agent_id", "disconnected_at"], name: "idx_on_remote_agent_id_disconnected_at_1cc0276ba4"
    t.index ["remote_agent_id"], name: "index_remote_agent_sessions_on_remote_agent_id"
    t.index ["token_digest"], name: "index_remote_agent_sessions_on_token_digest", unique: true
  end

  create_table "remote_agents", force: :cascade do |t|
    t.string "architecture", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.string "platform", null: false
    t.text "public_key", null: false
    t.integer "public_number", null: false
    t.string "ref", null: false
    t.datetime "revoked_at"
    t.bigint "session_generation", default: 0, null: false
    t.jsonb "supported_executors", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "public_number"], name: "index_remote_agents_on_user_id_and_public_number", unique: true
    t.index ["user_id", "ref"], name: "index_remote_agents_on_user_id_and_ref", unique: true
    t.index ["user_id"], name: "index_remote_agents_on_user_id"
  end

  create_table "remote_workspace_placements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "executor", null: false
    t.string "operation_id", null: false
    t.string "operation_kind", default: "prepare", null: false
    t.datetime "prepared_at"
    t.string "provider_workspace_ref"
    t.bigint "remote_agent_id", null: false
    t.jsonb "spec", default: {}, null: false
    t.string "spec_hash", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["operation_id"], name: "index_remote_workspace_placements_on_operation_id", unique: true
    t.index ["remote_agent_id", "state"], name: "index_remote_workspace_placements_on_remote_agent_id_and_state"
    t.index ["remote_agent_id"], name: "index_remote_workspace_placements_on_remote_agent_id"
    t.index ["workspace_id"], name: "index_remote_workspace_placements_on_workspace_id", unique: true
  end

  create_table "stored_files", force: :cascade do |t|
    t.string "archive_entry_path"
    t.bigint "archive_source_id"
    t.bigint "byte_size", null: false
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "media_type", null: false
    t.bigint "number", null: false
    t.jsonb "origin"
    t.bigint "project_id", null: false
    t.string "sha256", null: false
    t.datetime "updated_at", null: false
    t.index ["archive_source_id"], name: "index_stored_files_on_archive_source_id"
    t.index ["project_id", "number"], name: "index_stored_files_on_project_id_and_number", unique: true
    t.index ["project_id"], name: "index_stored_files_on_project_id"
    t.check_constraint "archive_source_id IS NULL AND archive_entry_path IS NULL OR archive_source_id IS NOT NULL AND archive_entry_path IS NOT NULL", name: "stored_files_archive_provenance_complete"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
    t.index ["slug"], name: "index_tags_on_slug", unique: true
  end

  create_table "task_notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "note_id", null: false
    t.bigint "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id"], name: "index_task_notes_on_note_id"
    t.index ["task_id", "note_id"], name: "index_task_notes_on_task_id_and_note_id", unique: true
    t.index ["task_id"], name: "index_task_notes_on_task_id"
  end

  create_table "task_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.bigint "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_task_tags_on_tag_id"
    t.index ["task_id", "tag_id"], name: "index_task_tags_on_task_id_and_tag_id", unique: true
    t.index ["task_id"], name: "index_task_tags_on_task_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.text "context"
    t.datetime "created_at", null: false
    t.text "intended_direction"
    t.bigint "number", null: false
    t.bigint "position", null: false
    t.string "priority"
    t.bigint "project_id", null: false
    t.string "status", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "number"], name: "index_tasks_on_project_id_and_number", unique: true
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["status", "position", "id"], name: "index_tasks_on_status_and_position_and_id"
  end

  create_table "totp_credentials", force: :cascade do |t|
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "label", default: "Authenticator", null: false
    t.datetime "last_used_at"
    t.bigint "last_used_counter"
    t.text "secret", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_totp_credentials_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "encrypted_password", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index "lower((username)::text)", name: "index_users_on_lower_username", unique: true
  end

  create_table "workspace_events", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "occurred_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "sequence", null: false
    t.bigint "workspace_id", null: false
    t.index ["workspace_id", "sequence"], name: "index_workspace_events_on_workspace_id_and_sequence", unique: true
    t.index ["workspace_id"], name: "index_workspace_events_on_workspace_id"
  end

  create_table "workspace_executions", force: :cascade do |t|
    t.string "cancel_operation_id"
    t.datetime "created_at", null: false
    t.string "cwd", default: "/workspace", null: false
    t.jsonb "env", default: {}, null: false
    t.integer "exit_code"
    t.datetime "finished_at"
    t.jsonb "invocation", default: {}, null: false
    t.string "ref", null: false
    t.string "remote_operation_id"
    t.jsonb "remote_spec", default: {}, null: false
    t.decimal "requested_timeout_seconds"
    t.jsonb "secret_env_names", default: [], null: false
    t.integer "sequence", null: false
    t.string "spec_hash"
    t.datetime "started_at", null: false
    t.string "state", default: "running", null: false
    t.binary "stderr_data"
    t.string "stderr_handle", null: false
    t.binary "stdout_data"
    t.string "stdout_handle", null: false
    t.string "terminating_signal"
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["cancel_operation_id"], name: "index_workspace_executions_on_cancel_operation_id", unique: true
    t.index ["ref"], name: "index_workspace_executions_on_ref", unique: true
    t.index ["remote_operation_id"], name: "index_workspace_executions_on_remote_operation_id", unique: true
    t.index ["workspace_id", "sequence"], name: "index_workspace_executions_on_workspace_id_and_sequence", unique: true
    t.index ["workspace_id"], name: "index_workspace_executions_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "architecture", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "credential_bindings", default: [], null: false
    t.string "environment", null: false
    t.datetime "expires_at"
    t.string "label"
    t.datetime "last_activity_at", null: false
    t.string "legacy_ref"
    t.jsonb "limits", default: {}, null: false
    t.string "os_name", null: false
    t.string "os_version", null: false
    t.integer "public_number"
    t.string "ref", null: false
    t.string "runner_handle"
    t.string "shell", null: false
    t.string "state", default: "starting", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "workspace_root", default: "/workspace", null: false
    t.index ["legacy_ref"], name: "index_workspaces_on_legacy_ref"
    t.index ["user_id", "public_number"], name: "index_workspaces_on_user_id_and_public_number", unique: true
    t.index ["user_id", "ref"], name: "index_workspaces_on_user_id_and_ref", unique: true
    t.index ["user_id", "state"], name: "index_workspaces_on_user_id_and_state"
    t.index ["user_id"], name: "index_workspaces_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "citations", "stored_files"
  add_foreign_key "credentials", "users"
  add_foreign_key "file_notes", "notes"
  add_foreign_key "file_notes", "stored_files"
  add_foreign_key "file_representations", "stored_files"
  add_foreign_key "file_tags", "stored_files"
  add_foreign_key "file_tags", "tags"
  add_foreign_key "file_tasks", "stored_files"
  add_foreign_key "file_tasks", "tasks"
  add_foreign_key "note_tags", "notes"
  add_foreign_key "note_tags", "tags"
  add_foreign_key "notes", "projects"
  add_foreign_key "notes", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "projects", "users"
  add_foreign_key "remote_agent_challenges", "remote_agents"
  add_foreign_key "remote_agent_enrollment_tokens", "users"
  add_foreign_key "remote_agent_sessions", "remote_agents"
  add_foreign_key "remote_agents", "users"
  add_foreign_key "remote_workspace_placements", "remote_agents"
  add_foreign_key "remote_workspace_placements", "workspaces"
  add_foreign_key "stored_files", "projects"
  add_foreign_key "stored_files", "stored_files", column: "archive_source_id"
  add_foreign_key "task_notes", "notes"
  add_foreign_key "task_notes", "tasks"
  add_foreign_key "task_tags", "tags"
  add_foreign_key "task_tags", "tasks"
  add_foreign_key "tasks", "projects"
  add_foreign_key "totp_credentials", "users"
  add_foreign_key "workspace_events", "workspaces"
  add_foreign_key "workspace_executions", "workspaces"
  add_foreign_key "workspaces", "users"
end
