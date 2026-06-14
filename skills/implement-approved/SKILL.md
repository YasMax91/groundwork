---
description: Implement an already-approved spec/plan for a Laravel backend through existing architecture boundaries. Use only after the user has explicitly approved the plan or spec in the current conversation.
---

# Implement approved work

Only proceed if the spec/plan was **explicitly approved in this conversation**. If not, stop and run
`start-task` / `spec` first.

## How to implement

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
- Add or update **focused tests** for behavior, validation, authorization, response shape, workflow
  transitions, money, migrations, and any fixed bug (regression test).

## Before finishing

Run the `final-check` skill (format + static analysis + targeted tests + Definition of Done).
