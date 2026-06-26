# RaDevs Laravel-back plugin — enhancement roadmap

Status: **in progress** (2026-06-26) — Wave 1 (E4/E7/E6) shipped in v0.5.0; Wave 0 spike done; Wave 2
(E1) shipped in v0.6.0 (E2 dropped); Wave 3 (E3) shipped in v0.7.0. Wave 4 pending · Owner: RaDevs

A prioritized, grounded backlog of improvements to the `groundwork` plugin. The current
plugin (v0.4.0) already implements most of the 2025–2026 frontier — just-in-time context via
pointers (impact-cache, Boost), external memory (`task-state.md`), sub-agent context isolation,
orchestrator-worker discovery, adversarial verification, executable proof, requirements→design→tasks
gating. **These items are a delta on a strong base, not a rewrite.** Nothing here is implemented yet;
this document is the decision surface.

## How to read this

Each item carries: **persona** it serves · **what** · **why** · **platform capability used** ·
**source + confidence** (`verified` = primary source/runtime-confirmed; `assumed` = practitioner-
sourced or needs confirmation) · **effort** (S/M/L) · **risk** · **files touched** · **acceptance
criteria** (clause-IDs, EARS-style — dogfooding item E4).

Confidence labels follow the plugin's own grounding protocol. Anything `assumed` or platform-version-
dependent must pass **Wave 0 (verification spike)** before it is built — we do not encode a guess.

---

## Grounding note — verify before building (Wave 0)

Two facts from the research sweep need confirmation against *this user's installed Claude Code version*
before any platform-dependent item is built. The two research sub-agents disagreed on a couple of
these (one read only the public docs; the other had the tools live in its runtime). We resolve the
disagreement by testing, not by trusting either:

| Capability | Status from research | Must confirm |
|---|---|---|
| `PreToolUse` returns `permissionDecision: "deny"` / exit-2 to block a tool call by input pattern | `verified` (code.claude.com/docs/hooks) | exact JSON output schema + that a plugin-shipped hook can deny |
| `EnterPlanMode` / `ExitPlanMode` as a structured approval gate a skill can drive | runtime-present, but **not** in the public docs the guide agent fetched | whether a skill can reliably drive it in the user's CC version, and the exact UX |
| `Workflow` multi-agent tool available + opt-in gated | runtime-present; the guide agent reported "no built-in orchestration" from docs only | that it's available to the end user and that a plugin **skill** invoking it counts as opt-in |
| Subagent frontmatter: `model`, `effort`, `tools`, `permissionMode`, `memory`, `isolation` | `verified` (code.claude.com/docs/sub-agents) | which fields are honored in the user's version |
| Skill frontmatter: `model`, `effort`, `allowed-tools`, `context: fork`, bundled-script execution via `${CLAUDE_SKILL_DIR}` | mostly `verified`; `context: fork`/`effort` weaker | confirm the subset we depend on |

**Wave 0 deliverable:** a one-page capability-confirmation note (run `claude --debug` in a real
project, fire each hook/tool once, capture the actual schemas). This de-risks Tier 1 and costs ~1
short session. Everything in Wave 2/3 below is contingent on it.

---

## Scoring summary

| ID | Item | Persona | Value | Effort | Risk | Tier |
|---|---|---|---|---|---|---|
| E1 | PreToolUse hard-gates (Sail-only, migration-lock, Discovery-lock) | developer | High | M | **Med** | 1 |
| E2 | ~~Native Plan Mode gate~~ — **dropped** (Wave 0: undocumented); covered by E1.c + docs | architect | — | — | — | 1 |
| E3 | Workflow-driven deep skills (deep-discovery / deep-grounding / deep-review) | architect + doc-analyst | High | L | Med | 1 |
| E4 | EARS acceptance criteria + clause-ID → test traceability | developer + doc-analyst | High | M | Low | 2 |
| E5 | `clarify` pass (pre-plan) + `converge` re-check (post-impl) | designer | Med–High | M | Low | 2 |
| E6 | Conformance-reviewer agent (diff-vs-spec), distinct from adversarial-verifier | developer/architect | High | S–M | Low | 2 |
| E7 | Effort-scaling L0–L4 → fan-out + single-threaded-implementation rule | architect | Med–High | S | Low | 3 |
| E8 | Lightweight ADR + design-alternatives at L3/L4 gates | architect/designer | Med | S–M | Low | 3 |
| E9 | Subagent `model`/`effort` pinning + skill progressive-disclosure | (cost/quality) | Med | S | Low | 3 |

---

