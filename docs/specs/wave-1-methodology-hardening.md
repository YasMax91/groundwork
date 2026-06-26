# Spec: Wave 1 — methodology hardening (plugin v0.5.0)

- Type: plugin self-improvement (docs / templates / one agent — no PHP, no platform dependency)
- Source: [plugin-enhancement-roadmap.md](plugin-enhancement-roadmap.md) items E4, E7, E6
- Status: approved → implemented (2026-06-26); conformance review CONFORMS (AC1–AC7 met)
- Target version: v0.5.0

## Goal

Sharpen the AI-SDD methodology so correctness and conformance are *checkable*, not just intended,
without touching any platform-dependent capability (no hooks/plan-mode/workflow). Three changes:
testable EARS acceptance criteria with test traceability (E4), explicit fan-out-by-level rules (E7),
and a distinct diff-vs-spec conformance reviewer (E6).

## Scope (Wave 1 / this spec)

E4, E7, E6 only. No PreToolUse hooks, no Plan Mode, no Workflow skills (those are Wave 2–3, gated by
the Wave 0 verification spike). Pure Markdown edits + one new agent file.

## Out of scope / future

E1/E2/E3 (Wave 2–3), E5/E8/E9 (Wave 4). The fan-out table (E7) *names* the deep skills as the L3/L4
escalation but does not build them.

---

## Design — file by file

### E4 — EARS acceptance criteria + clause-ID → test traceability

**The convention.** Every acceptance criterion becomes an EARS statement with a stable per-spec ID and
a `→ test:` pointer to the test that proves it. The red list and the Definition of Done are keyed by
those IDs.

EARS forms (the five patterns; combine for complex):
- Ubiquitous — `THE SYSTEM SHALL <response>`
- Event — `WHEN <trigger> THE SYSTEM SHALL <response>`
- State — `WHILE <state> THE SYSTEM SHALL <response>`
- Unwanted — `IF <condition> THEN THE SYSTEM SHALL <response>`
- Optional — `WHERE <feature> THE SYSTEM SHALL <response>`

ID rule: IDs are stable once assigned (`AC1`, `AC2`, …). On edit, **append** new IDs; never renumber
existing ones (a renumber breaks the test links and the checkpoint).

**`templates/specs/feature.md`** — replace the current free-form criteria + tests blocks:

> _Before_
> ```
> ## Acceptance criteria
> - [ ] ...
> ## Tests (write first — the red list)
> - feature (...):
> - unit (...):
> ```
> _After_
> ```
> ## Acceptance criteria (EARS — each maps to a red test)
> Stable IDs; append, never renumber. Each criterion → the test that proves it.
> - [ ] **AC1** WHEN an authenticated user with <permission> POSTs <valid payload> to <route>
>       THE SYSTEM SHALL persist <entity> and return 201 with <resource shape>.
>       → test: tests/Feature/<X>Test.php::test_creates_entity
> - [ ] **AC2** IF the payload fails <rule> THEN THE SYSTEM SHALL return 422 with the <field> error.
>       → test: tests/Feature/<X>Test.php::test_validation
> - [ ] **AC3** WHEN the caller lacks <permission> THE SYSTEM SHALL return 403.
>       → test: tests/Feature/<X>Test.php::test_authorization
>
> ## Tests (write first — the red list)
> Each test below names the AC ID(s) it proves; written fail-first before the code. Match the layer:
> - feature (contract / validation / authz / response shape) — covers: AC1, AC2, AC3
> - unit (services / calculations / state transitions) — covers: <AC ids>
> ```

**The other five templates** get the same treatment, proportional to type:
- `bugfix.md` — add one criterion tying the fixed behavior to the regression test:
  `**AC1** WHEN <repro condition> THE SYSTEM SHALL <correct behavior> (was: <wrong behavior>). → test: <regression test>`.
