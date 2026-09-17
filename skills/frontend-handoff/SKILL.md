---
description: Produce the frontend-developer handoff docs in docs/ai/frontend after a backend feature or change is fully implemented and the gates are green. Writes a Ukrainian instruction doc — what to build, when, how, why, where, plus the API contract (no frontend code) — stamps the front-matter the documentation portal groups by, updates the affected reference docs, then offers to commit. Use as the closing step of any implementation that changes the frontend-facing surface (endpoints, response shape, validation, auth, states, visibility).
---

# Frontend handoff (docs for the frontend developer)

Run this **after the full, final implementation** is done and the gates are green (after
`final-check`). It produces the documentation a frontend developer reads, then hands to their own AI
to build the UI against this backend and the design.

## Audience & language

- The reader is a **human frontend developer** who studies the doc, then passes it to their AI to
  compose the backend contract + design into a frontend.
- **Write these docs in Ukrainian** — they are a human handoff, an explicit exception to the
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

## Document types (all live under `docs/ai/frontend/`, the dir from `.groundwork.json` `docs.frontend`)

1. **Living reference doc** — `docs/ai/frontend/<area>.md`, the current truth for a feature/area
   (the "первоначальный документ"). Template: `${CLAUDE_SKILL_DIR}/../../templates/frontend/feature.md`.
   - **New functionality with no existing doc** → create it.
   - **A change** → edit the reference doc(s) the functionality touches so they describe current
     reality (add the new parts, fix the changed parts, remove the gone parts).
2. **Handoff instruction doc** — `docs/ai/frontend/handoff/<YYYY-MM-DD>-<slug>.md`, the delta you physically
   hand over. Template: `${CLAUDE_SKILL_DIR}/../../templates/frontend/handoff.md`. **Always create one**
   for a frontend-facing change, covering **new · changed · removed (breaking)** functionality.
3. **Runnable request package** — `docs/ai/frontend/http/<area>.postman_collection.json` **or**
   `docs/ai/frontend/http/<area>.http` (pick one per project and stay consistent), so the frontend **runs** the
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

4. **Contract snapshot** — `docs/ai/frontend/openapi/<YYYY-MM-DD>-<slug>.yaml|json`, the generated OpenAPI
   document as it stands at handoff, copied from the project's `openapi.spec_path` (`.groundwork.json`)
   after the generator has run. It is **committed with the work**: the frontend types against it, and a
   later contract diff needs a base that exists in git. Prose describes the change; this file *is* the
   contract, and the frontend can serve it as a mock before the backend is deployed:

   ```bash
   npx -y @stoplight/prism-cli mock docs/ai/frontend/openapi/<YYYY-MM-DD>-<slug>.yaml
   ```

   A project that documents no API (`openapi.enabled: false`, or no generator) skips this and says so
   in the handoff doc — the absence is stated, not silent. Without node on the machine, the snapshot is
   still committed and the mock line is marked as untried.

## Front-matter — how these documents are found

Every document under `docs/ai/frontend/` opens with a front-matter block. It is not decoration: the
project's documentation portal (`/dev/docs/<token>` on development and staging) builds its whole
grouping from it, so a document without the block is invisible to the reader it was written for, and
a grouping kept anywhere else would drift away from the files. A project without the portal yet gets
it from `groundwork:install-portal`; stamp the front-matter either way, so the documents are ready
the day it is installed.

A handoff:

```yaml
---
title: "Залишки приходять з 1С"          # human name, Ukrainian, no date in it
feature: ["catalog", "variants", "cart"]  # first = where it is filed, rest = also touched
area: catalog                             # section: see the areas in config/docs_portal.php
date: 2026-09-17
type: handoff
status: current
breaking: true                            # does a written frontend break if it ignores this?
lang: uk
spec: ["docs/ai/specs/2026-09-onec-stock-intake.md"]
openapi: ["docs/ai/frontend/openapi/2026-09-17-onec-stock-intake.json"]
http: ["docs/ai/frontend/http/onec-stock.http"]
---
```

A reference doc:

```yaml
---
title: "Каталог: фільтри, сортування, пошук"
feature: catalog          # the slug is this file's own basename
area: catalog
type: feature
updated: 2026-09-17
lang: uk
---
```

Three rules that are easy to get wrong:

- A feature's slug **is the basename of its reference doc**. If the functionality has no reference
  doc yet, put `feature_title: "<name>"` on the handoff — the portal then shows the feature by name
  and marks that the consolidated document is missing, rather than hiding the gap.
- When this handoff **replaces** an earlier one, edit the earlier document's front-matter:
  `status: superseded` and `superseded_by: "<that file's name>"`. Never rewrite its body — a delta is
  a dated record, and the portal already marks it as history for the reader.
- `breaking: true` is about the reader's existing code, not about the size of the change. An
  additive field is not breaking; a field that kept its type and changed its meaning is.

## Steps

1. Document the **final** contract, not an intermediate one.
2. Identify the frontend-facing surface that changed. If none, state "нет влияния на фронтенд" and go
   to the commit step.
3. New vs change: create or update the living reference doc(s) in `docs/ai/frontend/` from the feature
   template.
4. Create the dated handoff doc in `docs/ai/frontend/handoff/` from the handoff template — new, changed,
   and breaking parts, with the contract (method, path, request fields + rules, response shape, auth,
   errors, pagination, states, visibility). Stamp its front-matter per the section above, and mark any
   predecessor this one replaces as `superseded`. Include a **«Подводные камни»** block: what the frontend
   must account for or the UI breaks — async states (a request that returns before the work is done),
   empty/error/loading states, ordering/idempotency of calls, visibility rules. Flag them proactively
   (per the blind-spot protocol); do not just document the happy-path contract.
5. Copy the **contract snapshot** (doc type 4) from `openapi.spec_path` into `docs/ai/frontend/openapi/`,
   dated and slugged, and link it from the handoff doc's header together with the mock command. If the
   generator did not run in this task, run it first — a snapshot older than the code is a contract that
   lies.
6. Create or update the **runnable request package** for the touched endpoints (doc type 3) with the
   examples captured in the live run. **Reachability rule:** document a field or value only if real
   data can produce it end-to-end — a shape the backend cannot actually populate is not a contract; if
   the live run could not produce it, it is not documented as available.
7. Post a one-line pointer in chat (Russian) telling the user which docs were created/updated.
8. Run the commit step.

## Commit step

After the docs are written, **ask the user whether to commit** (e.g. «Закоммитить?»).

- If **yes**: stage the implementation changes together with the `docs/ai/frontend/` docs and make a
  **single-line** commit message — imperative, behavior-first, English (commit messages follow the
  repo convention). **No AI attribution** — no `Co-Authored-By`, no "Generated with…" trailer
  (`attribution.commit` is set empty for this too). Commit on the current working branch; if on the
  default branch, note that to the user.
- If **no**: stop; leave everything staged-or-unstaged as the user prefers.

Never commit without the user's explicit yes in this turn.
