# AI-SDD process (RaDevs)

Generic spec-driven workflow for any RaDevs Laravel project. Domain facts live in the
project's `AGENTS.md`; this file is the process. Read together with
[grounding-protocol.md](grounding-protocol.md) and [laravel-standards.md](laravel-standards.md).

## Operating modes

State the current mode when starting non-trivial work.

- **Discovery** — inspect files, search code, read docs/CRD, summarize current behavior, list
  affected files, draft assumptions. No edits.
- **Spec** — create/update a spec under `docs/specs/`. No production code.
- **Plan** — propose steps, list changed files, tests, verification, deployment impact. No edits
  until approved.
- **Implementation** — edit per the approved spec, add focused tests, run gates. Keep scope tight.
- **Review** — review the diff for violations, missing tests, risks. No silent changes.

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

## Startup sequence (non-trivial tasks)

1. Read the project `AGENTS.md`.
2. Classify the task.
3. Inspect the real code first — prefer Boost MCP tools (`application-info`, `database-schema`,
   `search-docs`) over recalling from memory.
4. Consult the CRD for business intent when the task touches domain/API/schema/permissions/
   financial behavior/notifications/reports/integrations/deployment.
5. Do not write code in the first response.
6. Draft a short, implementation-oriented spec.
7. Produce an implementation plan.
8. List assumptions, conflicts, risks, verification steps.
9. Stop and wait for explicit approval.

First-response structure: current understanding · classification · files/docs to inspect ·
business/CRD areas affected · draft spec · acceptance criteria · plan · risks/assumptions ·
stop point.

## Definition of Ready

Goal clear · current behavior inspected · affected files identified · acceptance criteria written ·
validation/authorization/API/DB/queue impact known · tests listed · deployment risks identified ·
assumptions documented.

## Human approval gates (stop and ask)

public API contract change · new dependency · destructive migration · workflow-state logic ·
financial calculation · weakening permissions · deploy/runtime change · new architectural layer ·
external integration behavior · behavior not supported by CRD/code/explicit user decision ·
broad refactor/formatting/file deletion.

## Definition of Done

implementation matches the approved spec · public API preserved or intentionally changed ·
validation via FormRequest · authorization handled · business logic in services · resources preserve
response shape · multi-step writes transactional · focused tests added/updated · OpenAPI updated when
contracts change · format + static analysis run (or skip reason stated) · migration/deployment impact
documented · final report covers changed behavior, files, verification, risks, skipped work.

Never declare done with failing tests or static-analysis errors. Never use unqualified "100% done" —
see [grounding-protocol.md](grounding-protocol.md).

## Self-review checklist (before the final response)

followed the spec? · only related files changed? · API contracts preserved? · controllers thin? ·
logic in services? · validation in FormRequest? · authorization present where needed? · multi-step
writes transactional? · resources preserve shape? · N+1 handled? · migrations production-safe? ·
tests added/updated? · gates run or skip-reason stated? · risks/assumptions documented?