## Tier 1 — Hard enforcement + new engines

### E1 — PreToolUse hard-gates
- **Persona:** developer.
- **What:** a fail-safe `PreToolUse` hook that *blocks* (not just warns) the rules that are currently
  advisory in the guidelines:
  - (E1.a) direct `php` / `composer` / `artisan` / `phpunit` / `pest` on the host → must go through the
    configured runner (Sail). Mirrors the user's standing rule.
  - (E1.b) `Edit`/`Write` to an already-committed migration file (`database/migrations/*` present in
    `git ls-files`).
  - (E1.c) *optional, toggle-gated:* production-code `Edit`/`Write` while `task-state.md` mode is
    `Discovery` or `Plan`.
- **Why:** the most common failure is violating a rule we already documented. Moving E1.a/E1.b from
  prose to an engine-level deny removes a whole class of mistakes.
- **Capability:** `PreToolUse` → `permissionDecision: "deny"` (or exit 2). `verified` — hooks doc;
  confirm exact schema in Wave 0.
- **Files:** new `hooks/pre-tool-guard.sh`; edit `hooks/hooks.json` (PreToolUse matchers `Bash`,
  `Edit|Write`); edit `templates/project/.groundwork.json` (toggles `gates.enforce_runner`,
  `gates.lock_shipped_migrations`, `gates.lock_edits_in_discovery`); note in `laravel-standards.md` +
  `README.md`.
- **Risk (Med):** an over-broad blocklist could deny legitimate commands. Mitigation: copy the existing
  hooks' fail-open philosophy — match narrowly (only the bare `php`/`composer`/… verbs **not** already
  prefixed by the runner), allow obvious escapes, default the riskier toggle (E1.c) to **off**, and
  print the corrected command in the deny reason.
- **Acceptance criteria:**
  - `E1-AC1` WHEN a `Bash` call invokes `php artisan …` directly on the host AND a runner is configured,
    THE hook SHALL deny it and return the runner-prefixed form in the reason. (test: hook unit test)
  - `E1-AC2` WHEN an `Edit` targets a migration file tracked in git, THE hook SHALL deny it unless
    `gates.lock_shipped_migrations` is `false`. (test: hook unit test)
  - `E1-AC3` WHEN `.groundwork.json` is absent OR the relevant toggle is `false`, THE hook SHALL be a
    silent no-op (never break a non-RaDevs project). (test: hook unit test)
  - `E1-AC4` WHEN the runner is already present in the command (`./vendor/bin/sail …`), THE hook SHALL
    allow it. (test: hook unit test)
  - `E1-AC5` WHEN `./vendor/bin/sail` is absent or not executable (e.g. a fresh clone pre-`composer
    install`), THE hook SHALL NOT block host `composer`/`php` (bootstrap fail-open). (test: hook unit test)

### E2 — Native Plan Mode as the approval gate → **DROPPED / reframed (Wave 0)**

> **Wave 0 result:** skill-driven `EnterPlanMode`/`ExitPlanMode` is undocumented — not buildable from
> documented primitives. Reframed: the conversational `start-task`→`implement-approved` gate stays; the
> optional `gates.lock_edits_in_discovery` toggle (E1/Wave 2) is the deterministic hard gate; native
> plan mode (`defaultMode: "plan"`) is a documented user-level recommendation. See
> [wave-0-capability-confirmation.md](wave-0-capability-confirmation.md).

- **Persona:** architect.
- **What:** `start-task` ends its Discovery+Plan output by presenting the plan through `ExitPlanMode`
  (the structured approval checkpoint) instead of a prose "stop and wait". Discovery runs read-only.
- **Why:** turns the AI-SDD stop-point into a system-enforced gate — approval is captured, not assumed;
  read-only Discovery complements E1.c.
- **Capability:** `EnterPlanMode`/`ExitPlanMode`. Runtime-present; **confirm in Wave 0** that a skill
  can drive it in the user's version (the public docs were thin).
- **Files:** edit `skills/start-task/SKILL.md` (step 9 → present via plan mode); `guidelines/ai-sdd-process.md`
  (the stop point references plan mode); `README.md`.
- **Risk (Med):** depends on plan-mode availability/UX in the user's CC build. Fallback: keep the prose
  stop-point if Wave 0 shows the skill can't drive it reliably.
- **Acceptance criteria:**
  - `E2-AC1` WHEN `start-task` finishes the first response for an L2+ task, THE skill SHALL request
    approval via the plan-mode gate rather than only printing "waiting for approval".
  - `E2-AC2` WHILE in Discovery/Plan, no production file is edited (verified by E1.c when enabled).

