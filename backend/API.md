# Later, Bender API

The backend is a small JSON API for a user-owned task backlog. It uses PostgreSQL and has users, projects, tasks, global reusable tags, and opaque bearer tokens.

## Search

`GET /api/search` performs authenticated unified natural-language search across the current user's tasks and notes. It accepts `q`, optional `project`, `kinds` (`task` and/or `note`), `tags`, and `limit` (maximum 100). Results are compact ranked records; Elasticsearch is disposable derived state and can be rebuilt with `bin/rails chewy:reset[search_documents]`.

## Authentication

Every `/api` route requires `Authorization: Bearer <token>`. Create the first local user and an API token:

```sh
USERNAME=local PASSWORD='a-long-password' bin/rails users:create
USERNAME=local NAME=codex bin/rails api_tokens:create
```

The raw token is printed once. The database stores only its SHA-256 digest. Tokens are owned by users and can also be managed through `/api/tokens`.

`POST /api/auth/login` accepts `username` and `password` and returns `{ user, token }`. The token is an opaque bearer credential and can be revoked with `DELETE /api/auth/logout` or `DELETE /api/tokens/:id`. `GET /api/auth/current` returns the authenticated user.

Optional TOTP recovery credentials are managed through `/api/account/totp`. Enrollment requires the current password and confirmation with a current code. `POST /api/auth/recover` accepts `username`, `code`, `password`, and `password_confirmation`; it revokes all existing bearer tokens before returning a fresh one. If no confirmed TOTP credential exists, password recovery is unavailable.

## Routes

Projects use their slug in URLs:

```text
GET    /api/projects
POST   /api/projects
GET    /api/projects/:slug
PATCH  /api/projects/:slug
GET    /api/projects/:slug/tasks
POST   /api/projects/:slug/tasks
GET    /api/projects/:slug/tasks/:id
PATCH  /api/projects/:slug/tasks/:id
DELETE /api/projects/:slug/tasks/:id
GET    /api/tasks
GET    /api/notes
POST   /api/notes
GET    /api/notes/:id
PATCH  /api/notes/:id
GET    /api/projects/:slug/notes
POST   /api/projects/:slug/notes
GET    /api/tokens
POST   /api/tokens
DELETE /api/tokens/:id
```

Projects are archived by setting `archived_at`; they are not deleted. Task deletion is permanent. A nested task URL always scopes the task to its project.

## Tasks and filtering

Task `status` is one of `backlog`, `ready`, `doing`, `done`, or `dropped`. `priority` is optional and is one of `low`, `normal`, or `high`. `context` describes why a task exists; `intended_direction` records the direction already decided when it was parked. Both are plain text and may contain Markdown.

`GET /api/tasks` and nested task listing accept `status`, `priority`, `tag`, and `q`. Global listing also accepts `project=<slug>`. Results use ascending canonical integer `position` (then `id`) for board order. Create and update accept `position`; omitted position appends a task to its status column. Search uses PostgreSQL `ILIKE` across `title`, `context`, and `intended_direction`.

## Notes

Notes are durable context. A note always belongs to the authenticated user and may either be projectless (global user-level context) or belong to one of that user's projects. Use `GET /api/notes?projectless=true` (or `scope=global`) for global notes, `GET /api/notes?project=<slug>` or the nested project route for project notes. Notes have `title`, `body`, optional `project` slug, and optional reusable `tags`; updating `project` to `null` makes a note projectless. Note deletion is not supported.

Tasks accept `related_note_ids`, an array of globally unique note IDs. On create those notes are associated; on update the field replaces the complete relation set, and an empty array clears it. Omitting the field preserves existing relations. Task responses expose the current IDs in `related_note_ids`. Notes and tasks must belong to the same user.

## Tags

Create or update a task with an explicit `tags` array. Tags are normalized to lowercase names and created on use. On an update, `tags` replaces all current associations; omit `tags` to leave associations unchanged; use `"tags": []` to remove them. The operation is transactional.

```json
{
  "title": "Deploy the API",
  "status": "backlog",
  "priority": "high",
  "context": "The first production release still needs a repeatable deployment path.",
  "intended_direction": "Start with a boring container deployment.",
  "tags": ["deployment", "rails"]
}
```

Successful task responses include the task fields, tag names, project identity (`id`, `name`, `slug`), and timestamps. Errors use JSON such as:

```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "details": { "status": ["is not included in the list"] }
  }
}
```
