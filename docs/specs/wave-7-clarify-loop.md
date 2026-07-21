# Spec: Wave 7 — interview loop, live domain contract, skill hygiene (plugin v0.12.0)

- Type: plugin self-improvement — methodology + one new skill + one new guideline + a pruning pass
  (prose / templates / frontmatter; no hooks, no scripts). Cross-cutting UX change → treated as **L3**.
- Author: Max Yastremskyi (YasMax91).
- Source: an internal design for interview-driven discovery — an `AskUserQuestion` interview protocol,
  a living domain-language contract, and an author-facing skill-hygiene checklist. Extends the
  [enhancement roadmap](plugin-enhancement-roadmap.md) (Wave 7, after Wave 6 blind spots).
- Status: approved → implemented (2026-07-21); structural verification W7-AC1–AC11 all pass. Behavioral
  dogfood (a real L3 task opening an `AskUserQuestion` round) pending a real task — cannot be faked.
- Target version: v0.12.0

## Goal

Close the last gap in the front half of the pipeline: **the plugin never actually interviews the user.**
It maps couplings (`impact-mapper`), predicts omitted dimensions (`blind-spot-mapper`), and drafts a
plan — then asks its questions as one block of prose in the first response and proceeds. Decisions that
are the *user's* to make get assumed, not asked. Wave 7 turns that single prose block into a **bounded
interview loop** driven by `AskUserQuestion`, gives it a standalone entry point (`grill`), and stops the
project's domain contract from going stale the moment `init` finishes.

## Problem (diagnosis)

Confirmed by inspection of the current plugin (v0.11.0):

1. **`AskUserQuestion` is used nowhere.** Zero occurrences across `skills/`, `agents/`, `guidelines/`.
   Every question is free prose in the first response (`skills/start-task/SKILL.md:42-43`), and the only
   consent gate is the plan approval at `skills/start-task/SKILL.md:52`.
2. **Clarify is a one-shot, not a loop.** `skills/start-task/SKILL.md:58-60` says "resolve the blocking
   ones before producing the plan" but defines no rounds, no convergence criterion, and no place to
   record an answer. A dependent question — one whose sensible form depends on how a prior one was
   answered — cannot be asked at all.
3. **Level does not scale the interview.** L0–L4 scales *agent fan-out*
   (`guidelines/ai-sdd-process.md:40-56`) but not the depth of user consultation, so an L4 financial
   change gets exactly as much consultation as an L2 CRUD endpoint.
4. **Answers are not persisted.** `.claude/groundwork/task-state.md` (`guidelines/working-memory.md:22-43`)
   holds mode, level, slices, assumptions — but has no slot for *decisions the user made*, so after a
   compaction the agent can silently re-assume what was already settled.
5. **The domain contract is written once and never again.** `templates/project/AGENTS.md` (domain
   entities, invariants, permissions, integrations) is authored by `init`
   (`skills/init/SKILL.md:39-42`) and read by `start-task` (`skills/start-task/SKILL.md:11`); **no skill
   ever updates it.** A feature that adds an entity, an invariant, or a role leaves the contract stale
   until someone re-runs `init`.
6. **The plugin has no pruning discipline for itself.** 98 KB across 27 Markdown files, with the
   first-response structure and the startup sequence each written twice
   (`guidelines/ai-sdd-process.md:58-81` vs `skills/start-task/SKILL.md:9-52`).

## Boundaries — how the interview differs from what exists

The load-bearing decision, same as Wave 6: the new muscle must not become a fifth overlapping voice.

| Mechanism | Question it answers | Who resolves it |
|---|---|---|
| `impact-mapper` | "what will my change break?" (code couplings) | the agent, from code |
| `blind-spot-mapper` | "what dimension did you not think of?" | the agent, then → the interview if it needs a *decision* |
| `risk-review` | "is there a known engineering risk in what was done?" | the agent, from a checklist |
| `grounded-researcher` | "what does the external API actually support?" | the agent, from cited docs |
| **interview loop (new)** | **"which of these do you choose, and what did you mean?"** | **the user, and only the user** |