### E3 — Workflow-driven deep skills
- **Persona:** architect + documentation analyst.
- **What:** new skills that drive the `Workflow` tool for deterministic multi-agent orchestration,
  replacing ad-hoc single-agent spawns for the expensive phases:
  - (E3.a) `deep-discovery` — parallel `impact-mapper` over multiple seeds + `grounded-researcher`,
    deduped and synthesized (orchestrator-worker). For L3/L4 only.
  - (E3.b) `deep-grounding` — fan out N readers across a large external-API doc, build the capability
    matrix, then an adversarial panel (≥2 skeptics) verifies each row. This is the direct answer to
    "thoughtful analysis of original documentation". Wraps the existing `ground-integration` skill.
  - (E3.c) `deep-review` — dimensions (API contract, RBAC, financial visibility, migrations, workflow
    state, N+1) → find → adversarially verify each finding (pipeline). Heavyweight `risk-review`.
- **Why:** the current single-agent fan-out is the orchestrator-worker pattern done by hand; a Workflow
  makes it deterministic, parallel, and loop-until-dry. Best leverage for breadth-first work.
- **Capability:** `Workflow` tool. Runtime-present; **confirm in Wave 0** it is available to the end
  user and that invoking the skill is a valid opt-in. Anthropic multi-agent research post for the
  pattern (`verified`).
- **Files:** new `skills/deep-discovery/SKILL.md`, `skills/deep-grounding/SKILL.md`,
  `skills/deep-review/SKILL.md` (each may bundle a workflow script template); `README.md`; cross-links
  from `start-task` / `ground-integration` / `risk-review` ("for L3/L4, escalate to the deep variant").
- **Risk (Med):** multi-agent uses ~15× the tokens of a single thread (Anthropic). Mitigation: gate
  strictly behind explicit skill invocation + L3/L4 only + reuse the impact-cache staleness check; the
  skills must `log()` what they fan out so cost is visible.
- **Acceptance criteria:**
  - `E3-AC1` WHEN `deep-grounding` runs against an external API, THE output SHALL be a capability matrix
    where every row carries a cited source AND an adversarial verdict (≥2 independent skeptics).
  - `E3-AC2` WHEN any deep skill runs, THE fan-out (number of agents, seeds) SHALL be logged to the user.
  - `E3-AC3` Deep skills SHALL only be entered by explicit invocation, never auto-triggered on L0–L2.

---

## Tier 2 — SDD methodology at 2026 level

### E4 — EARS acceptance criteria + clause-ID → test traceability
- **Persona:** developer + documentation analyst.
- **What:** spec acceptance criteria become EARS statements ("WHEN <event> THE SYSTEM SHALL <behavior>")
  with stable clause IDs (e.g. `AC3`), and each ID is linked to the red test that proves it. The TDD
  red-list references the IDs; the Definition of Done checks every ID has a green test.
- **Why:** turns free-form criteria into machine-checkable, traceable statements — the single biggest
  correctness payoff; tightens the existing TDD red→green and DoD.
- **Capability:** none (pure methodology). Sources: Kiro specs (EARS), Sean Grove "The New Code"
  (clause-IDs as tests). `verified`.
- **Files:** edit all `templates/specs/*.md` (criteria section → EARS + IDs + `→ test:` link);
  `skills/spec/SKILL.md`; `guidelines/tdd-protocol.md` (red-list cites IDs); `guidelines/ai-sdd-process.md`
  (DoD: every AC ID has a passing test).
- **Risk (Low).**
- **Acceptance criteria:**
  - `E4-AC1` WHEN a spec is written for L2+, EACH acceptance criterion SHALL be an EARS statement with a
    stable ID and a named test path.
  - `E4-AC2` THE Definition of Done SHALL fail if any acceptance-criterion ID lacks a green test.

### E5 — `clarify` pass + `converge` re-check
- **Persona:** designer (проектировщик).
- **What:** (E5.a) a short disambiguation pass between Spec and Plan that surfaces logical
  inconsistencies, conflicting constraints, and gaps before planning; (E5.b) a `converge` re-check
  after implementation that re-audits the codebase against the spec and appends any leftover work as
  tasks.
- **Why:** catches under-specification at the cheapest point (pre-plan) and prevents silent
  spec-drift at the end. From spec-kit's clarify/converge phases.
