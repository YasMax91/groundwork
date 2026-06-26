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
- Respect architecture boundaries (see the Laravel standards):
  - validation + request authorization in **FormRequest**
  - business logic in **services**, not controllers/models/resources
  - response shape in **JsonResource**
  - **transactions** around multi-step domain writes
  - external calls behind **clients/services**
- Use **enums** for states, **decimal/int cents** for money, **guarded transitions** for workflow
  state, and **DB-level constraints** for integrity.
- Confirm version-specific Laravel details with Boost `search-docs`; inspect schema with
  `database-schema` rather than guessing column names.
- Preserve public API shapes, route names, validation semantics, and permissions unless the spec
  explicitly changes them. Update OpenAPI when a contract changes.
- Drive the work with **focused tests written first** — behavior, validation, authorization, response
  shape, workflow transitions, money, migrations, and any fixed bug (failing regression test before
  the fix).
- **Keep the checkpoint current** — as each slice goes red→green, flip `[ ]`→`[x]` and `red`→`green`
  in `.claude/groundwork/task-state.md` (see `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`).
  It is what survives a restart or compaction, so the next session resumes mid-task instead of
  re-deriving the plan.

## Before finishing

1. Run the `final-check` skill (format + static analysis + the green test gate + Definition of Done).
   Report the red→green order for the behavior you changed.
2. Once the gates are green, run the **`frontend-handoff`** skill — it documents the **final**
   frontend-facing contract for the frontend developer in `ai/frontend/` (create the reference doc
   for new functionality, update the affected ones for a change, and always add a dated handoff doc),
   then asks whether to commit. Skip only if the change has no frontend-facing impact (say so).
