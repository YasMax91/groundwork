# Spec: Wave 9 — audience & language (plugin v0.14.0)

- Type: plugin self-improvement — methodology + one new skill + one new template (prose / templates;
  **no hooks, no scripts**). Cross-cutting change to how the agent addresses the reader → **L3**.
- Author: Max Yastremskyi (YasMax91). Owner: RaDevs.
- Source: the session-mined complaint brief for the v0.12.0 window (2026-07-21 → 2026-07-27). Wave 9 is
  the second package — jargon aimed at a non-technical owner (~8 cases, every project), a technical spec
  delivered where a **client document** was needed, estimates with no rule at all, and client/BA drafts
  arriving English-only. Follows [Wave 8](wave-8-live-verification.md) in the
  [feedback programme](plugin-enhancement-roadmap.md).
- Status: **draft — awaiting approval**. No files edited until approved.
- Target version: v0.14.0

## Goal

Make the plugin talk to the **person actually reading**. Today it writes for an engineer in every
channel: discovery reports and interview questions arrive as `errorCode 2406`, `uuid`, `rate-limit`,
`L2`, "декремент"; a client who does not know what a test is receives EARS criteria and developer hours;
a BA gets an English-only question list. The owner of the product then has to decode his own project —
"Не понимаю", "Не понял вопрос", "по-человечески, без жаргона" — or ask for the whole document to be
redone.

Wave 9 adds a **plain-language-first layer** wherever the user makes a decision, introduces the
**client document** as its own artifact (which the plugin simply does not have), fixes the estimate unit
at **real AI-hours to write the functionality** (the human reviews, never man-days), and makes every
client/BA-facing text ship with a **Russian mirror** without being asked.

## Problem (diagnosis)

Confirmed by inspection of the current plugin (v0.13.0) — each claim grepped, not assumed:

