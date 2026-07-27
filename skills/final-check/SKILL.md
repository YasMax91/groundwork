---
description: Run the final AI-SDD self-review before handing off backend work — run format, static analysis, and targeted tests, verify the Definition of Done, and produce the handoff summary.
---

# Final check

Run the gates and the self-review before declaring the work done. Use the project's commands
(from `.groundwork.json`, defaulting to Sail).

## Run the gates

- Format: `./vendor/bin/sail composer format:test` (or `format` to apply).
- Static analysis: `./vendor/bin/sail composer analyse`.
- Tests: the narrowest relevant first, then broader — e.g.
  `./vendor/bin/sail artisan test --filter=...`, then `./vendor/bin/sail composer test`. They must be
  **green** — the Stop gate also runs the suite on changed PHP (`gates.test_on_stop`). Confirm the
  tests for the changed behavior were written **test-first** (red→green).
- OpenAPI: if the change touched an endpoint, regenerate the spec
  (`./vendor/bin/sail artisan l5-swagger:generate`) — it must finish with **no errors and no
  warnings**, and every touched endpoint must be documented to the standard in
  `${CLAUDE_SKILL_DIR}/../../guidelines/openapi-protocol.md`. The `openapi` Stop gate enforces this;
  if the change provably does not touch the contract, record `- OpenAPI: n/a — <reason>` in the
  checkpoint rather than working around the gate.

Report results honestly. If a gate could not run (Sail/services unavailable), say so explicitly.

## Live verification (green gates are necessary, not sufficient)

The gates prove the code satisfies the tests and the static rules; they do **not** prove the running app
does what the user will see. Before "done", exercise the changed behavior against the **running** app the
way a user hits it. Scope it to the surface that changed — an API route gets an HTTP run, an admin/UI/CSS
change gets a browser run, a pure internal refactor gets neither.

- **API / feature endpoint — a real HTTP run.** Call the endpoint on the running app (curl / an HTTP
  client, or a real client inside `./vendor/bin/sail artisan tinker`) with realistic input, and capture
  the **actual** status + body. A green feature test does **not** satisfy this — the point is the wire,
  the middleware stack, the real DB, and the serialized response a client receives (the unqualified-column
  join that passes phpunit and 500s live is exactly what this catches). If the app is not served this
  session, fall back to the closest real exercise (`$this->getJson(...)` against the HTTP kernel) and say
  the wire was not hit.
- **Admin / UI / CSS — a real browser.** When a browser-driving tool is available (e.g. the
  `claude-in-chrome` MCP), open the actual screen and verify what the gates cannot see: (1) the asset /
  route **loads** at runtime (network — the edited file is really requested, not ignored by the theme),
  (2) the edited style / behavior is the **effective computed** one (not shadowed by theme specificity),
  after a hard refresh, and (3) no **persisted client state** (`localStorage` / session) is masking it.
  Drive it yourself — never hand the user a visual check you can run.
- **Coverage — every consumer, not the first one.** When the change touches a field, an enum, or a
  response shape, verify it **everywhere it surfaces** — List *and* Show, export, the API `JsonResource`,
  notifications — using the discovery impact map as the checklist. Confirm every denormalized / derived
  value is populated **end-to-end on a real row**, not merely written by code that "should" run. A
  consumer the map lists is either verified or explicitly noted out of scope; "fixed in one place" is not
  done while the map names others.
- **End-to-end reachability.** A value is documented as available only once real data produces it
  end-to-end — the field is in the shape **and** something can actually populate it. A shape the backend
  cannot fill is not a contract; catch it here, not when the frontend hits the wall (the payment-status-
  by-`uuid` case).
- **Bug reports are class signals, not point defects.** When the user reports a UI / behavior defect,
  audit the **whole class** of sibling sites — every model with that field, every column that truncates,
  every screen using that partial, every dashboard link's clickability — and fix + verify the class in
  one pass. One user-found defect means the class was never verified; a point patch just waits for the
  next instance.

**Fail-safe, never silent.** If the running app or the browser tool cannot be reached, state exactly what
stayed unverified and hand over precise reproduction steps — the same visible escape as
`OpenAPI: n/a — <reason>`. Never report green tests as "works live".

## Self-review checklist

followed the spec? · only related files changed? · API contracts preserved? · controllers thin? ·
logic in services? · validation in FormRequest? · authorization present? · multi-step writes
transactional? · resources preserve shape? · N+1 handled? · migrations production-safe? · tests
written test-first (red→green)? · each acceptance-criterion ID mapped to a passing test? · **every
touched endpoint documented in OpenAPI to the protocol** (all reachable status codes, request body
from the FormRequest, response schema from the JsonResource, examples/enums) and generation clean? ·
gates run or skip-reason stated? · **exercised live against the running app** for the touched surface
(HTTP run / browser drive), or stated what stayed unverified + repro? · **every consumer of a touched
shape verified** (List/Show/export/API/notifications), denormalized values present on real data? · a
user-reported defect audited as a class, not point-patched?

## Conformance review (L2+)

Before the handoff, spawn the **conformance-reviewer** agent on the working diff (`git diff`) against
the spec's acceptance-criterion IDs. In a fresh context it judges each AC `met` / `partial` / `unmet`
and reports only correctness/requirement gaps. Fix any unmet-AC gap, or fold it into the handoff as a
stated gap. Skip for L0/L1. This is distinct from the adversarial-verifier (which challenges "it works"
claims).

## Handoff summary

1. Behavior change first (not just files).
2. Key files changed and why.
3. What was verified, with the exact commands run **and the live run** — the red→green order (test
   failed before the code, passes after) for the changed behavior, plus the HTTP / browser exercise
   against the running app and its **observed result** (real status + body, or the screen state), not
   just that the gates passed.
4. How to test manually or with targeted automated tests.
5. Risks, deployment notes, migrations, cache/config/queue/scheduler impact, API-contract changes.
6. Anything skipped, deferred, or not run.
7. Assumptions or CRD/code conflicts.

Never report unqualified "100% done". State what is `verified` vs `assumed`.

## Converge (re-audit vs the full spec)

Beyond the diff-scoped conformance review, re-audit the spec's **full** acceptance-criteria set against
implemented reality: which AC IDs are done, which remain, which were deferred. Append any unmet or
deferred criteria to `.claude/groundwork/task-state.md` as remaining slices so nothing silently drops. If
everything is satisfied, say so.

**Blind-spot re-pass.** Also check for blind spots the *finished* implementation itself created — a
state that is now async, a new failure path, a consumer the change now affects, data that needs a
backfill. Surface any material one (per `${CLAUDE_SKILL_DIR}/../../guidelines/blind-spot-protocol.md`)
as a handoff note or a new slice; "none" is a valid result.

**Domain-drift check.** When the finished change added, renamed, or removed a domain entity, an
invariant, a permission rule, an external integration, or a term, update the matching section of the
project's `AGENTS.md` in this same change. That file is the contract every later task reads first, and
`init` is its only other writer — left alone, it goes stale the day after onboarding. A refactor or a
bug fix that introduced no new vocabulary changes nothing here.

## Close the checkpoint

When the handoff is clean and the gates are green, mark the task done in
`.claude/groundwork/task-state.md` (or delete the file) so the next session starts fresh instead of
resuming a finished task. If work remains, leave the checkpoint reflecting the true remaining state.

## Next: frontend handoff

If the gates are green and the change touched the frontend-facing surface, run the
**`frontend-handoff`** skill next — document the final contract for the frontend developer in
`ai/frontend/`, then offer to commit.
