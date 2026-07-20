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
  the expert in), per [blind-spot-protocol.md](blind-spot-protocol.md). No edits.
- **Spec** — create/update a spec under `docs/specs/`. No production code.
- **Plan** — propose steps, list changed files, tests, verification, deployment impact. No edits
  until approved.
- **Implementation** — test-first (red→green→refactor): write the failing test, implement to green,
  refactor under the gates. Edit per the approved spec; keep scope tight. See
  [tdd-protocol.md](tdd-protocol.md).
- **Review** — review the diff for violations, missing tests, risks. No silent changes. Two distinct
  gates: the **adversarial-verifier** challenges "it works" claims (is the claim true?); the
  **conformance-reviewer** judges the diff against the spec's acceptance-criterion IDs (does it match?).

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

1. Read the project `AGENTS.md`.
2. Classify the task.
3. Inspect the directly-involved code first — prefer Boost MCP tools (`application-info`,
   `database-schema`, `search-docs`) over recalling from memory.
4. Map the connections (blast radius) outward — callers/consumers, events/listeners, observers, jobs,
   scheduled commands, policies, FK/cascades, API consumers of the response shape, and covering tests.
   For L2+ spawn the `impact-mapper` agent; for L0/L1 a quick self-trace is enough. Then surface
   **blind spots** — the dimensions the request omits (per [blind-spot-protocol.md](blind-spot-protocol.md));
   for L3/L4 spawn `blind-spot-mapper` in a fresh context alongside `impact-mapper`.
5. Consult the CRD for business intent when the task touches domain/API/schema/permissions/
   financial behavior/notifications/reports/integrations/deployment.
6. Do not write code in the first response.
7. Draft a short, implementation-oriented spec.
8. Produce an implementation plan.
9. List assumptions, conflicts, risks, verification steps.
10. Stop and wait for explicit approval.

First-response structure: current understanding · classification · files/docs to inspect ·
connections / blast radius · business/CRD areas affected · draft spec · acceptance criteria ·
clarifications (ambiguities/conflicts/gaps to resolve before planning) · blind spots (dimensions you
did not ask about — unintended consequences, missing requirements, domain/product angles; per the
blind-spot protocol) · plan · risks/assumptions · stop point.

## Definition of Ready

Goal clear · current behavior inspected · affected files identified · connections mapped (callers,
events, jobs, policies, FK/cascades, consumers of the response shape, covering tests) · acceptance
criteria written · validation/authorization/API/DB/queue impact known · tests listed (the red list —
fail-first tests covering the criteria, for L2+/bug fixes) · deployment
risks identified · blind spots surfaced (resolved or explicitly accepted) · assumptions documented.

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
format + static analysis run (or skip reason stated) · migration/deployment impact
documented · frontend handoff docs in `ai/frontend` created/updated when the change touches the
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
passing test? · gates run or skip-reason stated? · blind spots surfaced (or none)? ·
risks/assumptions documented?
