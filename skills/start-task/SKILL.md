---
description: Start a backend task through the RaDevs AI-SDD discovery/plan workflow. Use at the beginning of any non-trivial feature, bug fix, or API/schema/permission/workflow/integration change, before writing code.
---

# Start task (discovery & plan)

Stay in **Discovery mode**: inspect and plan only, do not edit files until the plan is approved.

## Steps

1. **Read the project `AGENTS.md`** for domain facts, invariants, permission rules, and runtime
   commands.
2. **Classify the task** (L0 tiny → L4 critical). State the level and what it implies.
3. **Inspect the real code first.** Prefer Boost MCP tools — `application-info`, `database-schema`,
   `search-docs` — over recalling from memory. Read the actual routes, requests, controllers,
   services, models, resources, migrations, and tests involved.
4. **Consult the CRD** for business intent when the task touches domain/API/schema/permissions/
   financial behavior/notifications/reports/integrations/deployment.
5. **If the task touches an external API**, run the `ground-integration` skill before designing.
6. **Produce the first response in this structure** (no code yet):
   current understanding · classification · files/docs to inspect · business/CRD areas affected ·
   draft spec · acceptance criteria · implementation plan · risks & assumptions · stop point.
7. **Stop and wait for explicit approval** before implementing.

## Rules

- Do not invent business rules — derive them from CRD, code, or an explicit user decision.
- Label every claim as `verified` (with evidence) or `assumed`. Never use unqualified "done".
- For a normal feature or risky change, write a spec with the `spec` skill before implementing.