The rule that keeps the lanes clean: **facts are the agent's job, decisions are the user's.** Anything
findable in the filesystem, Boost, the CRD, or a subagent is never a question. Blind-spot output is the
interview's richest *feed* — a surfaced dimension that needs a product call becomes a frontier question
instead of a bullet the user has to reply to in prose.

## Design — per item

### C1 — `clarify-protocol` guideline + interview rounds in `start-task` (the core)

New `guidelines/clarify-protocol.md`, shaped like `blind-spot-protocol.md` (mandate · mechanics ·
calibration · anti-patterns · reference case). It defines:

- **The mandate** — *facts are yours, decisions are the user's.* Look up anything the environment can
  answer (Boost, grep, the impact map, the CRD, a subagent); put every genuine choice to the user. A
  decision silently assumed is the cheapest defect to prevent and the most expensive to discover.
- **The decision tree and the frontier.** Decisions branch: some questions only make sense once an
  earlier one is answered. The **frontier** is every decision whose prerequisites are already settled —
  exactly the questions askable *now* without guessing at an answer not yet heard. Ask the whole
  frontier in one round; a question that depends on another still open belongs to the next round.
- **Mechanics — `AskUserQuestion`, always.** Each round is one `AskUserQuestion` call, max 4 questions
  (the tool's limit), each with 2–4 concrete options. **Every question carries the agent's recommended
  option first, marked as the recommendation, with its consequence** — a question without a
  recommendation offloads the agent's job onto the user. Free-prose questions are not an interview.
- **Subagents never ask.** A subagent cannot prompt the user; when one surfaces a question, the main
  agent carries it into the next round itself.
- **Convergence — the stop criterion.** The loop ends when the frontier is empty: every blocking
  decision answered by the user, everything else explicitly recorded as an assumption. "No more
  questions" is a claim about the tree, not about patience.
- **Calibration — proportional to level (the anti-ceremony rule):**
  - **L0/L1** — no loop. At most one question, and only if a blocking ambiguity genuinely stops the
    work; otherwise proceed on a stated assumption.
  - **L2** — one round, blocking decisions only.
  - **L3/L4** — rounds until the frontier is empty, capped at **3 rounds**; anything unresolved at the
    cap is recorded as an explicit assumption in the spec, never silently assumed.
  - **Never re-ask what is already settled** — check the checkpoint's `## Decisions` first.
- **Persistence.** Every answer is written to `.claude/groundwork/task-state.md` under a new `## Decisions`
  section (`<decision> — <chosen option> — <date>`), so a compaction or restart cannot lose it.

Wiring:

- `skills/start-task/SKILL.md` — the clarify block in the first response is followed by an explicit
  **interview step** before the plan: run the rounds per the protocol, then write the decisions to the
  checkpoint. The existing stop-and-approve gate stays where it is.
- `guidelines/ai-sdd-process.md` — Discovery mode names the interview loop; the Definition of Ready
  gains "every blocking decision answered by the user (not assumed)".
- `guidelines/working-memory.md` + the checkpoint template — the `## Decisions` section.
- `guidelines/blind-spot-protocol.md` — the boundaries table gains the feed direction: a blind spot
  needing a product call becomes a frontier question rather than a prose bullet.

### C2 — `grill` skill (standalone stress-test)

New `skills/grill/SKILL.md`, **user-invoked** (`disable-model-invocation: true` — zero context load; it
only ever fires by hand). It runs the C1 protocol *outside* the task pipeline: no L-classification, no
`impact-mapper`, no spec. Use it on a plan, an architecture decision, a product idea, or a half-formed
intent — including work that never becomes code.

Differences from the in-pipeline loop, all deliberate: no round cap (the user chose to be grilled and
ends it by saying so), and it closes with a **decision summary** — what was settled, what stays
assumed, what to do next — plus an offer to hand off to `start-task` or `spec`. It references
`clarify-protocol.md` rather than restating it (single source of truth).

### C3 — living domain contract

- `templates/project/AGENTS.md` gains a **Domain language** section: the project's terms with the one
  word to use for each and the synonyms to avoid — so the agent, the CRD, and the code name the same
  thing the same way. Kept tight: project-specific terms only, never general programming vocabulary.
- **One writer, at one point.** `skills/final-check/SKILL.md` (converge step) gains a **domain-drift
  check**: when the finished change added, renamed, or removed a domain entity, an invariant, a
  role/permission, an external integration, or a domain term, update the matching section of the
  project's `AGENTS.md` **in the same change**. Everything else keeps reading it, so there is exactly
  one writer besides `init`.
- Calibration: update only on a real domain change — not on every task. A pure refactor, a bug fix with
  no vocabulary change, or an internal rename touches nothing.
- `guidelines/ai-sdd-process.md` Definition of Done gains "domain contract current — `AGENTS.md`
  reflects any entity / invariant / permission / integration / term the change introduced".
- `skills/init/SKILL.md` derives the new section during discovery like the others (`[from code ·
  confirm]`).

### C4 — skill hygiene pass

New `docs/skill-hygiene.md` — a **development-time checklist for plugin authors**, not a runtime
guideline (it never loads into a project's context): context load vs cognitive load, model- vs
user-invoked, progressive disclosure, single source of truth, and the failure modes to hunt —
duplication, sediment, sprawl, no-ops, and steering by prohibition instead of by the target behaviour.

Then apply it once, with a bounded target:

- **De-duplicate the two known copies** — the first-response structure and the startup sequence live in
  both `guidelines/ai-sdd-process.md:58-81` and `skills/start-task/SKILL.md:9-52`. Keep one authoritative
  copy (the skill owns the steps; the guideline points at it) so a change is a one-place edit.
- **Prune no-ops** in the five heaviest files (`ai-sdd-process`, `start-task`, `blind-spot-protocol`,
  `frontend-handoff`, `openapi-protocol`) — sentence by sentence, deleting what the model already does
  by default.
- Deliberately **out of scope**: rewriting protocols, renaming skills, or restructuring the plugin.
  Behaviour must not change — this pass removes text, it does not add rules.

### C5 — rollout

`.claude-plugin/plugin.json` → `0.12.0`; `README.md` "What's inside" documents the interview loop, the
`grill` skill, and the living domain contract, and the Layout lists the new files;
`plugin-enhancement-roadmap.md` records Wave 7.

## Acceptance criteria (EARS)

Verification is structural (inspect the Markdown / frontmatter) plus a live check that `grill` loads and
that a dogfooded L3 task actually opens an `AskUserQuestion` round.

- [x] **W7-AC1** THE guideline `guidelines/clarify-protocol.md` SHALL exist and define (a) the
      facts-vs-decisions mandate, (b) the decision tree / frontier round model, (c) the
      `AskUserQuestion` mechanics including max 4 questions per round and a recommended option per
      question, (d) the convergence criterion, AND (e) the per-level calibration.
      → check: guidelines/clarify-protocol.md
- [x] **W7-AC2** WHEN `start-task` reaches the point before the implementation plan THE skill SHALL run
      the interview rounds per the protocol, AND the first-response structure SHALL remain intact.
      → check: skills/start-task/SKILL.md
- [x] **W7-AC3** THE calibration SHALL bound the loop by level — L0/L1 at most one question, L2 one
      round, L3/L4 up to 3 rounds with anything unresolved recorded as an explicit assumption.
      → check: guidelines/clarify-protocol.md + skills/start-task/SKILL.md
- [x] **W7-AC4** THE protocol SHALL forbid asking the user anything the environment can answer, AND
      SHALL state that a subagent's question is carried into the next round by the main agent.
      → check: guidelines/clarify-protocol.md
- [x] **W7-AC5** THE checkpoint template in `guidelines/working-memory.md` SHALL include a `## Decisions`
      section, `start-task` SHALL write the answers into it, AND the protocol SHALL require checking it
      before asking so a settled decision is never re-asked.
      → check: guidelines/working-memory.md + skills/start-task/SKILL.md
- [x] **W7-AC6** THE skill `skills/grill/SKILL.md` SHALL exist with `disable-model-invocation: true`,
      SHALL reference the clarify protocol instead of restating it, SHALL run without an L-level or an
      impact map, AND SHALL close with a decision summary plus a handoff offer.
      → check: skills/grill/SKILL.md
- [x] **W7-AC7** THE boundaries table in `guidelines/blind-spot-protocol.md` SHALL state that a blind
      spot requiring a user decision feeds the interview frontier.
      → check: guidelines/blind-spot-protocol.md
- [x] **W7-AC8** THE template `templates/project/AGENTS.md` SHALL contain a **Domain language** section,
      AND `skills/init/SKILL.md` SHALL derive it during grounded discovery.
      → check: templates/project/AGENTS.md + skills/init/SKILL.md
- [x] **W7-AC9** WHEN a change adds, renames, or removes a domain entity / invariant / permission /
      integration / term THE `final-check` converge step SHALL update the project's `AGENTS.md` in the
      same change, AND the Definition of Done SHALL list the domain contract as current.
      → check: skills/final-check/SKILL.md + guidelines/ai-sdd-process.md
- [x] **W7-AC10** THE document `docs/skill-hygiene.md` SHALL exist as an author-facing checklist, AND
      the duplicated first-response structure and startup sequence SHALL survive in exactly one
      authoritative place.
      → check: docs/skill-hygiene.md + guidelines/ai-sdd-process.md + skills/start-task/SKILL.md
- [x] **W7-AC11** `.claude-plugin/plugin.json` SHALL be `0.12.0`; `README.md` SHALL document the
      interview loop, `grill`, and the living domain contract, and list the new files in the Layout;
      Wave 7 SHALL be recorded in the roadmap.
      → check: plugin.json + README.md + plugin-enhancement-roadmap.md

## Risks / assumptions

- **Interrogation fatigue (the primary risk).** An unbounded interview is worse than no interview —
  the user stops reading the options and clicks the recommendation. Mitigated by W7-AC3 (L0/L1 barely
  ask, L2 one round, L3/L4 capped at 3) and by the rule that every question carries a recommendation,
  so clicking through is a valid fast path rather than a failure.
- **Latency on the critical path.** Rounds add turns before the plan. Accepted deliberately for L3/L4,
  where an assumed decision is the expensive failure; explicitly avoided for L0–L2.
- **`AskUserQuestion` availability.** If the tool is unavailable in a given harness, the loop degrades
  to the current behaviour — the numbered question block in prose, answered in one reply. No hard
  dependency.
- **C4 changes a lot of text at once.** Mitigated by the bounded target (two known duplicates + no-op
  pruning in five files) and by the rule that behaviour must not change; verified by re-reading the
  affected skills end-to-end, not by diff size.
- **Domain-contract churn.** A per-task writer could bloat `AGENTS.md`. Mitigated by the single-writer
  rule (`final-check` only) and the real-domain-change trigger.
- **Assumption** — the frontier model is worth its complexity only where decisions genuinely depend on
  each other (L3/L4). At L2 it collapses to a single round, which is the intended behaviour, not a
  degradation.

## Rollout

- Version **v0.12.0**. Additive for C1–C3, subtractive for C4 — no hook or script behavior changes.
- Commit (single line, no AI attribution):
  `feat: v0.12.0 — interview loop (clarify protocol + grill), living domain contract, skill hygiene`.

## Verification plan

Inspect each touched file against W7-AC1–AC11. Confirm `grill` appears in the skill list and is
user-invoked only. Dogfood the loop on one real L3 task and confirm a round actually opens via
`AskUserQuestion` and its answers land in the checkpoint's `## Decisions`. Run `conformance-reviewer` on
the diff. Structural review only — methodology and prose, no scripts.
