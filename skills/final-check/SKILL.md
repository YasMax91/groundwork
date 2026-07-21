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

## Self-review checklist

followed the spec? · only related files changed? · API contracts preserved? · controllers thin? ·
logic in services? · validation in FormRequest? · authorization present? · multi-step writes
transactional? · resources preserve shape? · N+1 handled? · migrations production-safe? · tests
written test-first (red→green)? · each acceptance-criterion ID mapped to a passing test? · **every
touched endpoint documented in OpenAPI to the protocol** (all reachable status codes, request body
from the FormRequest, response schema from the JsonResource, examples/enums) and generation clean? ·
gates run or skip-reason stated?

## Conformance review (L2+)

Before the handoff, spawn the **conformance-reviewer** agent on the working diff (`git diff`) against
the spec's acceptance-criterion IDs. In a fresh context it judges each AC `met` / `partial` / `unmet`
and reports only correctness/requirement gaps. Fix any unmet-AC gap, or fold it into the handoff as a
stated gap. Skip for L0/L1. This is distinct from the adversarial-verifier (which challenges "it works"
claims).

## Handoff summary

1. Behavior change first (not just files).
2. Key files changed and why.
3. What was verified, with the exact commands run — including the red→green order (test failed before
   the code, passes after) for the changed behavior.
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
