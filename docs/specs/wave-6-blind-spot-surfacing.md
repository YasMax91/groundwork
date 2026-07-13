# Spec: Wave 6 — blind-spot surfacing (plugin v0.10.0)

- Type: plugin self-improvement — methodology + one new agent (prose / templates / frontmatter; no
  hooks, no scripts). Cross-cutting UX change → treated as **L3**.
- Source: post-roadmap UX request — "agents must predict what I don't know I'm missing". Extends the
  [enhancement roadmap](plugin-enhancement-roadmap.md) (Wave 6, beyond the original E1–E9).
- Status: approved → implemented (2026-07-13); conformance review CONFORMS (W6-AC1–AC11)
- Target version: v0.10.0

## Goal

Give the workflow a **proactive blind-spot muscle**: the agent must, without being asked, surface the
dimensions the user did not think of — unstated consequences, hidden couplings, and domain/product
angles where the user is not the expert — and explain *why it matters* and *what it will break*, in
plain language. Today the plugin catches **known unknowns** (ambiguities in what was said, technical
blast radius, a fixed engineering risk checklist); it has no mechanism for **unknown unknowns** — the
things the user cannot ask about because he does not know they exist.

## Problem (diagnosis)

Proactive blind-spot detection exists today only in three narrow forms: code couplings
(`impact-mapper` / `deep-discovery`), external-API capability assumptions (`grounding` /
`deep-grounding`), and a fixed 8-dimension engineering risk checklist (`risk-review` / `deep-review`).
Confirmed gaps:

1. **No challenge of the intent at task entry.** The first response surfaces only *ambiguities in what
   was said* (the clarify pass) — it never predicts the *omitted* dimension.
2. **Nobody audits the completeness of the spec itself.** The whole downstream (`conformance-reviewer`,
   `final-check`, converge) validates conformance *to* the spec; `conformance-reviewer` is deliberately
   barred from questioning the criteria ("stay in that lane"). A blind spot baked into the spec is
   caught by no one.
3. **The standing skeptic points the wrong way.** `adversarial-verifier` challenges "it works", not the
   soundness/completeness of the request.
4. **No product/domain layer.** Every proactive mechanism is technical; the plugin assumes the user's
   goal and solution are correct and only validates the execution.
5. **A blind spot found during implementation has no escalation path** (`implement-approved` is pure
   execution).

## Boundaries — how blind-spot surfacing differs from what exists

This is the load-bearing design decision: the new muscle must **not** become a fourth overlapping
noise source. Each existing mechanism keeps its lane; blind-spot surfacing owns the empty one.

| Mechanism | Question it answers | When |
|---|---|---|
| `impact-mapper` | "What will my change break?" (code couplings) | Discovery |
| clarify pass | "What did you mean?" (ambiguity in what was **said**) | Pre-plan |
| `risk-review` / `deep-review` | "Is there a *known* engineering risk in what was done?" (fixed checklist) | Review |
| `adversarial-verifier` | "Is the *it-works* claim true?" | Verification |
| `conformance-reviewer` | "Does the diff match the spec?" | Verification |
| **blind-spot surfacing (new)** | **"What dimension did you not think of — including product/domain — that you don't know you don't know?"** | **Task entry, proactively** |

Blind-spot surfacing references the others; it never duplicates them (an item already covered by the
impact map, clarify, or the risk checklist is cited, not re-raised).

## Design — per item

### B1 — `blind-spot-protocol` guideline (the core)

New `guidelines/blind-spot-protocol.md`, in the shape of `grounding-protocol.md` (motto · mandate ·
taxonomy · output format · calibration · reference case). It defines:

- **The advisory mandate.** The agent is an expert advisor, not only an executor: it must challenge the
  *intent*, not only the *execution* — "you asked X, but it will cause Y / you also need Z / this won't
  meet your own goal W." It raises these on its own initiative, never waiting to be asked.
- **The blind-spot taxonomy** (the systematic checklist the agent runs, so coverage is not left to
  inspiration). Laravel-backend default categories, extensible per project via `AGENTS.md`:
  1. **Data & state** — concurrency/races, idempotency, transactionality, cascade/soft-delete,
     uniqueness, existing-data backfill/migration, timezones, money precision/rounding.
  2. **Scale & performance** — N+1, pagination, indexes, payload size, timeouts, rate limits.
  3. **Security & privacy** — authorization on every path, data leakage in response/logs, PII/privacy,
     audit trail.
  4. **Compatibility** — API backward-compat, client/mobile versions, breaking the frontend contract.
  5. **Operability** — rollback, zero-downtime migration, feature flags, observability/alerts, retries.
  6. **Domain & product** — solving the *right* problem, does the scope meet the stated goal,
     business-rule edge cases, conflict with an existing user expectation, localization.
  7. **External integrations** — webhook ordering/retries/idempotency, partial failures, external-state
     consistency.