- `api-contract-change.md` — add an Acceptance-criteria block (valid request, invalid request → 422,
  response shape, authz), EARS + IDs + `→ test:`; the Tests section references the IDs.
- `migration.md` — add criteria for schema-dependent behavior only (casts, backfill, constraint
  enforcement), EARS + IDs + tests. Pure DDL with no observable behavior needs none — say so.
- `workflow-change.md` — add criteria for allowed transitions, blocked transitions (IF…THEN), and
  side effects; IDs + tests.
- `integration-change.md` — add criteria tied to the **Executable proof** row and the faked paths; the
  happy-path proof is `AC1`'s test.

**`skills/spec/SKILL.md`** — step 4 ("Write acceptance criteria") gains: write them in EARS with stable
IDs and a `→ test:` pointer; keep it proportional (trivial CRUD does not need ceremony — a plain
"returns 201 + shape" criterion is fine in EARS but don't invent branches). Add the five-form EARS
reference inline (compact).

**`guidelines/tdd-protocol.md`** — the "turn acceptance criteria into a red list" language gains: each
red-list test **names the AC ID(s)** it proves; the order proof (red→green) is reported per AC.

**`guidelines/ai-sdd-process.md`** — Definition of Done gains a line: *every acceptance-criterion ID has
a passing test written test-first (red→green); no AC ID is left unmapped*. Self-review checklist gains:
*each acceptance-criterion ID mapped to a passing test?*

### E7 — Fan-out by level (effort scaling) + single-threaded implementation

**`guidelines/ai-sdd-process.md`** — new subsection right after "Task classification":

> ```
> ## Fan-out by level (effort scaling)
>
> Match agent fan-out to task level. Over-spawning wastes ~15× tokens; coding is a poor multi-agent fit.
>
> - L0 Tiny — no subagents. Inline.
> - L1 Small — self-trace (a few targeted greps). No agent.
> - L2 Normal — 1 impact-mapper (cache-aware). Add grounded-researcher only if an external API is touched.
> - L3 High-risk — impact-mapper + grounded-researcher (if integration) for discovery;
>   conformance-reviewer + adversarial-verifier for verification. May escalate to the deep-* skills.
> - L4 Critical — as L3, plus an adversarial panel (≥2 skeptics) on the riskiest claims; deep-* encouraged.
>
> Single-threaded implementation: only Discovery and Verification fan out. Implementation (TDD slices)
> runs single-threaded — one slice at a time, no parallel coding agents.
> ```

**`skills/start-task/SKILL.md`** — step 4 cites the new table instead of restating thresholds.
**`skills/implement-approved/SKILL.md`** — add the single-threaded-implementation rule line.
**`agents/impact-mapper.md`, `grounded-researcher.md`, `adversarial-verifier.md`** — one line each:
"spawned by Discovery/Verification, not during implementation."

### E6 — Conformance-reviewer agent (diff-vs-spec)

**New `agents/conformance-reviewer.md`** — modeled on `adversarial-verifier.md`'s shape, but a different
job. Frontmatter: `name: conformance-reviewer`, read-only tools (`Read, Grep, Glob, Bash`), `effort: high`.
Behavior:
- Receives **only** the diff (`git diff`) + the spec's acceptance criteria — **not** the implementation
  reasoning (fresh context, so it judges the result, not the story).
- For each AC ID: verdict `met` / `partial` / `unmet`, with `file:line` evidence from the diff.
- Reports **only** gaps that affect correctness or a stated criterion — explicitly **not** style,
  naming, or preference (the over-reporting guard).
- Distinct from `adversarial-verifier`: that one challenges "it works" claims (truth of a claim); this
  one checks "does the diff satisfy the approved spec" (conformance/coverage).
- Output: per-AC verdict table → ranked gap list (each tied to an unmet AC ID) → or "no gaps".

**`skills/final-check/SKILL.md`** — add a step (L2+ only): before the handoff summary, spawn
`conformance-reviewer` on the working diff vs the spec's acceptance criteria; fold unmet-AC gaps into
the handoff (or fix them). Skip for L0/L1.
**`skills/risk-review/SKILL.md`** — note that conformance (diff-vs-spec) is the conformance-reviewer's
job; risk-review stays focused on the risk categories.
**`guidelines/ai-sdd-process.md`** — Review mode mentions the two distinct review gates
(adversarial-verifier = claim truth; conformance-reviewer = spec conformance).

---

## Acceptance criteria (EARS — dogfooding E4)

Verification here is **structural inspection** of the Markdown (this plugin has no PHP suite); the
"test" pointer is the file to inspect.

- [ ] **W1-AC1** THE SYSTEM SHALL render every acceptance criterion in all six `templates/specs/*.md`
      as an EARS statement with a stable ID and a `→ test:` pointer.
      → check: each file in `templates/specs/`
- [ ] **W1-AC2** THE Definition of Done in `guidelines/ai-sdd-process.md` SHALL require every
      acceptance-criterion ID to have a passing test, and the self-review checklist SHALL include the
      AC-to-test mapping check.
      → check: `guidelines/ai-sdd-process.md`
- [ ] **W1-AC3** THE `guidelines/ai-sdd-process.md` SHALL contain a "Fan-out by level" subsection
      stating, per L0–L4, the permitted discovery/verification fan-out, AND SHALL state that
      implementation slices run single-threaded.
      → check: `guidelines/ai-sdd-process.md`
- [ ] **W1-AC4** WHEN `final-check` runs for an L2+ task THE skill SHALL instruct spawning
      `conformance-reviewer` on the diff vs the spec criteria before the handoff.
      → check: `skills/final-check/SKILL.md`
- [ ] **W1-AC5** THE `conformance-reviewer` agent prompt SHALL state it receives only the diff + spec
      criteria (not the reasoning) AND reports only correctness/requirement gaps, each with `file:line`
      and the unmet AC ID.
      → check: `agents/conformance-reviewer.md`
- [ ] **W1-AC6** THE `skills/spec/SKILL.md` SHALL contain the five-form EARS reference and the
      stable-ID / append-never-renumber rule.
      → check: `skills/spec/SKILL.md`
- [ ] **W1-AC7** THE `guidelines/tdd-protocol.md` SHALL require each red-list test to name the AC ID(s)
      it proves.
      → check: `guidelines/tdd-protocol.md`

## Risks / assumptions

- **EARS ceremony creep** — over-formalizing trivial CRUD. Mitigation: the spec skill states criteria
  must stay proportional; EARS is a clarity tool, not a quota.
- **Conformance-reviewer over-reporting** — a gap-seeker flags style. Mitigation: the explicit
  "correctness/requirement gaps only" guard is in the agent prompt (W1-AC5).
- **Extra verification agent cost** — one fresh-context agent per L2+ finalization. Acceptable: returns
  a distilled verdict; skipped for L0/L1. Consistent with the E7 fan-out table.
- **Assumption** — no project currently depends on the exact wording of these templates/guidelines in a
  way a re-word would break. Mitigation: changes are additive to structure; IDs are new.

## Rollout

- Version: **v0.5.0** (one wave per minor bump). Additive methodology change — no blocking behavior
  (unlike Wave 2's E1), so the release note is straightforward.
- Per the rollout convention: commit + bump `.claude-plugin/plugin.json` version + the user runs
  `/plugin reinstall`. Update `README.md`'s "What's inside" to mention EARS criteria + conformance
  reviewer.
- Suggested commit (single line, no AI attribution): `feat: v0.5.0 — EARS testable criteria, fan-out-by-level, conformance-reviewer`.

## Verification plan

Since this is a docs/agents change, verification = inspect each touched file against W1-AC1..AC7, then
dogfood: run `conformance-reviewer` on this very diff against W1-AC1..AC7 as the first real use.
