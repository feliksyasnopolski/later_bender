# Later, Bender API

The backend is a small JSON API for a single-owner task backlog. It uses PostgreSQL and has four domain objects: projects own tasks; tags are global and reusable through the task-tags join; and API tokens authenticate clients. There are no users, teams, sessions, or frontend routes.

## Authentication

Every `/api` route requires `Authorization: Bearer <token>`. Create a token locally:

```sh
NAME=codex bin/rails api_tokens:create
```

The raw token is printed once. The database stores only its SHA-256 digest. Revoke a token from the Rails console with `ApiToken.find(id).update!(revoked_at: Time.current)`.

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
```

Projects are archived by setting `archived_at`; they are not deleted. Task deletion is permanent. A nested task URL always scopes the task to its project.

## Tasks and filtering

Task `status` is one of `backlog`, `ready`, `doing`, `done`, or `dropped`. `priority` is optional and is one of `low`, `normal`, or `high`. `context` describes why a task exists; `intended_direction` records the direction already decided when it was parked. Both are plain text and may contain Markdown.

`GET /api/tasks` and nested task listing accept `status`, `priority`, `tag`, and `q`. Global listing also accepts `project=<slug>`. Search uses PostgreSQL `ILIKE` across `title`, `context`, and `intended_direction`.

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