- **Capability:** none (methodology). Source: GitHub spec-kit. `verified`.
- **Files:** edit `skills/start-task/SKILL.md` (insert clarify before the plan); new
  `skills/converge/SKILL.md` *or* fold into `final-check`; `guidelines/ai-sdd-process.md` (modes).
- **Risk (Low).**
- **Acceptance criteria:**
  - `E5-AC1` WHEN requirements contain an ambiguity or conflict, THE clarify pass SHALL surface it as an
    explicit question before any plan is produced.
  - `E5-AC2` WHEN implementation completes, THE converge step SHALL list spec criteria not yet satisfied
    (or state "none") and append them as tasks.

### E6 — Conformance-reviewer agent (diff-vs-spec)
- **Persona:** developer/architect.
- **What:** a new subagent that, in a fresh context, judges the **diff against the spec/plan** and flags
  only gaps that affect correctness or stated requirements — explicitly *not* style. Distinct from the
  existing `adversarial-verifier`, which challenges "it works" claims.
- **Why:** the two review jobs are different (does it match the plan? vs. does the claim hold?). The
  fresh-context, gap-only reviewer is now a named best practice.
- **Capability:** subagent. Source: Claude Code best-practices (fresh-context reviewer; "report gaps,
  not style"; guard against over-reporting). `verified`.
- **Files:** new `agents/conformance-reviewer.md`; wire into `skills/final-check/SKILL.md` /
  `skills/risk-review/SKILL.md`; `guidelines/ai-sdd-process.md` (Review mode gains this gate).
- **Risk (Low):** a gap-seeking reviewer over-reports — mitigate with the explicit "correctness/
  requirement gaps only" instruction in the agent prompt.
- **Acceptance criteria:**
  - `E6-AC1` THE conformance-reviewer SHALL receive only the diff + the spec criteria, not the
    implementation reasoning.
  - `E6-AC2` THE conformance-reviewer SHALL report only gaps tied to correctness or a stated criterion,
    each with a `file:line` and the unmet criterion ID.

---

## Tier 3 — Tuning + architecture memory

### E7 — Effort-scaling L0–L4 → fan-out + single-threaded-implementation rule
- **Persona:** architect.
- **What:** an explicit table mapping task level to fan-out (L0/L1 = self-trace; L2 = 1 `impact-mapper`;
  L3/L4 = mapper + researcher + verifier / the deep skills), plus a rule that **implementation (TDD
  slices) stays single-threaded** — only discovery/verification fan out.
- **Why:** prevents over-spawning and wasted multi-agent token cost; coding is a poor multi-agent fit.
- **Capability:** none (rule). Source: Anthropic multi-agent post + Building effective agents.
  `verified`.
- **Files:** edit `guidelines/ai-sdd-process.md` (classification → fan-out table); `skills/start-task`,
  `skills/implement-approved`; note in the agent files.
- **Risk (Low).**
- **Acceptance criteria:**
  - `E7-AC1` THE process doc SHALL state, per level, how many subagents discovery may spawn.
  - `E7-AC2` THE implement-approved skill SHALL state that implementation slices run single-threaded.

### E8 — Lightweight ADR + design-alternatives at L3/L4 gates
- **Persona:** architect/designer.
- **What:** when an L3/L4 human-approval gate is hit (new dependency, new architectural layer,
  workflow-state logic), capture a 5-line ADR: 2–3 options with trade-offs + the chosen one + why.
- **Why:** forces alternative exploration before lock-in and leaves durable decision memory for future
  sessions.
- **Capability:** none (artifact). Source: design-alternatives `verified` (Building effective agents);
  **ADR-helps-AI is `assumed`** (practitioner-sourced, no Anthropic-primary endorsement found).
- **Files:** new `templates/adr.md`; fold capture into `skills/spec/SKILL.md` *or* a tiny ADR step;
  `guidelines/ai-sdd-process.md` (the existing approval-gate list gains "write the ADR").
  **Resolved:** hybrid — feature-local trade-offs stay in the spec's tradeoffs section; `docs/adr/` is
  reserved for cross-cutting, durable decisions only.
- **Risk (Low).**
- **Acceptance criteria:**
  - `E8-AC1` WHEN an L3/L4 approval gate is reached, THE workflow SHALL record ≥2 considered options and
    the chosen one with rationale.

### E9 — Subagent `model`/`effort` pinning + skill progressive-disclosure
- **Persona:** cost/quality.
- **What:** pin `grounded-researcher` and `adversarial-verifier` to a strong model / `high` effort, and
  allow `impact-mapper` a cheaper tier; move long reference material out of SKILL.md bodies into bundled
  level-3 files loaded on demand.
- **Why:** matches model strength to task and keeps each SKILL.md lean (progressive disclosure).
- **Capability:** subagent + skill frontmatter. `verified` (sub-agents/skills docs); confirm the exact
  fields in Wave 0.
- **Files:** edit `agents/*.md` frontmatter; refactor the longer skills to reference bundled files.
- **Risk (Low).**
- **Acceptance criteria:**
  - `E9-AC1` Verification/research agents SHALL declare an explicit model/effort appropriate to their job.
  - `E9-AC2` No single SKILL.md SHALL inline reference material that could be a loaded-on-demand file.

---

## Recommended sequencing

Order by de-risking + value, not by tier number:

- **Wave 0 — Verification spike (S).** ✅ **DONE 2026-06-26** — see
  [wave-0-capability-confirmation.md](wave-0-capability-confirmation.md). E1 = GO; E2 = dropped/reframed.
- **Wave 1 — Methodology hardening (low risk, immediate, no platform dependency): E4, E7, E6.**
  Sharpens every task starting now; pure docs/templates/one agent.
- **Wave 2 — Enforcement engine: E1** (E2 dropped). ✅ **shipped in v0.6.0 (2026-06-26)** →
  [wave-2-enforcement.md](wave-2-enforcement.md). Hook tests 15/15; conformance CONFORMS.
- **Wave 3 — Deep workflows: E3.** ✅ **shipped in v0.7.0 (2026-06-26)** →
  [wave-3-deep-skills.md](wave-3-deep-skills.md). AC1–AC6 CONFORMS; AC7 live smoke passed.
- **Wave 4 — Polish: E5, E8, E9.** Clarify/converge, ADR capture, pinning/progressive-disclosure.

Each wave is shippable on its own (commit + version bump + `/plugin reinstall` per the rollout
convention). Suggested: Wave 1 → `v0.5.0`, Wave 2 → `v0.6.0`, Wave 3 → `v0.7.0`, Wave 4 → `v0.8.0`.

---

## Decisions (resolved 2026-06-26)

1. **E1.c strictness** — **toggle OFF by default**; projects opt in. E1.a/E1.b ship **on**. Rationale:
   E1.c keys off mutable bookkeeping (the `mode` field in `task-state.md`), so a stale value would
   cause false blocks (friction); E1.a/E1.b key off immutable facts. E2 (Plan Mode) covers read-only-
   during-planning more reliably anyway.
2. **E1.a scope** — **deny** (not warn-only), with the corrected runner command in the deny reason and
   a narrow verb matcher. **Bootstrap fail-open:** the hook acts only when `./vendor/bin/sail` exists
   and is executable, so a fresh clone (where Sail isn't installed yet) can still run host `composer
   install`.
3. **E3 token budget** — **accepted.** ~15× token cost is acceptable *because* deep skills are gated to
   explicit invocation only + L3/L4 only; normal L0–L2 work is unaffected and uses the existing single-
   agent flow.
4. **E8 ADR location** — **hybrid.** Feature-local trade-offs stay in the spec's existing "technical
   approach and tradeoffs" section; a separate `docs/adr/` is reserved for **cross-cutting, durable**
   decisions (new dependency, new architectural layer, workflow-state model) that outlive a feature.
5. **Versioning cadence** — **one wave per minor bump** (Wave 1 → v0.5.0 … Wave 4 → v0.8.0). Each wave
   is independently useful and revertable. The Wave 2 release note must explicitly flag E1's new
   blocking behavior (a previously-running host command can now be denied; toggles let projects opt out).

## Out of scope (considered, rejected for now)

- Subagent cross-session `memory:` — speculative value for this workflow; revisit later.
- Repository/DDD/CQRS scaffolding — explicitly against the Laravel standards.
- Adding external MCPs beyond Boost — no clear need; revisit if a docs/issues MCP proves valuable.

## Source appendix (confidence)

- Anthropic — *Effective context engineering for AI agents* · *Building effective agents* · *How we
  built our multi-agent research system* · *Equipping agents with Agent Skills* · *Writing effective
  tools for AI agents* (`verified`).
- Claude Code docs — best-practices · hooks · skills · sub-agents · plugins-reference (`verified`).
- GitHub spec-kit (`verified`); Amazon Kiro feature specs / EARS (`verified`); Sean Grove "The New
  Code" (`verified` via transcript; primary is the recorded talk).
- ADR canonical (adr.github.io) + practitioner usage with AI assistants (`assumed` — no Anthropic-
  primary endorsement of ADR-for-AI was found).
