# Spec: Wave 10 — process depth (plugin v0.15.0)

- Type: plugin self-improvement — methodology only (prose; **no hooks, no scripts, no new skills**).
  Changes when three existing mechanisms fire → **L3**.
- Author: Max Yastremskyi (YasMax91).
- Source: the session-mined complaint brief for the v0.12.0 window (2026-07-21 → 2026-07-27), items
  **B-2** (`grill` never offered), **B-3** (blast radius not re-mapped when the task grows), **B-6**
  (options never presented as a visible step) and the **A5** half not closed by Wave 8. Third package of
  the [feedback programme](plugin-enhancement-roadmap.md), after
  [Wave 8](wave-8-live-verification.md) and [Wave 9](wave-9-audience-and-language.md).
- Status: **draft — approved to implement** (the author authorised Waves 10–11 to run without a per-wave
  gate on 2026-07-27).
- Target version: v0.15.0

## Goal

Three mechanisms the plugin already owns fire at the wrong time, or never:

1. **`grill` exists and is never reached.** The plugin's best tool for a half-formed intent is invocable
   only by hand, and nothing in the workflow ever mentions it — so it fires only when the user already
   knows he needs it, which is exactly when he needs it least.
2. **The blast-radius map is built once and goes quietly irrelevant.** The misses were not at task
   start; they happened when a long session grew new sub-requests ("и ещё поправь X") whose files were
   never in the map. The staleness check cannot see this by construction.
3. **Options are offered inside questions, never as a position.** Recommendation-first is real and
   strong, but the user never sees "here are the two ways to build this, I recommend the first, because
   …" at plan altitude — so it reads as "never proposes his own solutions" even though every question
   carries a recommendation.

Wave 10 fixes *when* each fires. It adds no new skill and no new agent.

## Problem (diagnosis)

Confirmed against v0.14.0 — each claim grepped, not assumed:

1. **Nothing in the workflow points at `grill`.** Across the whole plugin, `grill` appears in
   `README.md:18` and `:161`, in `docs/skill-hygiene.md:16` (as the example of a user-invoked skill), and
   in the roadmap/spec history. **No skill and no guideline mentions it** — `start-task`, `spec`, and
   `clarify-protocol.md` never name it. `skills/grill/SKILL.md:3` is `disable-model-invocation: true`, so
   its description never enters the context either. The plugin's own hygiene doc predicted this exact
   failure: *"a user-invoked skill … costs zero context, but you become the index that must remember it
   exists"* (`docs/skill-hygiene.md:13-14`). The index was left as the human.
2. **The impact cache cannot detect a scope change — only a code change.** `guidelines/working-memory.md:79-80`
   gates reuse on two conditions, `git diff --quiet <BASE_COMMIT> -- <SEEDS>` and `git diff --quiet -- <SEEDS>`.
   Both interrogate the seeds **already mapped**. A new sub-request introduces *new* seeds, absent from the
   `SEEDS:` header (`:71`) — so both checks pass, the cache looks fresh, and the plan proceeds on a map
   that never covered the new work. There is **no rule anywhere** about a sub-request arriving mid-task: a
   grep for `sub-request` / `scope change` / `mid-task` across `skills/` and `guidelines/` returns nothing.
   `skills/implement-approved/SKILL.md:44-47` escalates a *blind spot* found mid-build, which is the
   nearest thing and a different event.
3. **`≥2 options` exists in exactly one place, and it is an artifact, not a conversation.**
   `skills/spec/SKILL.md:28` requires two considered options **in an ADR**, i.e. only for cross-cutting,
   durable L3/L4 decisions, written into `docs/adr/` after the fact. Nothing asks the agent to *show* its
   candidate approaches before the interview. `guidelines/clarify-protocol.md:41-43` mandates a
   recommendation per question — a choice **inside** a decision, not a proposal of how to solve the task.

## Boundaries — three different moments

The load-bearing distinction, so the new rules do not collide with what already works:

| Mechanism | Fires when | Altitude | Wave 10 |
|---|---|---|---|
| approaches block (C3) | before the interview | **how we solve this task** (2–3 candidate shapes) | **new step** |
| per-question recommendation (`clarify-protocol`) | inside the interview | one decision, 2–4 concrete outcomes | **unchanged** |
| ADR (`spec`) | at an L3/L4 durable gate | the decision that outlives the feature | **fed by** the approaches block |
| `grill` | intent too blurred for a plan | the thinking itself, no classification | **now offered** |
| `impact-mapper` cache | discovery, and now on scope growth | code couplings | **re-checked** |

Guardrails: `grill` is **offered, never auto-run** (it is an unbounded interview — starting one
unasked would be worse than not offering it); the approaches block **collapses honestly** when there is
only one sensible path; and the map re-check is **cheap by default** — comparing a seed list — with the
expensive re-map only when the comparison fails.

