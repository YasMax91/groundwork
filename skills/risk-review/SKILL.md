---
description: Review the current diff or plan for domain, API, permission, financial-visibility, migration, workflow, integration, and deployment risks. Use before finalizing risky backend changes.
effort: high
---

# Risk review

Review the current diff (or the proposed plan) against each category. Report concrete findings with
file/line references and a suggested fix; do not silently change code during review.

## Checklist

- **API contract** — renamed/removed/retyped fields, changed enums, pagination shape, error format,
  route names, HTTP methods, or authorization behavior on existing endpoints. Additive is safer;
  breaking changes need explicit approval and OpenAPI updates.
- **Permissions / RBAC** — every write endpoint has an authorization rule; no reliance on frontend
  visibility; allowed- and forbidden-user tests exist.
- **Financial visibility** — hidden financial fields stay hidden in production-display/station
  contexts; money keeps its decimal-string behavior.
- **Workflow state** — transitions go through guards; no bypass of state rules; scan/movement
  sequence preserved.
- **Migrations** — additive and production-safe; no destructive change without approval; indexes for
  new query patterns; casts/factories/resources/tests aligned; rollback risk documented.
- **External integrations** — behind clients/services; capability claims are grounded (see the
  grounding protocol); errors/retries handled and tested with fakes.
- **Queues / scheduler / cache** — side effects behind jobs/events; cache is not the source of truth;
  deployment accounts for cache/config rebuild.
- **N+1 / performance** — relationships eager-loaded intentionally on list endpoints.
- **Test-first discipline** — for L2+/bug fixes the covered behavior has fail-first tests (red→green);
  a bug fix has a regression test that failed before the fix. See the TDD protocol
  (`${CLAUDE_SKILL_DIR}/../../guidelines/tdd-protocol.md`).

End with: confirmed risks (ranked) · required approvals · missing or after-the-fact tests ·
suggested fixes.
