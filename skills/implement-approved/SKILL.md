---
description: Implement an already-approved spec/plan for a Laravel backend through existing architecture boundaries. Use only after the user has explicitly approved the plan or spec in the current conversation.
---

# Implement approved work

Only proceed if the spec/plan was **explicitly approved in this conversation**. If not, stop and run
`start-task` / `spec` first.

## How to implement

- **Work test-first** for L2+ and bug fixes: for each slice write the failing test before the code,
  implement to green, then refactor under the gates — no production code for a covered slice before a
  red test exists. Match the test to the layer (feature for contract/validation/authz/shape; unit for
  services/calculations/state transitions). See the TDD protocol (`${CLAUDE_SKILL_DIR}/../../guidelines/tdd-protocol.md`).
- **Implementation is single-threaded** — work one TDD slice at a time; do not spawn parallel coding
  agents. Fan-out is for Discovery and Verification only (see "Fan-out by level" in the process doc).
- Follow the approved spec's acceptance criteria; keep changes scoped to the task.
- Respect architecture boundaries (`${CLAUDE_SKILL_DIR}/../../guidelines/laravel-standards.md` — the
  table there says which of these a hook actually enforces and which are on you):
  - validation + request authorization in **FormRequest**
  - business logic in **services**, not controllers/models/resources
  - response shape in **JsonResource**
  - **transactions** around multi-step domain writes — and a job or event dispatched inside one goes
    out via `->afterCommit()` (or `after_commit` on the queue connection), never bare: a worker can
    pick the job up before the transaction commits and read a row that does not exist yet
  - external calls behind **clients/services**
- Use **enums** for states, **decimal/int cents** for money, **guarded transitions** for workflow
  state, and **DB-level constraints** for integrity.
- Confirm version-specific Laravel details with Boost `search-docs`; inspect schema with
  `database-schema` rather than guessing column names.
- Preserve public API shapes, route names, validation semantics, and permissions unless the spec
  explicitly changes them.
- **Update the OpenAPI annotations in the same slice that changes the endpoint** — not at the end, not
  "later". A touched endpoint documents every reachable response code (success + 401/403/404/409/422),
  its request body derived from the FormRequest rules, and its response schema derived from the
  JsonResource, with examples and enums from the real PHP enums. The `openapi` Stop gate blocks "done"
  when the contract surface changed and the spec did not. See
  `${CLAUDE_SKILL_DIR}/../../guidelines/openapi-protocol.md`.
- Drive the work with **focused tests written first** — behavior, validation, authorization, response
  shape, workflow transitions, money, migrations, and any fixed bug (failing regression test before
  the fix).
- **Keep the checkpoint current** — as each slice goes red→green, flip `[ ]`→`[x]` and `red`→`green`
  in `.claude/groundwork/task-state.md` (see `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`).
  It is what survives a restart or compaction, so the next session resumes mid-task instead of
  re-deriving the plan.
- **A new sub-request is a scope change — re-check the blast radius before building it.** When the user
  adds work inside the active task ("и ещё поправь X", "while you're there…"), name the sub-request's
  seeds (files, models, tables, symbols) and compare them with the `SEEDS:` header of the cached impact
  map:
  - **already covered** → the map holds, proceed;
  - **new seeds outside the map** → the map does not cover this work. Match the response to what the new
    seeds *are*, because `impact-mapper` is the most expensive fan-out in the plugin:
    - a **model, table, or service** among them (couplings fan out invisibly) → **L2+:** re-spawn
      `impact-mapper` over the **union** of old and new seeds, overwrite the cache, refresh `SEEDS:` and
      `BASE_COMMIT`. **L0/L1:** a targeted self-trace.
    - only a **Resource, FormRequest, view, or string** → a targeted self-trace at any level; re-spawning
      the mapper for a copy change is the ceremony this rule is meant to avoid.
  - **no cached map at all** (an L0/L1 task never wrote one) → nothing to compare against, so trace the
    new seeds yourself; if the sub-request pushes the work to L2+, build the map now.

  The comparison, not the level, decides — **accumulation counts**: three small sub-requests can jointly
  touch a class nobody mapped. The check is cheap (a list comparison), so a borderline case is treated as
  a scope change. **Record the sub-request joining the scope in the checkpoint**, with whether the map was
  re-mapped or self-traced; a checkpoint that omits a scope change is an overstatement of what was
  covered. Rules: `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`.
- **Escalate a blind spot found mid-build.** If a slice reveals a dimension the plan missed with
  material consequences (a race, a cascade, a broken consumer, a domain rule), **stop and surface it** —
  do not silently work around it. A silent workaround buries the decision the user should make. See
  `${CLAUDE_SKILL_DIR}/../../guidelines/blind-spot-protocol.md`.

## Before finishing

1. Run the `final-check` skill (format + static analysis + the green test gate + Definition of Done).
   Report the red→green order for the behavior you changed.
2. Once the gates are green, run the **`frontend-handoff`** skill — it documents the **final**
   frontend-facing contract for the frontend developer in `ai/frontend/` (create the reference doc
   for new functionality, update the affected ones for a change, and always add a dated handoff doc),
   then asks whether to commit. Skip only if the change has no frontend-facing impact (say so).
