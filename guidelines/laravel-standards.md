# Laravel standards (Groundwork)

Curated, opinionated standards for Laravel backends. Stay on the framework's grain. Confirm
version-specific details with Boost `search-docs` for the installed version rather than recalling them.

**What the engine holds.** Six rules are enforced by hooks: breaking one is denied outright, or the task
cannot end.

| Rule | Hook | Opt-out |
|---|---|---|
| Laravel/PHP commands go through the runner, not the host | `hooks/pre-tool-guard.sh` | `gates.enforce_runner` |
| A shipped (git-tracked) migration is never edited | `hooks/pre-tool-guard.sh` | `gates.lock_shipped_migrations` |
| Formatting runs on every edit | `hooks/format-on-edit.sh` | `gates.format_on_edit` |
| Static analysis passes before "done" — and a no-op analyser is refused, not counted as clean | `hooks/done-gate.sh` | `gates.analyse_on_stop` + `gates.analyse_skip_reason` |
| The suite passes before "done"; a suite resolving to SQLite on a project that targets another engine is reported | `hooks/test-gate.sh` | `gates.test_on_stop` |
| The OpenAPI document moves together with an API change | `hooks/openapi-gate.sh` | `gates.openapi_on_stop` |
| `env()` is never read outside `config/`, and money is never `float`/`double` in a migration | `hooks/defect-scan.sh` | `gates.defect_scan` |
| A suite that resolves to SQLite on a project targeting another engine is refused, not run | `hooks/test-gate.sh` | `gates.sqlite_tests_reason` (a stated reason downgrades it to a notice) |

Three further defect classes are **reported, not blocked**, by `hooks/defect-scan.sh`, because each one
has a legitimate shape: an irreversible side effect (mail, a notification, an outbound HTTP call) inside
a transaction; a queued or broadcast event dispatched inside a transaction without
`ShouldDispatchAfterCommit`; a job with no `$tries`, `$backoff`, `retryUntil` or `failed()`.

**Everything else on this page is an instruction to the agent, and nothing checks it automatically** —
thin controllers, logic in `app/Services`, transactions around multi-step writes, guarded transitions,
money as decimal or integer cents, ULIDs at the edge, DB-level integrity, the anti-patterns. They are
caught, if at all, by review: `agents/conformance-reviewer.md` against the spec's acceptance criteria,
and `skills/risk-review`. A rule worth following is worth writing down; claiming a gate it does not have
is the failure this plugin exists to prevent (`guidelines/ai-sdd-process.md`).

## Framework baseline

**Resolve the versions from the project, never from memory.** `composer.lock` is the authority for what
is actually installed (`laravel/framework`, `php`), and Boost `application-info` reports it directly.
Confirm version-specific APIs with Boost `search-docs` against that version.

Support policy, verbatim from [laravel.com/docs/releases](https://laravel.com/docs/releases), checked
**2026-08-27** — re-read it rather than trusting this copy if the date is far behind:

| Version | PHP | Released | Bug fixes until | Security fixes until |
|---|---|---|---|---|
| 11 | 8.2 – 8.4 | 2024-03-12 | 2025-09-03 | **2026-03-12 — ended** |
| 12 | 8.2 – 8.5 | 2025-02-24 | **2026-08-13 — ended** | 2027-02-24 |
| 13 | 8.3 – 8.5 | 2026-03-17 | Q3 2027 | 2028-03-17 |

A project outside the bug-fix window still receives security patches until the later date, and nothing
else: a framework bug found there will not be fixed upstream. That is a fact for the discovery
interview and a task of its own — never a silent decision taken inside an unrelated change. The
`SessionStart` hook states it once per session for a project in that position.

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
- **Tests**: the project's own runner — Pest when `pestphp/pest` is in `composer.json`, PHPUnit
  otherwise; both run through `artisan test` (`./vendor/bin/sail artisan test`), which is what the gate
  invokes. Feature tests for API/validation/
  authorization/response shape; unit tests for services and calculations; a regression test for
  every bug fix. Write them **test-first** for L2+ features and bug fixes — see
  [tdd-protocol.md](tdd-protocol.md).
- Use Boost tools for schema, docs, and version facts instead of guessing.