- **Per-item output format:** *what's missed · why it matters (plain language) · consequence if ignored
  · recommendation/options · priority (high/med/low) · `verified`/`assumed`*. The user is not the
  expert — a term without its consequence is useless; always give the "so what" and a path forward.
- **Anti-noise calibration (mandatory — the make-or-break rule):**
  - **Proportional to level** — L0/L1: inline, 0–2 items and only if genuinely material (or none);
    L2: the self-authored block in the first response; L3/L4: the block **plus** the `blind-spot-mapper`
    agent.
  - **Material and non-obvious only** — never raise what the user already decided explicitly, or what
    is trivial/obvious. Rank by importance; cap at the top ~5–7.
  - **"None" is an honest answer** — do not fabricate blind spots to look thorough (mirrors the
    grounding protocol's "don't guess" and the reviewers' "over-reporting is failure").
  - **No duplication** — an item already owned by `impact-mapper` / clarify / `risk-review` is cited,
    not re-raised.

Wire into `guidelines/ai-sdd-process.md`: a one-line principle in Operating modes; **blind spots** added
to the first-response structure (distinct from `clarifications`) and to the Definition of Ready.

### B2 — `blind-spot-mapper` agent + fan-out

New `agents/blind-spot-mapper.md` (sibling to `impact-mapper`: that one maps code couplings, this one
maps the uncovered *dimensions*). Runs in a **fresh context** — it receives the task statement + the
spec/plan but **not** the author's reasoning, so it is not infected by the framing that produced the
blind spot in the first place (the same fresh-context leverage as `conformance-reviewer`). It runs the
taxonomy, returns a **ranked** blind-spot list in the B1 output format, and explicitly delimits itself
from the four existing agents (it is not the coupling mapper, not the risk checklist, not the it-works
skeptic, not the conformance judge). `tools: Read, Grep, Glob, Bash`; `effort: high` (the job needs
care/expertise); **`model` unset** (inherit — same rule as Wave 4 E9). Carries the B1 anti-noise
calibration verbatim so a fresh-context agent cannot become an over-reporter.

Fan-out: extend the "Fan-out by level" table + startup sequence in `ai-sdd-process.md` and the
`start-task` map step — `blind-spot-mapper` is **optional at L2, required at L3/L4** (Discovery phase,
alongside `impact-mapper`). Implementation stays single-threaded (unchanged).

### B3 — pipeline touchpoints (full-coverage option, per the user's choice)

- **Spec** — add a "**Blind spots considered**" section to every `templates/specs/*.md` (what the user
  may not have considered + how the spec closes it *or* deliberately defers it); `skills/spec/SKILL.md`
  instructs filling it. This closes gap #2 at the point the spec is written — the completeness the
  `conformance-reviewer` may not question is now authored in and audited by `blind-spot-mapper` upstream.
- **Implementation escalation** — `skills/implement-approved/SKILL.md`: when a TDD slice reveals a
  missed dimension with material consequences, **stop and surface it** (do not silently work around it).
  Closes gap #5.
- **Final check** — `skills/final-check/SKILL.md` converge step gains a **blind-spot re-pass**: new blind
  spots the finished implementation created (e.g. a state that is now async).
- **Risk review** — `skills/risk-review/SKILL.md` (+ `skills/deep-review/workflow.md`) gain an **open
  "other consequences beyond the checklist"** category and a **domain/product lens**, and state
  explicitly that risk-review may run on the **plan at entry**, not only on the diff.
- **Frontend handoff** — `skills/frontend-handoff/SKILL.md` (+ `templates/frontend/*`) gain a
  **"gotchas / подводные камни"** block: what the frontend must account for or the UI breaks (async
  states, empty/error states, visibility) — flagged proactively, not just documented as contract.

### B4 — rollout

`.claude-plugin/plugin.json` → `0.10.0`; `README.md` "What's inside" notes blind-spot surfacing +
the new agent in the Layout; `plugin-enhancement-roadmap.md` records Wave 6.

## Acceptance criteria (EARS — dogfooding E4)

Verification is structural (inspect the Markdown / frontmatter) + the agent loads (`/agents`); no
executable proof (no scripts).

- [ ] **W6-AC1** THE guideline `guidelines/blind-spot-protocol.md` SHALL exist and define (a) the
      advisory mandate (challenge the intent, not only the execution), (b) the blind-spot taxonomy,
      (c) the per-item output format (what's missed · why · consequence · recommendation · priority ·
      verified/assumed), AND (d) the anti-noise calibration. → check: guidelines/blind-spot-protocol.md
- [ ] **W6-AC2** WHEN `start-task` produces the first response for an L2+ task THE structure SHALL
      include a **blind spots** section distinct from **clarifications**, AND `ai-sdd-process.md`
      first-response structure + Definition of Ready SHALL list it.
      → check: skills/start-task/SKILL.md + guidelines/ai-sdd-process.md
- [ ] **W6-AC3** THE agent `agents/blind-spot-mapper.md` SHALL exist with valid frontmatter
      (name, description, tools, effort; `model` unset), SHALL receive the task statement + spec/plan
      without the author's reasoning, SHALL return a ranked blind-spot list per the taxonomy, AND SHALL
      delimit itself from impact-mapper / risk-review / adversarial-verifier / conformance-reviewer.
      → check: agents/blind-spot-mapper.md
- [ ] **W6-AC4** THE "Fan-out by level" table + startup sequence SHALL include `blind-spot-mapper` —
      optional at L2, required at L3/L4 (Discovery).
      → check: guidelines/ai-sdd-process.md + skills/start-task/SKILL.md
- [ ] **W6-AC5** EACH `templates/specs/*.md` SHALL contain a "Blind spots considered" section, AND
      `skills/spec/SKILL.md` SHALL instruct filling it (what may have been missed + closed or deferred).
      → check: templates/specs/*.md + skills/spec/SKILL.md
- [ ] **W6-AC6** WHEN implementation reveals a missed dimension with material consequences THE
      `implement-approved` skill SHALL instruct stopping and surfacing it (not silently working around).
      → check: skills/implement-approved/SKILL.md
- [ ] **W6-AC7** THE `risk-review` skill AND the `deep-review` workflow SHALL add an open
      "other consequences beyond the checklist" category plus a domain/product lens, AND SHALL state
      risk-review may run on the plan at entry, not only the diff.
      → check: skills/risk-review/SKILL.md + skills/deep-review/workflow.md
- [ ] **W6-AC8** THE `frontend-handoff` skill SHALL include a "gotchas / подводные камни" block for
      what the frontend must account for or the UI breaks.
      → check: skills/frontend-handoff/SKILL.md + templates/frontend/
- [ ] **W6-AC9** THE `final-check` converge step SHALL include a blind-spot re-pass for new blind spots
      the finished implementation created. → check: skills/final-check/SKILL.md
- [ ] **W6-AC10** THE anti-noise calibration (proportional-to-level · material-only · ranked · "none"
      allowed · no fabrication · no duplication of impact-mapper/clarify/risk-review) SHALL appear in
      BOTH the protocol AND the agent prompt.
      → check: guidelines/blind-spot-protocol.md + agents/blind-spot-mapper.md
- [ ] **W6-AC11** `.claude-plugin/plugin.json` SHALL be `0.10.0`; `README.md` SHALL note blind-spot
      surfacing + list the new agent; Wave 6 SHALL be recorded in the roadmap.
      → check: plugin.json + README.md + plugin-enhancement-roadmap.md

## Risks / assumptions

- **Ceremony creep / noise (the primary risk).** A mandatory "what you missed" block on every task can
  fatigue the user and erode trust. Mitigated by W6-AC10: proportional to level (L0/L1 may emit
  nothing), material/non-obvious only, ranked top ~5–7, "none" is honest, no duplication. If it still
  over-fires in practice, tighten the cap — do not remove the muscle.
- **Overlap/confusion with clarify / impact-mapper / risk-review.** Mitigated by the Boundaries table
  and the agent's explicit self-delimitation; each mechanism keeps its lane.
- **Token cost of `blind-spot-mapper`.** Gated to L3/L4 (optional L2), like `impact-mapper`; `effort:
  high` is justified by the expertise the job needs. No new platform dependency — it is one more
  subagent (4 already ship).
- **Over-report by a fresh-context agent.** Same mitigation as `conformance-reviewer` ("an
  over-reporting reviewer is a failed reviewer"), carried verbatim into the agent prompt.
- **Assumption** — the taxonomy is a starting set, not exhaustive; projects extend it via `AGENTS.md`.
  The open "other consequences" category (B3 risk-review) is the escape hatch for anything off-list.

## Rollout

- Version **v0.10.0**. Additive — no hook/script behavior change; changes how the agent *reasons and
  reports*, not what it enforces.
- Commit (single line, no AI attribution):
  `feat: v0.10.0 — proactive blind-spot surfacing (protocol + blind-spot-mapper + pipeline touchpoints)`.

## Verification plan

Inspect each touched file against W6-AC1–AC11; confirm `blind-spot-mapper` frontmatter is valid and the
plugin still lists it in `/agents`. Dogfood `conformance-reviewer` on the diff. Structural review only —
no executable proof (methodology + prose, no scripts).
