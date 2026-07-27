# AI-SDD process (RaDevs)

Generic spec-driven workflow for any RaDevs Laravel project. Domain facts live in the
project's `AGENTS.md`; this file is the process. Read together with
[grounding-protocol.md](grounding-protocol.md), [blind-spot-protocol.md](blind-spot-protocol.md),
[laravel-standards.md](laravel-standards.md), and [tdd-protocol.md](tdd-protocol.md).

## Operating modes

State the current mode when starting non-trivial work. Discovery is wide; the change is narrow —
scope the edit tightly, never the investigation.

- **Discovery** — inspect files, search code, read docs/CRD, summarize current behavior. Map the
  connections outward (callers, consumers, events, jobs, policies, FK/cascades, covering tests), not
  just the directly-involved files. Draft assumptions. Surface **blind spots** — the dimensions the
  request omits (unintended consequences, missing requirements, domain/product angles the user is not
  the expert in), per [blind-spot-protocol.md](blind-spot-protocol.md). Then **interview** the user for
  the decisions only they can make — facts are yours to find — per
  [clarify-protocol.md](clarify-protocol.md). No edits.
- **Spec** — create/update a spec under `docs/specs/`. No production code.
- **Plan** — propose steps, list changed files, tests, verification, deployment impact. No edits
  until approved.
- **Implementation** — test-first (red→green→refactor): write the failing test, implement to green,
  refactor under the gates. Edit per the approved spec; keep scope tight. See
  [tdd-protocol.md](tdd-protocol.md).
- **Review** — review the diff for violations, missing tests, risks, and **exercise the change live**
  against the running app (HTTP run / browser drive per `final-check`) — green gates prove the code, not
  the running app. No silent changes. Two distinct gates: the **adversarial-verifier** challenges "it
  works" claims (is the claim true?); the **conformance-reviewer** judges the diff against the spec's
  acceptance-criterion IDs (does it match?). A defect the **user** reports is a signal about a whole
  class — audit every sibling site and fix the class, never point-patch the one instance.

## Task classification (classify before working)

- **L0 Tiny** — typo/comment/docs. No spec/plan/tests/approval if the user asked for it.
- **L1 Small bug fix** — short inline spec, plan, targeted regression test. Approval unless the
  user said apply now.
- **L2 Normal feature** — spec + plan + tests + approval.
- **L3 High-risk** (workflow state, payments/financial visibility, RBAC, schema migration, public
  API contract, deploy/runtime) — spec + plan + CRD check + tests + deployment notes + approval.
- **L4 Critical** (financial calc, order lifecycle, permission model, destructive migration,
  external integration behavior, queue/scheduler with business impact) — all of L3 + rollback
  notes + human approval always required.

## Estimates

Whenever the work is estimated — in a document or in chat — the unit is **real AI-hours to write the
functionality**, never man-days or developer hours: a human reviews this code, he does not write it.
Ranges per block, a total, and the reviewer's time on its own line. The format is owned by the
**`client-doc`** skill ([../skills/client-doc/SKILL.md](../skills/client-doc/SKILL.md)) — follow it there
rather than a second copy that drifts.

## Fan-out by level (effort scaling)

Match agent fan-out to task level. Over-spawning wastes ~15× the tokens; coding is a poor multi-agent
fit, so only Discovery and Verification fan out.

- **L0 Tiny** — no subagents. Inline.
- **L1 Small** — self-trace (a few targeted greps). No agent.
- **L2 Normal** — 1 `impact-mapper` (cache-aware). Add `grounded-researcher` only if an external API
  is touched; `blind-spot-mapper` optional when the task has real product/domain surface.
- **L3 High-risk** — `impact-mapper` + `blind-spot-mapper` + `grounded-researcher` (if integration) for
  discovery; `conformance-reviewer` + `adversarial-verifier` for verification. May escalate to
  `deep-discovery` / `deep-grounding` / `deep-review`.
- **L4 Critical** — as L3 (blind-spot-mapper required), plus an adversarial panel (≥2 skeptics) on the
  riskiest claims and blind spots.

