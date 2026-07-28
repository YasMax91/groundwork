---
description: Write a client-facing document for a non-technical client — the outcome, what is in and out of scope, an AI-hours estimate, and what is needed from them. English canonical file plus a Russian mirror under docs/client/. Not a substitute for an implementation spec.
---

# Client document

The reader is a **client who does not know what a test, an endpoint, or a migration is.** He is deciding
whether this work is worth paying for and what he gets. Write for him.

**This is not a spec.** The `spec` skill produces the technical contract for the bot and the developer —
`docs/specs/`, EARS acceptance criteria, a red-test list, request/response shapes. It is the right
artifact for building and the wrong one for a client. Bending one into the other is the exact failure
this skill exists to prevent.

## What it never contains

no tests or test plans · no acceptance criteria / EARS / clause IDs · no endpoints, routes, `FormRequest`,
`JsonResource` · no schema, migrations, or queries · no architecture, layers, or class names · no
man-days or developer hours · no internal code or status number as the opening of a sentence.

If the reader needs any of that, the artifact he wants is a **spec**. Say so and switch, rather than
producing a hybrid that serves neither.

## Structure

Template: `${CLAUDE_SKILL_DIR}/../../templates/client-doc.md` — the problem it solves · what the client
will be able to do · what is included now · what is left for later · how long it takes · what is needed
from him · what happens next · what is still open.

## Style

- **Prose, not a backlog.** Sentences and short paragraphs. Bullets only for genuinely enumerable things
  (what is in, what is out). A client reads prose; a wall of clauses reads as an invoice.
- **No em dashes in text that may travel by SMS or a messenger** — use a plain hyphen. `—` falls outside
  GSM-7, which forces UCS-2 encoding and doubles the cost per message.
- **Everyday words first**, per the layered rule in
  `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`. Where an internal term is unavoidable,
  explain it in the same sentence, in words the client already uses.
- **Never promise a check you can run now.** "We will verify this later", written while the probe is
  available today, is a deferral the client pays for. Run it, then write what it showed (the live-proof
  discipline in `${CLAUDE_SKILL_DIR}/../final-check/SKILL.md`).
- **No invented certainty.** Anything undecided or unverified is named as open, not smoothed over.

## Estimating — real AI-hours, never man-days

The unit is the **real time the AI spends writing the functionality** — producing the working code, its
tests, and its documentation. A human does not write this code; he reviews and accepts it. **Man-days and
developer hours are therefore the wrong unit and never appear.**

**Calibrate the numbers before writing them down** — measure the repo's own throughput from `git log`,
estimate the delta where the work already exists in history, and sanity-check the total against that
throughput. The rules are in
[`../../guidelines/ai-sdd-process.md`](../../guidelines/ai-sdd-process.md) §Estimates; this section
only governs how the calibrated numbers are presented to the client.

- **A range per block of functionality, then a total.** A single number reads as a promise; a range reads
  as an estimate. Name what would push it to the top of the range.
- **The reviewer's time is its own line** — what the client's side spends checking and accepting. It is
  not development time and is never folded into it.
- **Deferred scope carries no hours.** Name it as deferred with no number, so "later" cannot be read as
  "included".

## Language — English is what you send, Russian is what you read

Two files, same content, produced in the **same pass, without being asked**:

- `docs/client/<slug>.en.md` — **canonical.** This is the file the client receives.
- `docs/client/<slug>.ru.md` — a **full Russian mirror**, so the author can read and check the whole
  document before sending it.

**Edits land in English; the mirror is regenerated from it.** Never edit the Russian file on its own —
one direction of generation is what keeps the two from drifting. If the project's client reads another
language, the project's `AGENTS.md` says so and this skill follows it.

The same applies to any other text **the user will send onward** — a question list for a BA, a message to
forward: produce both versions unasked. It does not reach the working conversation itself: questions the
agent asks *the user* are simply in the user's language. This extends the exception the `frontend-handoff`
docs already hold — the reader is a human, so the language serves the reader rather than the
English-artifact rule.

## Steps

1. **Ground the content in reality** — what the system does today, what it will do, and what is genuinely
   unknown come from the code, the CRD, and live checks, not from optimism. See
   `${CLAUDE_SKILL_DIR}/../../guidelines/grounding-protocol.md`.
2. Fill the template in plain language, prose first.
3. Estimate per the rule above — AI-hours by block, a total, the reviewer's time separate.
4. Write `docs/client/<slug>.en.md`, then generate `docs/client/<slug>.ru.md` from it.
5. Post a short Russian pointer in chat — which files, and the one-line gist.
6. **Ask whether to commit** (single line, no AI attribution). Never commit without an explicit yes.
