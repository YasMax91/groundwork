# Spec: Wave 21 — two production defect classes get a rule where the agent will see it (v0.31.0)

- Type: plugin self-improvement → **L2** (four prose/template files, no new mechanism).
- Author: Max Yastremskyi (YasMax91).
- Source: item E28 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). Structural, with one behavioural criterion (AC4) that is
  enforced by an existing mechanism and was not executed here — stated as such below.
- Target version: **v0.31.0**.

## Goal

Two defects that reach production in payment- and order-shaped backends — the plugin's stated
specialty — were nowhere in its instructions: a job dispatched inside a transaction, and a webhook
delivered twice. Put each rule in the file the agent already reads at the moment it can still act.

## Problem (diagnosis)

- `skills/implement-approved/SKILL.md:23` requires transactions around multi-step domain writes. That
  requirement is what creates the defect: a job dispatched inside `DB::transaction` can be picked up by
  a worker before the commit lands, and it reads a row that does not exist yet. `grep -rniI
  'aftercommit|after_commit'` over the whole repository returned **0**.
- `templates/specs/integration-change.md:33` had AC3 — *our* retry of an outgoing call stays
  idempotent. The reverse direction, *their* redelivery of an incoming event, had no criterion, though
  at-least-once is the default contract of every webhook that retries. That is how one charge gets
  recorded twice.
- `skills/ground-integration/SKILL.md` built a free-form capability matrix. Whether the provider takes
  an idempotency key, whether delivery is at-least-once, and whether an event has a stable id are the
  three answers that decide if the integration can be made safe at all — and none is guessable.

## Design

- **`skills/implement-approved/SKILL.md`** — the transaction bullet now carries its own consequence:
  a job or event dispatched inside a transaction goes out via `->afterCommit()` (or `after_commit` on
  the queue connection), with the race spelled out in one clause.
- **`skills/risk-review/SKILL.md`** — the same rule as something to *find* in a diff, inside the
  existing "Queues / scheduler / cache" item.
- **`templates/specs/integration-change.md`** — new **AC4**: a repeated delivery is a no-op, keyed on a
  unique `(provider, event_id)` record written in the same transaction as the effect, with a `→ test:`
  pointer. Unconditional by decision: a provider without callbacks keeps the line and writes
  `N/A — <provider> has no webhooks/callbacks (evidence: <URL>)`. An assumption that is written down
  can be checked; an omitted one cannot.
- **`skills/ground-integration/SKILL.md`** — the three rows above are mandatory in every capability
  matrix; `UNKNOWN` on any of them blocks coding exactly like any other unresolved row.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | The `afterCommit` rule exists in the skills, not only in a guideline | met — 2 matches, `implement-approved:25` and `risk-review:45`; 0 before |
| AC2 | The rule sits next to the requirement that causes the defect | met — same bullet as "transactions around multi-step domain writes" |
| AC3 | The integration template carries a redelivery criterion keyed on `(provider, event_id)` with a `→ test:` pointer | met — AC4, and the red-test list now names duplicate delivery |
| AC4 | A spec that leaves AC4 empty cannot pass conformance as CONFORMS | **not executed** — it rests on the existing rule in `agents/conformance-reviewer.md:28` ("a criterion with a `→ test:` pointer is met only if the diff contains that test"). Structural inheritance, not a run |
| AC5 | The capability matrix cannot be filled without answering the three delivery questions | met — the three rows are marked mandatory, with the `N/A` form defined |

## Deliberately not done

- **A PHPStan rule for dispatch-inside-transaction.** A text grep gives false positives on multi-line
  closures, and a real rule is a separate piece of work with its own test fixture. Until then this is
  an instruction, labelled as one — consistent with wave 20 rather than a second false gate.
