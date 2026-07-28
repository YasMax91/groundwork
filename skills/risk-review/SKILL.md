---
description: Review the current diff or plan for domain, API, permission, financial-visibility, migration, workflow, integration, and deployment risks. Use before finalizing risky backend changes.
effort: high
---

# Risk review

Review the current diff (or the proposed plan) against each category. Report concrete findings with
file/line references and a suggested fix; do not silently change code during review. Run it on the
**plan at task entry**, not only on the finished diff — the cheapest place to catch a risk is before
the code exists.

Scope: spec **conformance** (does the diff satisfy each acceptance-criterion ID?) is the
**conformance-reviewer**'s job in `final-check`. Risk-review stays on the risk categories below.

For an **L3/L4** diff, escalate to **`deep-review`** — a multi-agent Workflow that adversarially
verifies every finding before reporting (only confirmed risks survive).

## Checklist

- **API contract** — renamed/removed/retyped fields, changed enums, pagination shape, error format,
  route names, HTTP methods, or authorization behavior on existing endpoints. Additive is safer;
  breaking changes need explicit approval and OpenAPI updates.
- **OpenAPI drift** — an endpoint changed without its annotations, a documented field that no longer
  exists, a response code reachable in code but absent from the spec, a schema copy-pasted instead of
  referenced. The published spec is what clients build against; drift is a contract bug, not a docs
  nit. See `${CLAUDE_SKILL_DIR}/../../guidelines/openapi-protocol.md`.
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
- **Vulnerability classes the gates do not model** — when the diff touches authentication, RBAC, file
  upload, raw SQL (`DB::raw`, `whereRaw`), deserialization, redirects built from input, or anything
  handling secrets, scan the changed files with `semgrep` (the companion plugin) and judge each hit:
  a confirmed risk with its fix, or dismissed with the reason. Pint/Larastan/PHPUnit stay the gates;
  this is the pass that looks for the injection/authz class they were never built to catch. Not
  installed, or the surface is untouched — say the scan did not run, so nobody reads silence as a
  clean scan.
- **Test-first discipline** — for L2+/bug fixes the covered behavior has fail-first tests (red→green);
  a bug fix has a regression test that failed before the fix. See the TDD protocol
  (`${CLAUDE_SKILL_DIR}/../../guidelines/tdd-protocol.md`).
- **Other consequences (open — beyond the checklist)** — anything the fixed dimensions above do not
  name: a domain/product mismatch (does this solve the *right* problem and meet the stated goal?), a
  broken user expectation, an unintended side effect. The escape hatch so an off-list blind spot still
  surfaces — walk the blind-spot taxonomy
  (`${CLAUDE_SKILL_DIR}/../../guidelines/blind-spot-protocol.md`).

End with: confirmed risks (ranked) · required approvals · missing or after-the-fact tests ·
suggested fixes.