1. **Plain language is required in exactly one place.** `guidelines/blind-spot-protocol.md:15` ("in plain
   language") and `:44` ("why it matters (plain language)") are the **only** two occurrences in the whole
   plugin. `clarify-protocol.md` — the file that defines how questions are asked — never mentions it, so
   an `AskUserQuestion` round is free to offer options a non-technical owner cannot tell apart.
2. **The first response is a list of engineering labels.** `skills/start-task/SKILL.md:41-46` prescribes
   "current understanding · classification · files/docs to inspect · connections / blast radius · …" —
   every section technical, no layer that says what this means for the client or the business. The reader
   who must approve the plan meets the blast radius before he meets the point.
3. **No client document exists as an entity.** `skills/` holds 13 skills, none client-facing;
   `templates/` holds `project/`, `specs/`, `frontend/`, `adr.md`. The spec templates are
   irreducibly technical — `templates/specs/feature.md:28-46` is EARS criteria plus a red-test list —
   so a client deliverable can only be produced by bending `spec` into something it is not (which is
   what happened, and it needed a full rewrite).
4. **No estimation rule of any kind.** A grep for `estimat` / `hours` / `man-day` / `человеко` across
   `skills/`, `guidelines/`, and `templates/` returns **nothing** (the only `effort` hits are subagent
   frontmatter — model effort, not calendar time). So an estimate's unit is improvised per answer, and
   "developer hours / man-days" is the default the model reaches for — the wrong unit when an AI writes
   the code and the human only reviews it.
5. **Russian is an exception granted to two artifacts, and client/BA texts are not among them.**
   `skills/frontend-handoff/SKILL.md:15` (whole docs in Russian) and `skills/spec/SKILL.md:51-52` (the
   chat выжимка only) are the entire set. A client document or a BA question list therefore defaults to
   the English-artifact rule from `templates/project/CLAUDE.md:17` — which is why both arrived
   English-only and had to be re-asked for in Russian.
6. **Client-text style tics repeat.** Bullet lists where prose reads better ("Давай без списков"), and
   em dashes in text bound for SMS ("Замени — на -") — an em dash falls outside GSM-7, forcing UCS-2 and
   doubling the message cost. Neither is written down anywhere, so both recur.

## Boundaries — who each artifact is written for

The load-bearing rule: **`spec` stays technical.** The failure was bending it toward a client, not the
spec itself. Wave 9 adds a lane; it does not blur one.

| Artifact | Reader | Language | Contains |
|---|---|---|---|
| `docs/specs/*` (`spec` skill) | the bot + the developer | English (+ Russian выжимка in chat) | EARS criteria, red tests, FormRequest/Resource, migrations — **unchanged** |
| `ai/frontend/*` (`frontend-handoff`) | a human frontend developer | Russian (+ English contract terms) | what/when/how/why + the contract + the runnable package — **unchanged** |
| **`docs/client/*` (new `client-doc`)** | **the client, who knows nothing about development** | **English canonical (sent to the client) + Russian mirror (for the author)** | **outcome, scope in/out, AI-hours, what is needed from them, next steps — no tests, no AC/EARS, no endpoints, no architecture** |
| chat (discovery, questions, blind spots) | the product owner | Russian | plain-language meaning **first**, technical identifiers after |

Guardrail against the opposite failure: **plain language adds a layer, it never deletes the detail.**
Codes, field names, and status numbers stay — they are how the work gets done — they simply stop being
the opening. And it is scoped to where the user *decides* (discovery report, questions, blind spots,
client doc); a `final-check` handoff summary or an OpenAPI note stays engineering prose.

## Design — per item

### C1 — Plain-language-first, defined once (A2)

A new named section in `guidelines/clarify-protocol.md` — the plugin's guideline for how the agent
addresses the user — so there is exactly **one** definition, referenced elsewhere rather than copied:

- **Lead with the lived consequence, in everyday words.** What does the client see, what does the
  business lose, what breaks for a real person — *then* the identifier. "Клиент нажимает «Оплатить» и
  видит ошибку, деньги не списываются (внутренний код 2406, лимит второго уровня)" — not the reverse.
- **The test to apply before sending.** Could someone who has never opened this codebase tell what he is
  deciding and what it costs him? If not, rewrite it. A question whose options differ only by a code, a
  field name, or an internal term fails this test.
- **Never delete the technical layer** — it moves after the meaning, in parentheses or the next line.
- **Where it binds:** the `AskUserQuestion` question text, option labels, and option descriptions; the
  first-response discovery report; the blind-spot block (already required there — now the same rule, one
  source); the client document (wholly).

Wiring: `clarify-protocol.md` mechanics gain the rule; `skills/start-task/SKILL.md` step 7 gains a
plain-language opening layer **before** the technical sections — two or three sentences of "what this
means for the client / for the business" — and its interview step cites the rule;
`guidelines/blind-spot-protocol.md` replaces its two ad-hoc "plain language" mentions with a reference to
the single definition (no behavior change, one source of truth).

### C2 — The `client-doc` skill + template (A3 / B-A)

New `skills/client-doc/SKILL.md` (model-invocable — the agent should offer it when the deliverable is
clearly for a client) plus `templates/client-doc.md`.

- **Audience:** a client who does not know what a test, an endpoint, or a migration is. The document
  answers: what problem this solves · what you will be able to do that you cannot do now · what is
  included now and what is deliberately left for later · how long it takes · what we need from you ·
  what happens next · what is still open.
- **Explicitly absent** — and the skill says so, because this is the exact failure being fixed: no
  tests, no acceptance criteria / EARS, no endpoints or `FormRequest`/`JsonResource`, no schema or
  migrations, no architecture, no man-days. If the reader needs any of that, the artifact they want is a
  `spec`, not a client doc.
- **Style (A6):** prose over bullet lists where prose reads better — a client reads sentences, not a
  backlog; bullets only for genuinely enumerable things (what is in, what is out). **No em dashes in
  text that may travel by SMS** — a plain hyphen instead: `—` is outside GSM-7, so it forces UCS-2 and
  doubles the message cost. Never write "we will check this later" into a client text when the check is
  available now — run it, then write the answer (the live-verification discipline from Wave 8, applied to
  what the client is told).
- **Language (C4 below):** `docs/client/<slug>.en.md` is canonical and is what the client receives;
  `docs/client/<slug>.ru.md` is a full Russian mirror for the author.

### C3 — Estimates in AI-hours (B-1)

The rule, owned by `skills/client-doc/SKILL.md` (where estimates are delivered), with a two-line pointer
from `guidelines/ai-sdd-process.md` so it binds **any** estimate, in a document or in chat:

- The unit is **real AI-hours to write the functionality** — the time the agent spends producing working
  code, tests, and docs. **Never man-days, never developer hours**: a human does not write this code.
- **Shape:** a range per major block of functionality, a total, and a **separate line for the reviewer's
  time** — what the human spends checking and accepting, which is not development time and must not be
  folded into it.
- Ranges, not points (a single number reads as a promise); state what would push it to the upper bound.
- An estimate covers only what the current scope contains; deferred items are named as deferred with no
  hours attached, so "later" never silently reads as "included".

### C4 — Client/BA texts ship with a Russian mirror (A4)

Settled 2026-07-27 as **plugin core**, not a personal preference, and settled again the same day on
form: the client receives **English**, the author reads **Russian**.

- Any client- or BA-facing deliverable — a client document, a BA question list, a message to be
  forwarded — is produced in **both**, in the same pass, **without being asked**.
- **English is canonical** (it is what is sent). The Russian file is a **mirror regenerated from the
  English**, never edited independently — that is what keeps two files from drifting: edits land in
  English, the mirror is rewritten from it.
- Filenames carry the language (`<slug>.en.md` / `<slug>.ru.md`) so the sendable file is never ambiguous.
- This extends the existing exception list (`frontend-handoff`, the `spec` выжимка) rather than
  contradicting the English-artifact rule — the reader is a human, same as those two.

### C5 — Rollout

`.claude-plugin/plugin.json` → `0.14.0`; `README.md` "What's inside" documents the plain-language layer,
the `client-doc` artifact, and the AI-hours rule, and the Layout lists the new skill + template;
`plugin-enhancement-roadmap.md` marks Wave 9 shipped.

## Acceptance criteria (EARS)

Structural verification (inspect the Markdown / templates), plus one dogfood: a real discovery response
whose opening layer is plain language, and one generated client doc pair.

- [ ] **W9-AC1** THE guideline `guidelines/clarify-protocol.md` SHALL define the plain-language-first
      rule once — lead with the lived consequence in everyday words, keep the technical identifier after
      it, and apply the "could a non-technical reader tell what he is deciding?" test — AND SHALL bind it
      to the `AskUserQuestion` question text, option labels, and option descriptions.
      → check: guidelines/clarify-protocol.md
- [ ] **W9-AC2** THE first-response structure in `skills/start-task/SKILL.md` SHALL open with a
      plain-language layer (what this means for the client / the business) **before** the technical
      sections, AND the technical sections SHALL remain intact.
      → check: skills/start-task/SKILL.md
- [ ] **W9-AC3** THE plain-language rule SHALL exist in exactly one authoritative place;
      `guidelines/blind-spot-protocol.md` SHALL reference it instead of restating it.
      → check: guidelines/blind-spot-protocol.md + guidelines/clarify-protocol.md
- [ ] **W9-AC4** THE skill `skills/client-doc/SKILL.md` SHALL exist, SHALL define its reader as a client
      who does not know development, AND SHALL explicitly exclude tests, acceptance criteria / EARS,
      endpoints / FormRequest / JsonResource, schema / migrations, architecture, and man-days — naming
      `spec` as the artifact for those. → check: skills/client-doc/SKILL.md
- [ ] **W9-AC5** THE template `templates/client-doc.md` SHALL exist and SHALL cover: the problem, what
      the client will be able to do, what is in scope now, what is deferred, the estimate, what is needed
      from the client, next steps, and open questions — with no technical section.
      → check: templates/client-doc.md
- [ ] **W9-AC6** THE client-doc style rules SHALL require prose over bullet lists where prose reads
      better, SHALL forbid em dashes in text that may travel by SMS (plain hyphen; `—` breaks GSM-7 and
      doubles cost), AND SHALL forbid promising the client a check that can be run now.
      → check: skills/client-doc/SKILL.md
- [ ] **W9-AC7** WHEN an estimate is given, THE unit SHALL be real AI-hours to write the functionality —
      never man-days or developer hours — presented as a range per block plus a total plus a **separate**
      reviewer-time line, with deferred items carrying no hours; AND `guidelines/ai-sdd-process.md` SHALL
      point at the owning rule so it binds estimates given in chat too.
      → check: skills/client-doc/SKILL.md + guidelines/ai-sdd-process.md
- [ ] **W9-AC8** WHEN a client- or BA-facing deliverable is produced, THE skill SHALL produce the English
      canonical file **and** the Russian mirror in the same pass without being asked, with the language in
      the filename (`.en.md` / `.ru.md`), AND SHALL state that English is canonical and the Russian mirror
      is regenerated from it rather than edited independently. → check: skills/client-doc/SKILL.md
- [ ] **W9-AC9** THE `spec` skill and the spec templates SHALL remain technical and unchanged in
      audience — no client-facing content folded into them.
      → check: skills/spec/SKILL.md + templates/specs/*.md
- [ ] **W9-AC10** `.claude-plugin/plugin.json` SHALL be `0.14.0`; `README.md` SHALL document the
      plain-language layer, the client document, and the AI-hours rule and list the new files in the
      Layout; AND the roadmap SHALL record Wave 9 as shipped.
      → check: .claude-plugin/plugin.json + README.md + plugin-enhancement-roadmap.md

## Risks / assumptions

- **Plain language read as dumbing down (primary risk).** The rule must not strip the detail the work
  needs. Mitigated by making it a **layer** — meaning first, identifiers after, nothing deleted — and by
  scoping it to decision surfaces, leaving `final-check` summaries and OpenAPI notes as engineering prose.
- **Two-file drift for the client doc.** Mitigated by construction: English is canonical, the Russian
  file is regenerated from it and never edited on its own. The remaining failure mode (someone edits the
  mirror) is visible in git, unlike a silent divergence.
- **The agent guessing the client's language.** English canonical is the settled default here; a project
  whose client reads another language states it in its `AGENTS.md`, and the skill follows that.
- **`client-doc` firing when a spec was wanted.** A model-invocable skill can trigger on the wrong
  deliverable. Mitigated by the explicit exclusion list plus the boundaries table — the moment tests,
  criteria, or endpoints are wanted, the answer is `spec`.
- **Estimate accuracy.** AI-hours are still an estimate; ranges plus the "what pushes it to the upper
  bound" note keep it honest. The unit change fixes the *category* error (man-days for work a human does
  not do), not forecasting itself.
- **Assumption.** The em-dash / GSM-7 rule matters only for text bound for SMS or a messenger; in a
  document read on screen the em dash is harmless. Scoped accordingly rather than banned globally.

## Rollout

- Version **v0.14.0**. Additive — one new skill, one new template, prose edits; **no hook or script
  changes**, no change to `spec`'s audience, and nothing touched in the Wave 8 live-verification path.
- Commit (single line, no AI attribution):
  `feat: v0.14.0 — plain-language-first communication, client-doc artifact, AI-hours estimates`.

## Verification plan

Inspect each touched file against W9-AC1–AC10. Confirm `client-doc` appears in the skill list. Dogfood:
one discovery response that opens in plain language, and one client-doc pair (`.en.md` + `.ru.md`) whose
estimate is AI-hours by block with a separate reviewer line and no technical section. Run
`conformance-reviewer` on the diff. Structural + one dogfood; methodology and prose, no scripts.
