# TDD protocol (RaDevs) — test-first by default

Test-first discipline for RaDevs Laravel work. Read together with
[ai-sdd-process.md](ai-sdd-process.md), [laravel-standards.md](laravel-standards.md), and
[grounding-protocol.md](grounding-protocol.md). The standards say *what* to test and which gate
enforces it; this protocol says *when to write it* — first.

## The cycle

**Red → Green → Refactor.** Write a failing test for the next slice of intended behavior, watch it
fail for the right reason, write the minimum code to pass, then refactor under green with the gates
holding shape. One slice at a time.

## When it's mandatory

- **L2+ features** and **bug fixes (any level)**: test-first is required. A bug fix starts with a
  failing regression test that reproduces the defect.
- **L0 / non-bugfix L1**: optional — encouraged, not enforced.
- Test-first applies to the behavior you are changing. You do not retro-fit tests onto untouched
  code to "earn" the right to edit.

## Layered style (match the test to the layer)

The laravel-standards already split the suite — *feature tests for API/validation/authorization/
response shape; unit tests for services and calculations*. TDD keeps that split and adds order: write
the test for a layer **before** the code for that layer.

- **Feature-first (outer loop)** — start every covered task with a failing feature test that asserts
  the observable contract: route + HTTP status, validation (422 shape), authorization (401/403), and
  the `JsonResource` response shape. This is the acceptance criterion made executable. Hit the real
  DB **on the project's engine** (`RefreshDatabase` against the MySQL/Postgres declared in
  `.groundwork.json` `database.default` — **not** in-memory SQLite; a green on SQLite is a false
  green for an engine-specific defect), use factories, do **not** mock Eloquent.
- **Unit-first (inner loop)** — for non-trivial domain logic, drive it with unit tests first: service
  methods, money/financial calculation, guarded state transitions, enum behavior — anything with
  branches worth pinning. These are the L3/L4 risk surfaces; they earn the tighter loop.
- **Trivial CRUD** — the feature loop is enough; do not add unit tests just to hit a number.

So a feature's outer red is a feature test; its calculations and transitions get their own inner
red→green first; the controller stays thin and is covered by the feature test.

## What each step means (no theater)

- **Red is a real failure.** The test must fail because the behavior is missing — a meaningful
  assertion failure — not a typo, a missing import, or a parse/compile error. If it errors before
  reaching the assertion, it is not red yet.
- **Green is the minimum.** Write just enough to pass. Resist building unrequested branches; the next
  red will ask for them.
- **Refactor is under green.** Improve names, extract methods, remove duplication only while the
  suite stays green and Pint/Larastan stay clean. No behavior change without a test that asked for it.

## Bug fixes

Reproduce first: a failing test that exercises the wrong behavior (red), then the smallest safe fix
(green). The test must fail *before* the fix — a test written after the fix and green on its first
run proves nothing. This is what the `bugfix.md` template's regression section requires.

## External integrations

Grounding requires executable proof before "done". The TDD cycle *is* that proof when written first:
the failing feature test (or a sandbox/Tinker call captured as a test) exercises the real path. A
capability still marked `UNKNOWN` must be resolved with the user before you write its red test — do
not encode a guess.

## Gates

- **Green is enforced.** The Stop gate runs the test suite on changed PHP (`gates.test_on_stop`,
  default on; Sail-aware — an unavailable environment never blocks). You cannot declare done with red
  or missing tests. The gate also **warns when the suite resolves to SQLite/`:memory:`** while the
  project targets MySQL/Postgres — that green does not count; rerun on the real engine.
- **Red→Green is reported.** The handoff states, for the behavior changed, that the test failed
  before the code and passes after. The gate proves green; the report proves the order.

## Don't

- No production code for a covered task before a failing test exists for the slice.
- No test written after the fact and green on its first run, passed off as red→green.
- No mocking Eloquent / the framework to force a unit test where a feature test is the right tool.
- No bending the test to match a bug, or loosening an assertion just to reach green.
