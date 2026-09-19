# Later, Bender browser API contract

The executable browser API contract is generated from the Rails request specs
in [`spec/integration/openapi_spec.rb`](spec/integration/openapi_spec.rb).
The versioned artifact is [`openapi/v1.yaml`](openapi/v1.yaml); regenerate it
with:

```sh
cd backend
bundle exec rake rswag:specs:swaggerize
```

The request specs validate documented status codes and response schemas against
the Rails controllers. CI regenerates the artifact, validates it with
`openapi_parser` in strict reference mode, and fails if it differs from the
checked-in artifact.

## Contract rules not expressible in OpenAPI alone

- JSON endpoints are under `/api`; authenticated routes accept opaque bearer
  tokens from local `ApiToken` credentials or accessible OAuth access tokens.
- Authentication and ownership failures intentionally avoid revealing whether
  another user’s resource exists.
- Canonical resources are user-scoped. Projects use slugs, tasks expose stable
  project-local refs such as `WR-12`, and files expose immutable refs such as
  `WR-F1`.
- Omitted relationship arrays preserve existing relationships on PATCH;
  supplying an array replaces them, and `[]` clears them.
- Cursor values are signed, opaque, and bound to their filters and ordering.
- Files are immutable source artifacts. Metadata, relationships, readable
  representations, archive inspection, and downloads are separate surfaces.
- Search indexes and semantic representations are derived state; canonical
  writes do not depend on indexing success.

Rails controllers and request specs remain authoritative for behavior that
cannot be represented by OpenAPI, including ownership scoping, transactional
relationship replacement, cursor binding, archive safety, and optimistic note
edit conflicts.
