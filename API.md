# Later, Bender API

The backend is a small JSON API for a user-owned task backlog. It uses PostgreSQL and has users, projects, tasks, global reusable tags, and opaque bearer tokens.

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
GET    /api/tokens
POST   /api/tokens
DELETE /api/tokens/:id
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
