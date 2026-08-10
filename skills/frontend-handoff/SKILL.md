---
description: Produce the frontend-developer handoff docs in ai/frontend after a backend feature or change is fully implemented and the gates are green. Writes a Russian instruction doc — what to build, when, how, why, where, plus the API contract (no frontend code) — updates the affected reference docs, then offers to commit. Use as the closing step of any implementation that changes the frontend-facing surface (endpoints, response shape, validation, auth, states, visibility).
---

# Frontend handoff (docs for the frontend developer)

Run this **after the full, final implementation** is done and the gates are green (after
`final-check`). It produces the documentation a frontend developer reads, then hands to their own AI
to build the UI against this backend and the design.

## Audience & language

- The reader is a **human frontend developer** who studies the doc, then passes it to their AI to
  compose the backend contract + design into a frontend.
- **Write these docs in Russian** — they are a human handoff, an explicit exception to the
  English-artifact rule. Keep endpoint paths, field names, enum values, and HTTP details in English
  (that is the contract).
- **No frontend code.** No JS/TS, no components, no fetch snippets — the developer knows how to
  build. Describe *what / when / how / why / where* and the **contract**. JSON request/response
  **data** examples and field tables are encouraged (they are the contract, not code).
- **Ground everything in the real implementation** — derive endpoints, request rules, response shape,
  auth, states, and visibility from the actual routes, `FormRequest`s, `JsonResource`s, enums,
  policies, and migrations you just built. Mark anything uncertain as an assumption; never invent a
  field or rule. See `${CLAUDE_SKILL_DIR}/../../guidelines/grounding-protocol.md`.
- **No slop**, per `${CLAUDE_SKILL_DIR}/../../guidelines/writing-standards.md`: no preamble about what
  the document covers, no restating the same rule in three sections, no filler adjectives. The reader is
  building from this — every sentence is either the contract or a decision he has to make.

## When it applies

Only when the change touches the **frontend-facing surface**: endpoints, request/validation rules,
response shape, authorization/visibility, workflow states the UI reflects, or new user-facing
behavior. For a purely internal change with **no** frontend impact, say so explicitly and skip the
docs — then go straight to the commit step.

## Document types (all live under `ai/frontend/`, the dir from `.groundwork.json` `docs.frontend`)

1. **Living reference doc** — `ai/frontend/<area>.md`, the current truth for a feature/area
   (the "первоначальный документ"). Template: `${CLAUDE_SKILL_DIR}/../../templates/frontend/feature.md`.
   - **New functionality with no existing doc** → create it.
   - **A change** → edit the reference doc(s) the functionality touches so they describe current
     reality (add the new parts, fix the changed parts, remove the gone parts).
2. **Handoff instruction doc** — `ai/frontend/handoff/<YYYY-MM-DD>-<slug>.md`, the delta you physically
   hand over. Template: `${CLAUDE_SKILL_DIR}/../../templates/frontend/handoff.md`. **Always create one**
   for a frontend-facing change, covering **new · changed · removed (breaking)** functionality.
3. **Runnable request package** — `ai/frontend/<area>.postman_collection.json` **or**
   `ai/frontend/<area>.http` (pick one per project and stay consistent), so the frontend **runs** the
   contract instead of retyping it. One request per touched endpoint — method, URL, headers (incl. the
   auth header), and a request body derived from the `FormRequest` rules — each annotated with a
   **captured example success + error response** from `final-check`'s live run, so the examples are real,
   not invented. The reference and handoff docs point to it; the package never restates the prose
   contract, it executes it.

   **When the live run did not happen** — the app or the browser was unreachable, an outcome `final-check`
   explicitly permits — still produce the package and the docs, and mark every example
   **`UNVERIFIED — выведено из FormRequest/JsonResource, не наблюдалось`**. The reachability rule in step 5
   then degrades from a prohibition into a flagged assumption. Saying nothing about it is the only
   forbidden option: an unmarked invented example is precisely the failure this package exists to prevent.

## Steps

1. Document the **final** contract, not an intermediate one.
2. Identify the frontend-facing surface that changed. If none, state "нет влияния на фронтенд" and go
   to the commit step.
3. New vs change: create or update the living reference doc(s) in `ai/frontend/` from the feature
   template.
4. Create the dated handoff doc in `ai/frontend/handoff/` from the handoff template — new, changed,
   and breaking parts, with the contract (method, path, request fields + rules, response shape, auth,
   errors, pagination, states, visibility). Include a **«Подводные камни»** block: what the frontend
   must account for or the UI breaks — async states (a request that returns before the work is done),
   empty/error/loading states, ordering/idempotency of calls, visibility rules. Flag them proactively
   (per the blind-spot protocol); do not just document the happy-path contract.
5. Create or update the **runnable request package** for the touched endpoints (doc type 3) with the
   examples captured in the live run. **Reachability rule:** document a field or value only if real
   data can produce it end-to-end — a shape the backend cannot actually populate is not a contract; if
   the live run could not produce it, it is not documented as available.
6. Post a one-line pointer in chat (Russian) telling the user which docs were created/updated.
7. Run the commit step.

## Commit step

After the docs are written, **ask the user whether to commit** (e.g. «Закоммитить?»).

- If **yes**: stage the implementation changes together with the `ai/frontend/` docs and make a
  **single-line** commit message — imperative, behavior-first, English (commit messages follow the
  repo convention). **No AI attribution** — no `Co-Authored-By`, no "Generated with…" trailer
  (`attribution.commit` is set empty for this too). Commit on the current working branch; if on the
  default branch, note that to the user.
- If **no**: stop; leave everything staged-or-unstaged as the user prefers.

Never commit without the user's explicit yes in this turn.
