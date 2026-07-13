---
description: Start a backend task through the RaDevs AI-SDD discovery/plan workflow. Use at the beginning of any non-trivial feature, bug fix, or API/schema/permission/workflow/integration change, before writing code.
---

# Start task (discovery & plan)

Stay in **Discovery mode**: inspect and plan only, do not edit files until the plan is approved.

## Steps

1. **Read the project `AGENTS.md`** for domain facts, invariants, permission rules, and runtime
   commands.
2. **Classify the task** (L0 tiny → L4 critical). State the level and what it implies.
3. **Inspect the directly-involved code.** Prefer Boost MCP tools — `application-info`,
   `database-schema`, `search-docs` — over recalling from memory. Read the actual routes, requests,
   controllers, services, models, resources, migrations, and tests the task names.
4. **Map the connections — do not stop at the involved files.** Discovery is wide; only the change is
   narrow. Trace outward in *both* directions from every touched symbol: who calls it, and what it
   pulls in. Chase the Laravel edges grep alone misses — events/listeners, observers, jobs, scheduled
   commands, policies/Gates/permission checks, `FormRequest`s reused across endpoints, the
   `JsonResource` shape and its API consumers, FK/cascade relationships, other modules on the same
   tables, and the tests covering any of it.
   - **L2+** (normal feature and up): base the plan on the **`impact-mapper`** connection map, but
     **reuse the cache first** — check `.claude/groundwork/impact/<slug>.md` and re-spawn the agent only
     if the seeds changed since it was written; otherwise overwrite the cache with the fresh map.
     This avoids re-running the most expensive fan-out on iterative work. Rules:
     `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`.
   - **L0/L1**: a quick outward trace yourself (a few targeted greps) is enough — no agent needed.
   - **Fan-out scales with level** — see "Fan-out by level" in
     `${CLAUDE_SKILL_DIR}/../../guidelines/ai-sdd-process.md`. Only Discovery and Verification fan out.
     For L3/L4 with many seeds, escalate to the `deep-discovery` skill (multi-agent Workflow).
   - **Surface blind spots** — after mapping couplings, walk the blind-spot taxonomy
     (`${CLAUDE_SKILL_DIR}/../../guidelines/blind-spot-protocol.md`): the dimensions the request omits —
     unintended consequences, missing requirements, domain/product angles the user is not the expert in.
     For **L3/L4** spawn the `blind-spot-mapper` agent in a fresh context (optional at L2). Report a
     **blind spots** block, separate from clarifications — material items only, ranked, or "none".
5. **Consult the CRD** for business intent when the task touches domain/API/schema/permissions/
   financial behavior/notifications/reports/integrations/deployment.
6. **If the task touches an external API**, run the `ground-integration` skill before designing.
7. **Produce the first response in this structure** (no code yet):
   current understanding · classification · files/docs to inspect · connections / blast radius ·
   business/CRD areas affected · draft spec · acceptance criteria · clarifications (ambiguities,
   conflicts, gaps surfaced as explicit questions to resolve before planning) · blind spots (dimensions
   you did not ask about — consequences / missing requirements / domain-product angles, per the
   blind-spot protocol; material only, or "none") · test plan (red list —
   fail-first tests for L2+/bug fixes) · implementation plan · risks & assumptions · stop point.
8. **Write the task checkpoint** to `.claude/groundwork/task-state.md` — mode, level, spec path, the
   slice/red list, assumptions, open approvals — so the work survives a restart or compaction (the
   `SessionStart` hook re-injects it automatically, no re-reading). This bookkeeping file under
   `.claude/groundwork/` is workflow memory, not a code edit, so it is allowed in Discovery. Format:
   `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`.
9. **Stop and wait for explicit approval** before implementing.

## Rules

- **Map before you plan.** Discovery is wide, the change is narrow — scope the edit tightly, never
  the investigation. An unmapped consumer is an unlisted risk.
- **Clarify before you plan.** Surface ambiguities, conflicting constraints, and gaps as explicit
  questions; resolve the blocking ones before producing the plan — under-specification is cheapest to
  fix here.
- **Surface blind spots — don't wait to be asked.** Predict the dimensions the request omits — the
  unintended consequence, the missing requirement, the domain/product angle the user is not expert in —
  and give each its consequence and a recommended default, in plain language. Material and non-obvious
  only; never re-raise what the impact map / clarify / risk-review already own; "none" is honest. This
  is distinct from clarify (which resolves ambiguity in what was *said*). See
  `${CLAUDE_SKILL_DIR}/../../guidelines/blind-spot-protocol.md`.
- Do not invent business rules — derive them from CRD, code, or an explicit user decision.
- Label every claim as `verified` (with evidence) or `assumed`. Never use unqualified "done".
- **Plan tests first.** For L2+ and bug fixes, turn the acceptance criteria into a red list — the
  fail-first tests written before code. See the TDD protocol (`${CLAUDE_SKILL_DIR}/../../guidelines/tdd-protocol.md`).
- For a normal feature or risky change, write a spec with the `spec` skill before implementing.
