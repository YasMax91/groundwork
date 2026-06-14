# Laravel standards (RaDevs)

Curated, opinionated standards for Laravel backends. Stay on the framework's grain; the standards are
enforced by tool-gates (Pint / Larastan / PHPUnit). Confirm version-specific details with Boost
`search-docs` for the installed version rather than recalling them.

## Architecture

- **Thin controllers**: validated input → service call → resource response → HTTP status. No domain
  logic in controllers.
- **Business logic in `app/Services`**: state transitions, financial calculation, workflow movement
  live there — not in controllers, requests, resources, or models.
- **FormRequest** for validation + request authorization. **JsonResource** for response shape.
- **Models** hold relationships, casts, scopes, accessors, and small local helpers only — not
  service-object logic.
- Wrap **multi-step domain writes in DB transactions** (orders, payments, movements, QC, etc.).
- Keep **external integrations behind dedicated clients/services** — never call them from
  controllers or models.
- Whitelist **list filters/sorting**; eager-load relationships intentionally to avoid N+1; enable
  `Model::preventLazyLoading()` in non-production so N+1 throws in tests.

## Data & domain modeling

- **Statuses/states**: native backed enums, cast in the model. No magic strings.
- **Workflow/order state**: guarded transitions — an explicit allowed-transition map that rejects
  invalid moves. Consider `spatie/laravel-model-states`.
- **Money**: never `float`. Use decimal columns or integer cents; preserve decimal-string behavior in
  API resources.
- **Externally exposed identifiers**: prefer ULIDs over leaking sequential auto-increment ids.
- **DB-level integrity**: foreign keys with explicit `onDelete`, unique indexes, and check
  constraints — not validation alone.
- **Migrations**: additive and production-safe; nullable/backfilled columns; never edit
  shipped migrations; add indexes for new query patterns.

## Don't (anti-patterns)

- No Repository pattern wrapping Eloquent; no DDD/hexagonal/CQRS for an API monolith. Add structure
  only when it removes real complexity or isolates a real external dependency.
- No invented business rules — derive them from the CRD, existing code, or an explicit user decision.

## Tooling / gates

- **Format**: Pint (`sail pint`) — runs automatically on edit via the plugin hook.
- **Static analysis**: Larastan / PHPStan (`sail composer analyse`) — the done-gate; catches the
  "wrong shape / 500 to the frontend" class early.
- **Tests**: PHPUnit (`sail artisan test`) — feature tests for API/validation/authorization/response
  shape; unit tests for services and calculations; a regression test for every bug fix.
- Use Boost tools for schema, docs, and version facts instead of guessing.
