# Laravel standards (Groundwork)

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

## Database engine

- **Target MySQL (primary) or PostgreSQL** — whichever the project actually runs. The engine is
  declared in `.groundwork.json` `database.default` and recorded in `AGENTS.md`; honor it. **Never
  default to SQLite** and do not assume SQLite semantics.
- **Tests run on the project's engine, not in-memory SQLite** — a green on SQLite is a false green
  for an engine-specific defect. See [tdd-protocol.md](tdd-protocol.md).
- **Engine-specific surfaces** — confirm against the target engine with Boost `search-docs` for the
  installed version: column changes in migrations (`change()` / drop-recreate), foreign-key
  enforcement, JSON columns & functions, `LIKE`/`ILIKE` case-sensitivity, `enum`, fullText indexes,
  `decimal`/money precision, date/time functions. What SQLite silently tolerates, MySQL or Postgres
  may reject.

## Don't (anti-patterns)

- No Repository pattern wrapping Eloquent; no DDD/hexagonal/CQRS for an API monolith. Add structure
  only when it removes real complexity or isolates a real external dependency.
- No invented business rules — derive them from the CRD, existing code, or an explicit user decision.

## Tooling / gates

- **Run every Laravel/PHP command through Sail locally** — `artisan`, `composer`, Pint, Larastan,
  tests, `tinker`, `migrate`, `make:*`, queue/scheduler, everything. Never invoke `php`, `composer`,
  `artisan`, or `phpunit`/`pest` directly on the host. The runner is `sail` by default
  (`.groundwork.json` `runner`); honor a project override there. **Enforced** by the plugin's
  `PreToolUse` guard (`gates.enforce_runner`, default on) — a host invocation is denied with the
  corrected runner command. Editing a shipped (git-tracked) migration is likewise blocked
  (`gates.lock_shipped_migrations`, default on).
- **Format**: Pint (`./vendor/bin/sail pint`) — runs automatically on edit via the plugin hook.
- **Static analysis**: Larastan / PHPStan (`./vendor/bin/sail composer analyse`) — the done-gate;
  catches the "wrong shape / 500 to the frontend" class early. A project without an analyser says so
  (`gates.analyse_on_stop: false` **plus** `gates.analyse_skip_reason`) rather than pointing
  `commands.analyse` at `echo` or `true`: a no-op exits 0, which had the gate reporting a clean
  analysis for a project that had none. The gate refuses a no-op command outright.
- **Tests**: PHPUnit (`./vendor/bin/sail artisan test`) — feature tests for API/validation/
  authorization/response shape; unit tests for services and calculations; a regression test for
  every bug fix. Write them **test-first** for L2+ features and bug fixes — see
  [tdd-protocol.md](tdd-protocol.md).
- Use Boost tools for schema, docs, and version facts instead of guessing.
