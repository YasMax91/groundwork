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

**Scaled by level** (the full Definition of Done is L2+; see
`${CLAUDE_SKILL_DIR}/../../guidelines/ai-sdd-process.md`):

- **L0** — no live run, no sweep, no class enumeration; the automatic gates are the whole check. The
  honesty rules at the end of this section still bind: say what was not verified, and never call green
  tests "works live".
- **L1** — exercise **the one thing you fixed**, live. Skip the consumer sweep, the reachability audit,
  and the class enumeration below unless the bug report itself points at a class.
- **L2+** — the whole section.

- **API / feature endpoint — a real HTTP run.** Call the endpoint on the running app (curl / an HTTP
  client, or non-interactively via
  `./vendor/bin/sail artisan tinker --execute="…"` — a bare `tinker` waits for a TTY and will hang) with
  realistic input, and capture the **actual** status + body. A green feature test does **not** satisfy this — the point is the wire,
  the middleware stack, the real DB, and the serialized response a client receives (the unqualified-column
  join that passes phpunit and 500s live is exactly what this catches). If the app is not served this
  session, fall back to the closest real exercise (`$this->getJson(...)` against the HTTP kernel) and say
  the wire was not hit.
- **Admin / UI / CSS — a real browser.** When a browser-driving tool is available — the
  `claude-in-chrome` MCP, the `playwright` companion plugin, or any other browser MCP in the session;
  take whichever is there rather than declaring the check impossible — open the actual screen and
  verify what the gates cannot see: (1) the asset /
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
- **Bug reports are class signals — surface the class, fix what is approved.** When the user reports a UI
  / behavior defect, **enumerate every sibling site** (every model with that field, every column that
  truncates, every screen using that partial, every dashboard link) and **report the list**. Fix the
  reported instance plus the siblings that fall inside the approved scope; offer anything wider as a
  **named follow-up slice with its own approval** — silently widening a change collides with "keep the
  scope tight" and with the approval gate. One user-found defect means the class was never verified, so
  the class must at minimum become *visible*; what stays unfixed is stated, never unmentioned.

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
gates run or skip-reason stated? · **exercised live against the running app** at this level's depth
(HTTP run / browser drive), or stated what stayed unverified + repro? · **L2+ only:** every consumer of
a touched shape verified (List/Show/export/API/notifications), denormalized values present on real
data? · **L2+ only:** a user-reported defect's sibling class enumerated and reported, each sibling fixed
in scope or offered as a slice?

## Conformance review (L2+ — per the fan-out table in `../../guidelines/ai-sdd-process.md`)

Before the handoff, spawn the **conformance-reviewer** agent on the working diff (`git diff`) against
the spec's acceptance-criterion IDs. At **L3/L4**, also spawn the **adversarial-verifier** on the
riskiest "it works" claim — the same table owns both calibrations. In a fresh context it judges each AC `met` / `partial` / `unmet`
and reports only correctness/requirement gaps. Fix any unmet-AC gap, or fold it into the handoff as a
stated gap. Skip for L0/L1.

## Record what it actually took

After the gates are green and before the handoff summary, close the measurement window:

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/estimate-ledger.sh --record --kind=<one word> --promised=<minutes, if one was given>
```

It reads `Started:` from the checkpoint, measures the agent's active minutes from this session's
transcript, and appends one row to the ledger every later estimate is calibrated against. Durations and
identifiers only — no transcript content is written. A checkpoint without `Started:` records nothing and
says so; that is a lost measurement, not an error to work around by inventing a start time.

Skip at L0. Everything from L1 up is worth a row: the corpus is what stops the next estimate from being
an opinion.

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
8. **What you decided alone** — the closing cost-of-silence list (below).
9. **Promised against actual** — one line: what the estimate said, what the work took in active agent
   minutes, and the gap. If no estimate was given, say that instead. This is the only place an estimate
   is ever falsified; without it the next one inherits the same error with nothing to correct it. Skip
   at L0.

Never report unqualified "100% done". State what is `verified` vs `assumed`.

**Every verification claim in point 3 carries its denominator** — the covered/total fraction against a
named set (the impact map's consumers, the routes, the acceptance-criterion IDs, the changed files), or
the plain statement that no verification was performed. Never estimate the fraction: if the set cannot
be enumerated, say that instead. "Checked it selectively" and "went over it superficially" are not
reports — they hide whether that was eight of nine or one of nine. Point 6 then carries each uncovered
item as its own line, and an out-of-scope note says **who** put it out of scope. Full rule:
`${CLAUDE_SKILL_DIR}/../../guidelines/writing-standards.md`; level calibration (nothing at L0, one
sentence at L1, fractions from L2) in `${CLAUDE_SKILL_DIR}/../../guidelines/ai-sdd-process.md`.

## The closing cost of silence

Before the plan, `start-task` listed what you decided for the user. This is the second half: **every
decision you took without asking since the plan was approved** — one line each, plain language first:
what was decided · the alternative you did not take · what changes if it was wrong.

- **Threshold** — a decision earns its line only if you made it alone **and** it changes observable
  behaviour, money, permissions, or a contract. Rounding a total, choosing which role the check reads,
  what the client's screen ends up showing, what the provider is told on a retry — those qualify. A
  variable name does not.
- **No repetition** — anything already listed before the plan stays there.
- **Scaled** — L0/L1: only if an item clears the threshold. L2+: mandatory, and "none" is valid
  content, stated as a claim rather than an omission.

Full rule: `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md` §The cost of silence — stated
again at the end.

The summary reports **outcomes, not effort**, per
`${CLAUDE_SKILL_DIR}/../../guidelines/writing-standards.md` — no "significantly improved", no count of
files read, no "Conclusion" section, and a failure written in the same plain voice as a success.

**When the work goes out as a pull request**, its body is this summary — behavior change, what was
verified with the observed result, risks, what stayed unverified — not a fresh description written
from the diff. It comes after the commit (the `frontend-handoff` step below asks for that) and needs
its own explicit yes before `gh pr create`; a reviewer reading an invented summary reviews the wrong
change.

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

When the handoff is clean and the gates are green, set `Mode: Done — <what shipped>` in
`.claude/groundwork/task-state.md` so the next session starts fresh instead of resuming a finished task.
That line is also what stops the `SessionStart` hook from re-injecting the whole checkpoint — a closed
task costs a pointer, an open one costs its body. If work remains, leave the checkpoint reflecting the
true remaining state.

**Do not delete the file while the working tree still holds an uncommitted contract-surface change.** The
`openapi` Stop gate reads the `OpenAPI: n/a — <reason>` line *from this file*, against the **working
tree**, before any commit exists — deleting it mid-turn destroys the exemption the task legitimately
declared and blocks its own "done". Deletion is safe only once the change is committed, or when the task
never touched routes / controllers / FormRequests / Resources.

## Next: frontend handoff

If the gates are green and the change touched the frontend-facing surface, run the
**`frontend-handoff`** skill next — it ends by asking whether to commit. **If the change is purely
internal**, there is no handoff to run, so **ask about committing here** rather than leaving the work
uncommitted and the question unasked. Never commit without an explicit yes.

The handoff skill documents the final contract for the frontend developer in `ai/frontend/`, then offers
to commit.
