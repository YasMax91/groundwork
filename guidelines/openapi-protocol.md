# OpenAPI protocol (RaDevs) — the spec is part of the contract, not documentation afterwards

The published OpenAPI/Swagger document is the contract the frontend and every external consumer read.
It must be **current** (never behind the code) and **complete to the last detail** (never a bare
`summary` over an undocumented payload). A contract change without a spec change is an unfinished
change — the `openapi` Stop gate enforces this, and the Definition of Done in
[ai-sdd-process.md](ai-sdd-process.md) requires it.

Toolchain in these projects: `darkaonline/l5-swagger` (or `zircote/swagger-php` directly) — the spec
is generated from PHP attributes `#[OA\...]` or docblock annotations `@OA\...` on controllers and
schema classes. Both styles are valid; match whichever the file already uses.

## Never invent — derive every part from real code

Each part of an operation has exactly one source of truth in the codebase. Read it; do not guess.

| Spec part | Source of truth |
| --- | --- |
| path · method · route params | `routes/api.php` (confirm with `route:list`) |
| request fields · types · required · limits | the **FormRequest** `rules()` — every rule maps to a constraint |
| response shape | the **JsonResource** `toArray()`, including nested resources and wrappers |
| enum values | the backing **PHP enum** — list the real cases, never a free-text string |
| status codes | the controller/service paths, policies, and exception handling that can actually run |
| auth scheme | the route's middleware/guard (`auth:sanctum`, ability/permission middleware) |
| pagination shape | the paginator actually returned (`data` + `links` + `meta`, or the custom wrapper) |

If a field's meaning is not derivable from code, ask — do not document a guess.

## Per-operation completeness checklist

Every public endpoint carries an operation that has **all** of it:

- `operationId` (unique, stable), `tags` (the feature area), `summary` (one line, imperative).
- `description` — what it does, when to call it, side effects, and any state it transitions.
- `security` — the scheme, or explicitly public. Never left implicit for a protected route.
- **Parameters** — every path/query/header param: `name`, `in`, `required`, typed `schema`,
  `description`, `example`; `enum` where the values are closed; filter/sort/pagination params too.
- **Request body** — every field from the FormRequest: type, `required` list, `format`
  (`date`, `email`, `uuid`, `decimal`), `minimum`/`maximum`/`maxLength`, `enum`, `nullable`,
  `description`, and a realistic `example`. Nested objects and arrays get their `items` schema.
- **Responses — every status the endpoint can actually return**, each with a schema and an example:
  - the success code (`200`/`201`/`204` — the real one, not a default `200`),
  - `401` when auth applies, `403` when a policy/permission applies, `404` when a route-model bind
    or lookup can miss, `409` for a guarded state transition that can be rejected,
  - `422` with the **validation-error schema** (`message` + `errors` keyed by field) whenever a
    FormRequest runs,
  - any `429`/`5xx` the project documents by convention.
- **Response schema = the real resource shape**, field by field, with types, `nullable`, formats and
  enums. Money keeps its decimal-string representation. Hidden/conditional fields are described as
  conditional, with the condition.
- `deprecated: true` plus the replacement in `description` when an endpoint or field is on the way out.

## Reuse, don't copy-paste

Shared shapes live in `#[OA\Schema]` components and are referenced with `ref`: resources
(`UserResource`, `OrderResource`), the validation-error envelope, the pagination envelope, common
enums. A copy-pasted inline schema drifts from the code the moment either side changes — one schema
per resource, referenced everywhere.

## Verification (not "it looks right")

1. Regenerate the spec — `./vendor/bin/sail artisan l5-swagger:generate` (or the project's
   `commands.openapi_generate`). It must finish **without errors or warnings**; swagger-php reports
   unresolved refs, duplicate `operationId`s, and malformed schemas here.
2. Diff-check: every route touched by the change has its operation updated in the same commit, and a
   field dropped from the code is dropped from the schema with it.
3. For a new endpoint, confirm it appears in the generated document — a route with no annotation
   generates nothing and silently ships undocumented.
4. **Audit the document, not just its freshness — public endpoints at L3/L4.** When the change adds or
   alters a publicly reachable operation and the `42crunch` plugin is installed, run its audit over the
   regenerated document and carry the OWASP-API findings (object-level authorization, missing
   authentication, unconstrained payloads) into the risk review as contract risks. A spec that matches
   the code can still describe an endpoint that hands out other tenants' objects — that is what this
   step catches and the drift check cannot. Not installed: say the audit did not run.

## Scope — this task, not the whole project

Auditing and repairing a project's whole spec — including pre-existing gaps that predate the current
task — is the `openapi-audit` skill's job; do not silently expand the current task into a
project-wide spec cleanup.
