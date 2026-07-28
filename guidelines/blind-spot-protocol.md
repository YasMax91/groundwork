# Blind-spot protocol (Groundwork) — surface what the user doesn't know to ask

The user cannot ask about what he does not know he is missing. The plugin already catches **known
unknowns** — ambiguity in what was said (the clarify pass), code blast radius (`impact-mapper`), a
fixed engineering risk checklist (`risk-review`). This protocol covers the **unknown unknowns**: the
omitted dimension, the unintended consequence, the domain/product angle the user is not the expert in.
The agent must raise these **on its own initiative**, before being asked.

## Mandate — advise, don't only execute

You are an expert advisor, not only an executor. Challenge the **intent**, not only the execution:
"you asked for X, but it will cause Y" · "you also need Z for this to work the way you expect" · "in
this scope it won't meet your own stated goal W" · "this solves a different problem than the one you
have". The user is not the expert here — so a bare term is useless: always give the **consequence**
(the "so what") and a **path forward**, under the plain-language rule that
[clarify-protocol.md](clarify-protocol.md) defines for every text the user decides on (meaning in
everyday words first, the identifier after it).

This is distinct from every existing mechanism — keep them in their lanes, cite them, never duplicate:

| Mechanism | Answers | blind-spot is different because |
|---|---|---|
| `impact-mapper` | "what will my change break?" (code couplings) | it predicts *missing dimensions*, not existing couplings |
| clarify pass | "what did you mean, and which do you choose?" | it predicts what was **not** said at all |
| `risk-review` | "is there a *known* risk in what was done?" (checklist) | it is open-ended and runs at **entry**, on the intent |
| `adversarial-verifier` | "is the it-works claim true?" | it questions the *request*, not the claim |

## Taxonomy — run the checklist, don't rely on inspiration

Walk these categories against the task; a project may extend them in its `AGENTS.md`:

1. **Data & state** — concurrency/races, idempotency (double-submit, retries), transactionality,
   cascade/soft-delete, uniqueness, existing-row backfill/migration, timezones, money precision/rounding.
2. **Scale & performance** — N+1, pagination, indexes, payload size, timeouts, rate limits.
3. **Security & privacy** — authorization on every path, data leakage in the response/logs, PII/privacy,
   audit trail.
4. **Compatibility** — API backward-compat, client/mobile app versions, breaking the frontend contract.
5. **Operability** — rollback, zero-downtime migration, feature flags, observability/alerts, retries.
6. **Domain & product** — solving the *right* problem, does the scope meet the stated goal, business-rule
   edge cases, conflict with an existing user expectation, localization.
7. **External integrations** — webhook ordering/retries/idempotency, partial failures, keeping external
   state consistent with local state.

## Output — one line per blind spot

Each item: **what's missed · why it matters (plain language) · consequence if ignored · recommendation
or options · priority (high/med/low) · `verified`/`assumed`**. Surface them as a **blind spots** block,
separate from `clarifications` (clarify settles what the user must *decide*; this predicts what they
never raised).

**An item that needs a product call does not stay a bullet.** Hand it to the interview as a frontier
question carrying your recommendation, per [clarify-protocol.md](clarify-protocol.md) — prediction
surfaces the dimension, the interview settles it.

**When the level's interview calibration will not admit it** — a non-blocking item at L0/L1, or a
non-blocking one past L2's single round — there is a third path, and it is never "drop it": record it as
an **explicit assumption** with its consequence, in the first response and in the spec. Surfaced and
assumed is honest; silently discarded because the question budget was full is not.

## Calibration — material only, or say "none" (the make-or-break rule)

An over-firing blind-spot pass is noise and erodes trust. So:

- **Proportional to level** — L0/L1: inline, 0–2 items and only if genuinely material (or nothing);
  L2: the self-authored block in the first response; L3/L4: the block **plus** the `blind-spot-mapper`
  agent in a fresh context.
- **Material and non-obvious only** — never raise what the user already decided explicitly, or the
  trivial/obvious. Rank by importance; cap at the top ~5–7.
- **"None" is an honest answer** — do not fabricate blind spots to look thorough. Absence of a real gap
  is a valid result (mirrors the grounding protocol's "don't guess instead of check").
- **No duplication** — an item already owned by `impact-mapper` / clarify / `risk-review` is cited once,
  not re-raised here.

## How to run it

The level sets the depth (see Calibration). Where `blind-spot-mapper` runs, it runs in a **fresh
context** — it sees the task and the plan, not your reasoning, so the framing that produced the blind
spot cannot reproduce it — and returns a ranked list in the output format above.

- The `spec` skill records the resolved blind spots in the spec's "Blind spots considered" section;
  `implement-approved` escalates any new one found mid-build; `final-check` re-passes for blind spots the
  finished implementation itself created.

## Reference case

A user asks for "add order cancellation". Executed literally, it ships — and in production a double
click double-refunds (no idempotency), a paid order is cancelled with no provider refund flow, and
stock never returns to inventory. None of these were in the request; all are standard for the domain. A
blind-spot pass raises them **before** the plan, each with its consequence and a recommended default —
so the user decides with the full picture instead of discovering it in production.
