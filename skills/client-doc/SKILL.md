---
description: Write a client-facing document for a non-technical client — the outcome, what is in and out of scope, an estimate in the agent's real build time, and what is needed from them (with their own time on a separate line). English canonical file plus a Russian mirror under docs/client/. Not a substitute for an implementation spec.
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

Everything in [`../../guidelines/writing-standards.md`](../../guidelines/writing-standards.md) applies —
every sentence carries a fact, no preambles or wrap-ups, no filler vocabulary, no self-praise, no section
kept alive without content. A client document is where slop costs the most: he is paying for what it
says, so anything that says nothing reads as padding on the invoice. On top of that:

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

## Estimating — the agent's real time, never man-days

The unit is the **wall-clock time the AI actually spends writing the functionality** — the working code,
its tests, its documentation. A human does not write this code; he reviews and accepts it. **Man-days and
developer hours are the wrong unit and never appear** — and neither does a man-day wearing a smaller
unit: work on mechanisms the codebase already has is normally minutes, and publishing it as hours is the
same error with better manners.

**Calibrate the numbers before writing them down** — read the measured ledger
(`${CLAUDE_PLUGIN_ROOT}/hooks/estimate-ledger.sh --report`), estimate the delta where the work already
exists in history, and sanity-check the total against both. Producing the calibrated numbers is the
`estimate` skill ([`../estimate/SKILL.md`](../estimate/SKILL.md)); the rules behind them are in
[`../../guidelines/ai-sdd-process.md`](../../guidelines/ai-sdd-process.md) §Estimates. **This section
only governs how those numbers are presented to the client** — and the client sees the number, never the
median or the sample size behind it. Those belong in the chat summary you post for yourself, so you can
check the document before sending it.

- **A line per block of functionality, then a total.** A range where the work is genuinely uncertain, a
  single number where it is not — a range whose ends differ by minutes is false precision. Name what
  would push it to the top of the range.
- **What needs a person is its own section, never added to the development number.** Two kinds belong
  there: what only the client can do — register an account with a provider, issue API keys, configure a
  webhook in his own dashboard, pass a verification, grant access, decide an open question — and the time
  his side spends reviewing and accepting the result. Each carries its own number and its owner, in the
  client's words ("create the account in the payment provider's dashboard", not "provision credentials").
- **Deferred scope carries no time.** Name it as deferred with no number, so "later" cannot be read as
  "included".
- **A date, if he asks for one, is the AI's time plus the wait on those human steps** — never the
  development number padded to cover the waiting.

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
3. Estimate per the rule above — the AI's real time by block, a total, and everything that needs a
   person in its own section.
4. Write `docs/client/<slug>.en.md`, then generate `docs/client/<slug>.ru.md` from it.
5. Post a short Russian pointer in chat — which files, and the one-line gist.
6. **Ask whether to commit** (single line, no AI attribution). Never commit without an explicit yes.
