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
5. **Consult the CRD** for business intent when the task touches domain/API/schema/permissions/
   financial behavior/notifications/reports/integrations/deployment.
6. **If the task touches an external API**, run the `ground-integration` skill before designing.
7. **Produce the first response in this structure** (no code yet):
   current understanding · classification · files/docs to inspect · connections / blast radius ·
   business/CRD areas affected · draft spec · acceptance criteria · test plan (red list — fail-first
   tests for L2+/bug fixes) · implementation plan · risks & assumptions · stop point.
8. **Write the task checkpoint** to `.claude/groundwork/task-state.md` — mode, level, spec path, the
   slice/red list, assumptions, open approvals — so the work survives a restart or compaction (the
   `SessionStart` hook re-injects it automatically, no re-reading). This bookkeeping file under
   `.claude/groundwork/` is workflow memory, not a code edit, so it is allowed in Discovery. Format:
   `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`.
9. **Stop and wait for explicit approval** before implementing.

## Rules

- **Map before you plan.** Discovery is wide, the change is narrow — scope the edit tightly, never
  the investigation. An unmapped consumer is an unlisted risk.
- Do not invent business rules — derive them from CRD, code, or an explicit user decision.
- Label every claim as `verified` (with evidence) or `assumed`. Never use unqualified "done".
- **Plan tests first.** For L2+ and bug fixes, turn the acceptance criteria into a red list — the
  fail-first tests written before code. See the TDD protocol (`${CLAUDE_SKILL_DIR}/../../guidelines/tdd-protocol.md`).
- For a normal feature or risky change, write a spec with the `spec` skill before implementing.
