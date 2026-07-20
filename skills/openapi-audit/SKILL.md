---
description: Audit and repair a project's whole OpenAPI/Swagger spec — inventory every API route, find endpoints that are undocumented or documented partially, and fill the gaps from real code. Use for pre-existing spec debt (a project whose Swagger is empty or stale), not for the endpoints of the task you are currently implementing.
effort: high
---

# OpenAPI audit

Brings a project's published spec back to the standard in
`${CLAUDE_SKILL_DIR}/../../guidelines/openapi-protocol.md`: every endpoint documented, every
operation complete to the last detail, generation clean.

Scope note: the endpoints **you are changing right now** are covered by `implement-approved` +
the `openapi` Stop gate. This skill is for the **backlog** — spec debt that predates the task.

## 1. Inventory both sides

- **Routes** — `./vendor/bin/sail artisan route:list --json`. Keep the API surface (the `api`
  middleware group / the project's API prefix); drop internal, telescope/horizon, and framework routes.
- **Documented operations** — regenerate first
  (`./vendor/bin/sail artisan l5-swagger:generate`), then read the produced document
  (usually `storage/api-docs/api-docs.json`). If generation fails, fix that before auditing —
  a failing build means the published spec is already stale.

## 2. Classify every route

For each API route, compare the documented operation against the protocol checklist:

| Verdict | Meaning |
| --- | --- |
| `missing` | No operation for this path+method — it ships undocumented. |
| `incomplete` | Operation exists but a required part is absent (see the checklist below). |
| `stale` | Documented shape contradicts the current FormRequest / Resource / enum / status codes. |
| `ok` | Matches the protocol. |

`incomplete`/`stale` must name **which** parts fail: summary/description · tags · security ·
parameters (typed, required, examples, enums) · request body derived from the FormRequest rules ·
**every reachable response code** (success + 401/403/404/409/422) · response schema matching the
JsonResource field-by-field · enum values from the PHP enums · pagination envelope · examples ·
component reuse instead of copy-paste.

## 3. Report before repairing

Produce a table — route · method · verdict · missing parts — plus counts per verdict. Then **ask the
user how far to go**: the whole spec, one area/tag, or only `missing` endpoints. A full repair on a
large API is a big diff; do not start it unprompted.

## 4. Repair in area-sized batches

Work one feature area (tag) at a time so each batch is reviewable:

1. Read the real code for every endpoint in the batch — route, controller action, FormRequest,
   JsonResource, policies, enums. Derive each part from the source of truth in the protocol table;
   **never invent** a field, code, or constraint.
2. Write/repair the annotations. Extract shared shapes (resource schemas, the validation-error
   envelope, the pagination envelope) into `#[OA\Schema]` components and `ref` them.
3. Regenerate — it must finish with no errors and no warnings.
4. Report the batch: endpoints fixed, parts added, anything you could not derive.

Unresolvable questions (a field whose meaning is not in the code, an undocumented status a client
depends on) go to the user as a question — not into the spec as a guess.

## 5. Close out

- Confirm generation is clean and the spec covers every API route (re-run step 1 to prove it).
- Note in the handoff which areas were repaired and which were deliberately left.
- If the change touched the frontend-facing contract, the `frontend-handoff` docs must reflect the
  same shapes — the spec and `ai/frontend/` cannot disagree.
- Ask before committing (single-line message, no AI attribution).