**Implementation is single-threaded.** Work one TDD slice at a time — no parallel coding agents. The
fan-out above is for Discovery and Verification only.

## Startup sequence (non-trivial tasks)

The ordered steps and the first-response structure belong to the **`start-task`** skill
([../skills/start-task/SKILL.md](../skills/start-task/SKILL.md)), which owns them — follow it there
rather than a second copy that drifts. Three rules bind every path through it: the first response
carries no code, no file is edited before the plan is approved, and a decision the user could have made
is never assumed instead.

## Definition of Ready

Goal clear · current behavior inspected · affected files identified · connections mapped (callers,
events, jobs, policies, FK/cascades, consumers of the response shape, covering tests) · acceptance
criteria written · validation/authorization/API/DB/queue impact known · tests listed (the red list —
fail-first tests covering the criteria, for L2+/bug fixes) · deployment
risks identified · blind spots surfaced (resolved or explicitly accepted) · every blocking decision
answered by the user rather than assumed · assumptions documented.

## Human approval gates (stop and ask)

public API contract change · new dependency · destructive migration · workflow-state logic ·
financial calculation · weakening permissions · deploy/runtime change · new architectural layer ·
external integration behavior · behavior not supported by CRD/code/explicit user decision ·
broad refactor/formatting/file deletion.

For a **cross-cutting, durable** decision among these (new dependency, new architectural layer,
workflow-state model), capture an ADR in `docs/adr/NNNN-<slug>.md` (from `templates/adr.md`) — ≥2
considered options + the chosen one + why. Feature-local trade-offs stay in the spec.

## Definition of Done

implementation matches the approved spec · public API preserved or intentionally changed ·
validation via FormRequest · authorization handled · business logic in services · resources preserve
response shape · multi-step writes transactional · focused tests written test-first (red→green) and
passing · every acceptance-criterion ID mapped to a passing test (no AC unmapped) · **OpenAPI current and
complete for every touched endpoint** — annotations updated in the same change, every reachable status
code documented, request body from the FormRequest, response schema from the JsonResource, generation
clean (see [openapi-protocol.md](openapi-protocol.md); the `openapi` Stop gate enforces it) ·
format + static analysis run (or skip reason stated) · **exercised live against the running app** for
the touched surface — a real HTTP run for an endpoint, a real browser drive for admin/UI/CSS (asset
loads · effective computed style · no persisted state masking it), or an explicit statement of what
stayed unverified with repro steps; green tests are never reported as "works live" · **every consumer of
a touched shape verified** (List *and* Show, export, API resource, notifications — per the impact map)
with denormalized/derived values present on real data, or the consumer noted out of scope ·
migration/deployment impact
documented · **domain contract current** — the project's `AGENTS.md` reflects any entity, invariant,
permission rule, integration, or term the change introduced · frontend handoff docs in `ai/frontend` created/updated when the change touches the
frontend-facing surface (run the `frontend-handoff` skill after the gates are green) · final report
covers changed behavior, files, verification, risks, skipped work.

After the final implementation and the frontend handoff, **ask whether to commit**; on yes, make a
single-line commit with no AI attribution (the `frontend-handoff` skill drives this).

Never declare done with failing tests or static-analysis errors. Never use unqualified "100% done" —
see [grounding-protocol.md](grounding-protocol.md).

## Self-review checklist (before the final response)

followed the spec? · only related files changed? · impact map honored (each flagged consumer handled
or noted out of scope)? · API contracts preserved? · controllers thin? ·
logic in services? · validation in FormRequest? · authorization present where needed? · multi-step
writes transactional? · resources preserve shape? · N+1 handled? · migrations production-safe? ·
tests written test-first (red→green) for covered work? · each acceptance-criterion ID mapped to a
passing test? · gates run or skip-reason stated? · exercised live against the running app (or stated
what stayed unverified + repro)? · every consumer of a touched shape verified, denormalized values
present on real data? · a user-reported defect audited as a class, not point-patched? · blind spots
surfaced (or none)? · risks/assumptions documented?