## Design — per item

### C1 — `grill` gets offered at the moment it is useful (B-2)

**`grill` stays user-invoked.** Making it model-invocable would put its description in every context
window forever to solve a problem that only needs a pointer at one moment. Instead, **`start-task`
becomes the index** — it is already loaded when discovery runs, so the pointer costs nothing outside it.

`skills/start-task/SKILL.md` gains a step, before the interview: when the intent is too unformed for a
plan, **offer `grill`** as one option in the interview round (with the recommendation stated, per the
clarify protocol) rather than silently planning on top of a guess. The signals, written to be checkable
rather than atmospheric — any of:

- the request names a **problem, not a change** ("orders get lost", "clients complain about payments");
- **two or more incompatible readings** survive the first discovery pass;
- it is an **architecture or product call**, not a code change (what should exist, not how to build it);
- **nobody can state what "done" looks like** — no acceptance shape can be written yet;
- the task is **L3/L4** and the goal, not just the mechanism, is still open.

Plus one signal the interview itself produces: `guidelines/clarify-protocol.md` — **hitting the L3/L4
round cap with the frontier still refilling means the thinking is not ready**, and the honest move there
is to offer `grill` rather than to record the remainder as assumptions. That is a new exit from the
convergence rule, not a new loop.

`skills/spec/SKILL.md` gains the same escape in one line: if the decisions are not settled enough to
write down, `grill` before the spec, not a spec full of assumptions.

### C2 — the map is re-checked when the task grows (B-3, and the rest of A5)

A **new sub-request inside an active task is a scope change**, and scope changes invalidate a blast-radius
map silently. The rule, level-independent for the *check* and level-scaled for the *response*:

- **On every new sub-request**, before implementing it: name its seeds (files, models, tables, symbols)
  and compare them with the `SEEDS:` header of the cached map.
- **Seeds already covered** → the map holds; proceed.
- **New seeds outside the map** → the map does not cover this work. **L0/L1:** a targeted self-trace over
  the new seeds. **L2+:** re-spawn `impact-mapper` over the **union** of old and new seeds, overwrite the
  cache, refresh `SEEDS:` and `BASE_COMMIT`.
- **Accumulation counts.** Three small sub-requests can jointly touch a class nobody mapped — which is why
  the check is level-independent. The comparison, not the level, decides.
- **Record it in the checkpoint** — the sub-request joined the scope, and the map was re-mapped or
  self-traced. A checkpoint that omits a scope change is exactly the overstatement problem.

`guidelines/working-memory.md` gains this as the **third staleness condition**, stated as the hole it
closes: the two `git diff` checks prove the mapped seeds did not change; they cannot prove the seeds are
*still the right ones*. Reuse requires all three.

Wiring: `skills/implement-approved/SKILL.md` (the skill that is running when sub-requests arrive — the
rule sits next to the existing mid-build blind-spot escalation), `guidelines/working-memory.md` (the third
condition), `skills/start-task/SKILL.md` (the cache-reuse step cites it), `guidelines/ai-sdd-process.md`
(Implementation mode: a sub-request re-enters discovery for its own blast radius before it is built).

### C3 — a visible approaches block before the questions (B-6)

`skills/start-task/SKILL.md`: the first response gains an **approaches** section, placed **before**
clarifications and the interview — the agent's 2–3 candidate ways to solve the task, the recommended one
first with the reason, and what each costs or forecloses. Written at plan altitude, in plain language
(Wave 9's layered rule), so the user is choosing between *shapes of a solution*, not ratifying a
pre-made one.

Calibration, so this does not become ceremony:

- **Only when a genuine fork exists.** When one path is plainly right, say exactly that in one line —
  "one sensible approach, here it is, because X" — and move on. A fabricated alternative is noise.
- **L0/L1:** skip. **L2:** one line per approach. **L3/L4:** the block, and it **feeds the ADR** when the
  decision is cross-cutting and durable (`spec` already requires ≥2 options there — now they are the same
  two, considered before the plan rather than reconstructed after it).
- It does not replace per-question recommendations; `guidelines/clarify-protocol.md` gains one line
  distinguishing the two altitudes so neither absorbs the other.

### C4 — rollout

`.claude-plugin/plugin.json` → `0.15.0`; `README.md` documents the approaches block, the scope-growth
re-map, and the `grill` offer; the roadmap marks Wave 10 shipped.

## Acceptance criteria (EARS)

Structural verification (inspect the Markdown), plus the behavioral checks named in the verification plan.

- [ ] **W10-AC1** WHEN the intent is too unformed for a plan — the request names a problem rather than a
      change, incompatible readings survive discovery, it is an architecture/product call, no acceptance
      shape can be stated, or L3/L4 with an open goal — THE `start-task` skill SHALL offer `grill` as an
      option in the interview round, AND SHALL NOT start it unasked.
      → check: skills/start-task/SKILL.md
- [ ] **W10-AC2** WHEN the L3/L4 interview reaches its round cap with the frontier still refilling, THE
      clarify protocol SHALL name offering `grill` as the honest exit rather than recording the remainder
      as assumptions. → check: guidelines/clarify-protocol.md
- [ ] **W10-AC3** THE `spec` skill SHALL state that decisions too unsettled to write down go to `grill`
      before a spec is written. → check: skills/spec/SKILL.md
- [ ] **W10-AC4** `grill` SHALL remain user-invoked (`disable-model-invocation: true`) — offered by a
      pointer, never promoted to model-invocable. → check: skills/grill/SKILL.md
- [ ] **W10-AC5** WHEN a new sub-request arrives inside an active task, THE workflow SHALL name its seeds
      and compare them against the cached map's `SEEDS:` header before implementing it; WHEN the new seeds
      fall outside the map, THE response SHALL be a targeted self-trace at L0/L1 or a re-spawned
      `impact-mapper` over the union of seeds at L2+, with the cache and its header overwritten.
      → check: skills/implement-approved/SKILL.md + guidelines/working-memory.md
- [ ] **W10-AC6** THE cache-reuse rule in `guidelines/working-memory.md` SHALL require a **third**
      condition beyond the two `git diff` checks — that the cached `SEEDS` still cover the seeds of the
      work at hand — stated as the hole it closes. → check: guidelines/working-memory.md
- [ ] **W10-AC7** THE scope-growth check SHALL be level-independent (accumulated small sub-requests
      count), AND the sub-request joining the scope SHALL be recorded in the checkpoint.
      → check: skills/implement-approved/SKILL.md + guidelines/ai-sdd-process.md
- [ ] **W10-AC8** THE first response in `start-task` SHALL include an **approaches** block before
      clarifications and the interview — 2–3 candidate approaches, the recommended one first with its
      reason and what it forecloses — AND SHALL state that a single sensible path is reported as such in
      one line rather than padded with invented alternatives.
      → check: skills/start-task/SKILL.md
- [ ] **W10-AC9** THE approaches block SHALL be distinguished from per-question recommendations by
      altitude in `guidelines/clarify-protocol.md`, AND SHALL feed the ADR's ≥2 options at L3/L4 instead
      of duplicating them. → check: guidelines/clarify-protocol.md + skills/start-task/SKILL.md
- [ ] **W10-AC10** `.claude-plugin/plugin.json` SHALL be `0.15.0`; `README.md` SHALL document all three
      changes; AND the roadmap SHALL record Wave 10 as shipped.
      → check: .claude-plugin/plugin.json + README.md + plugin-enhancement-roadmap.md

## Risks / assumptions

- **`grill` offered too eagerly (primary risk).** An offer on every vague-sounding request becomes a
  toll booth. Mitigated by checkable signals (not "feels unclear"), by it being one *option* in a round
  the user was getting anyway, and by never auto-starting it.
- **Re-map cost.** `impact-mapper` is the most expensive fan-out in the plugin; re-running it per
  sub-request could dominate a long session. Mitigated by the cheap-check-first design — a seed-list
  comparison costs nothing, and only a genuine miss triggers the fan-out, over the union so the result
  replaces rather than duplicates the old map.
- **Approaches block as ceremony.** Three invented options for a one-line fix is exactly the noise the
  blind-spot protocol warns about. Mitigated by the explicit single-path escape and the L0/L1 skip.
- **Sub-request detection is a judgement call.** Distinguishing "a new sub-request" from "a clarification
  of the current slice" has no mechanical test. Accepted: the check is cheap enough that treating a
  borderline case as a scope change costs a seed comparison, while missing one costs a defect — so the
  rule errs toward checking.
- **Assumption.** The `SEEDS:` header is maintained accurately by whoever last wrote the cache. If it is
  stale or vague, the comparison degrades — the existing "when in doubt about coverage, refresh rather
  than trust a stale map" rule (`guidelines/working-memory.md:85`) remains the backstop.

## Rollout

- Version **v0.15.0**. Additive prose only: **no hooks, no scripts, no new skills or agents**, no change
  to the approval gate, to test-first, to the Wave 8 live-verification path, or to Wave 9's audience rules.
- Commit (single line, no AI attribution):
  `feat: v0.15.0 — approaches-before-questions, blast-radius re-map on scope growth, grill offered when intent is unformed`.

## Verification plan

Inspect each touched file against W10-AC1–AC10. Confirm `grill`'s frontmatter is unchanged. Behavioral
checks that cannot be faked structurally, to be observed on real tasks: a first response that shows an
approaches block, and a mid-session sub-request that triggers a seed comparison. Run
`conformance-reviewer` on the diff. Methodology and prose, no scripts.
