# Groundwork plugin — enhancement roadmap

Status: original roadmap **complete** (2026-07-21) — Wave 1 (E4/E7/E6) v0.5.0 · Wave 0 spike · Wave 2 (E1) v0.6.0
(E2 dropped) · Wave 3 (E3) v0.7.0 · Wave 4 (E5/E8/E9) v0.8.0 · Wave 5 (status/UI, post-roadmap UX
request) v0.9.0 · Wave 6 (blind-spot surfacing, post-roadmap UX request) v0.10.0 · Wave 6.5 (OpenAPI
contract gate, post-roadmap) v0.11.0 · Wave 7 (interview loop + living domain contract + skill
hygiene, post-roadmap) v0.12.0. **Feedback programme (Waves 8–12) complete** — Wave 8 v0.13.0 ·
Wave 9 v0.14.0 · Wave 10 v0.15.0 · Wave 11 v0.16.0 · Wave 12 v0.17.0 (calibration), all conformance-verified.
**Wave 13** (author feedback, 2026-08-10) — v0.22.0 estimates in the agent's real build time + writing
standards · v0.23.0 interview depth; structurally verified. **Wave 14** (author feedback, 2026-08-11) —
v0.24.0 the denominator rule + the warn-only coverage-claim gate + the closing cost of silence; hook
behaviour proven by tests, prose structural. The research sweep behind the remaining backlog is
[modernization-research-2026-08.md](modernization-research-2026-08.md).
Author: Max Yastremskyi (YasMax91)

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
    silent no-op (never break a non-Groundwork project). (test: hook unit test)
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
  user and that invoking the skill is a valid opt-in. The tool provides the deterministic
  orchestrator-worker pattern (`verified`).
- **Files:** new `skills/deep-discovery/SKILL.md`, `skills/deep-grounding/SKILL.md`,
  `skills/deep-review/SKILL.md` (each may bundle a workflow script template); `README.md`; cross-links
  from `start-task` / `ground-integration` / `risk-review` ("for L3/L4, escalate to the deep variant").
- **Risk (Med):** multi-agent uses ~15× the tokens of a single thread. Mitigation: gate
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
- **Capability:** none (pure methodology). Uses EARS requirements syntax with clause-IDs linked to
  tests. `verified`.
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
  spec-drift at the end — a clarify pass before the plan and a converge pass at the end.
- **Capability:** none (methodology). `verified`.
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
- **Capability:** none (rule). `verified`.
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
- **Capability:** none (artifact). Design-alternatives capture `verified`; **ADR-helps-AI is `assumed`**
  (practitioner-sourced, no primary endorsement found).
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
- **Wave 4 — Polish: E5, E8, E9.** ✅ **shipped in v0.8.0 (2026-06-26)** →
  [wave-4-polish.md](wave-4-polish.md). Conformance CONFORMS. **Original roadmap complete.**
- **Wave 5 — Status / UI (post-roadmap, user UX request).** ✅ **shipped in v0.9.0 (2026-06-26)** →
  [wave-5-status-ui.md](wave-5-status-ui.md). Status line + in-action messages + session banner;
  conformance CONFORMS, fail-safe.
- **Wave 6 — Blind-spot surfacing (post-roadmap, user UX request).** ✅ **shipped in v0.10.0
  (2026-07-13)** → [wave-6-blind-spot-surfacing.md](wave-6-blind-spot-surfacing.md). Proactive
  blind-spot protocol + `blind-spot-mapper` agent (fresh context) + pipeline touchpoints across spec /
  implementation / review / frontend handoff; conformance CONFORMS (W6-AC1–AC11), calibrated against noise.
- **Wave 6.5 — OpenAPI contract gate (post-roadmap).** ✅ **shipped in v0.11.0** — `openapi-protocol`
  + blocking `openapi` Stop gate + `openapi-audit` skill: an endpoint change that ships without its
  annotations is not "done".
- **Wave 7 — Interview loop + living domain contract + skill hygiene (post-roadmap, user UX request).**
  ✅ **shipped in v0.12.0 (2026-07-21)** → [wave-7-clarify-loop.md](wave-7-clarify-loop.md). `clarify-protocol`
  + `AskUserQuestion` interview rounds in `start-task` (facts are the agent's, decisions are the user's) +
  the `grill` skill + a living domain contract kept current by `final-check` + an author-facing skill-hygiene
  pass.

Each wave is shippable on its own (commit + version bump + `/plugin reinstall` per the rollout
convention). Suggested: Wave 1 → `v0.5.0`, Wave 2 → `v0.6.0`, Wave 3 → `v0.7.0`, Wave 4 → `v0.8.0`.

---

## Feedback programme (Waves 8–11) — mined from the v0.12.0 usage window

Source: every session in the v0.12.0 window (2026-07-21 → 2026-07-27; 36 sessions across 4 projects),
read end-to-end and ranked by frequency. Caveat recorded at the time: `AskUserQuestion` answers are not
retained in session history, so the collected volume is a **lower bound** on the real friction. All
friction concentrated in long multi-task sessions (450–1350 messages); short single-task sessions and
`init` runs produced none.

Sequenced by pain, not by tier. Four packages:

- **Wave 8 — live-verification discipline.** ✅ **shipped in v0.13.0** →
  [wave-8-live-verification.md](wave-8-live-verification.md). The dominant complaint (~16 cases): "said
  done/verified, but it doesn't work live". Green gates stay necessary and stop being sufficient — a real
  HTTP run for endpoints, a real browser drive for admin/UI/CSS (asset loads · effective computed style ·
  persisted state), consumer coverage keyed to the impact map, end-to-end reachability of any declared
  contract value, class-audit instead of point-patch on a user bug report, a runnable Postman/curl package
  in the frontend handoff, and executable proof + surfaced citations broadened beyond external APIs.
- **Wave 9 — audience & language.** ✅ **shipped in v0.14.0** →
  [wave-9-audience-and-language.md](wave-9-audience-and-language.md). Plain-language-first defined once in
  `clarify-protocol` and bound to the discovery report, every interview question/option, and the
  blind-spot block (a layer — the identifier follows the meaning, nothing technical is deleted); the new
  `client-doc` skill + template as its own artifact (explicitly excluding tests / AC / EARS / endpoints /
  schema / architecture — those mean the answer is `spec`), with client-text style rules (prose over
  bullets, no em dash in SMS-bound text: `—` breaks GSM-7 and doubles cost); estimates fixed at **real
  AI-hours to write the functionality** — ranges per block + total + the reviewer's time on its own line,
  never man-days; and client/BA texts shipping as an English canonical file plus a Russian mirror
  regenerated from it, unasked (settled 2026-07-27 as plugin core, English is what the client receives).
- **Wave 10 — process depth.** ✅ **shipped in v0.15.0** →
  [wave-10-process-depth.md](wave-10-process-depth.md). Three mechanisms the plugin already owned, fixed
  at *when* they fire. `grill` stays user-invoked (zero context) but `start-task` becomes its index —
  offered, never auto-started, on checkable signals (a problem rather than a change, incompatible
  readings, an architecture call, no statable "done", L3/L4 with an open goal), plus a new exit from the
  interview: hitting the L3/L4 round cap while the frontier still refills means the *intent* is
  unsettled. The impact cache gains a **third** staleness condition — the cached `SEEDS` must still cover
  the seeds at hand — closing the hole where two `git diff` checks prove the mapped seeds did not change
  but never that they are still the right ones; a mid-session sub-request is a scope change that
  re-maps over the union of seeds (self-trace at L0/L1), level-independently, and lands in the checkpoint.
  And a visible **approaches** block precedes the interview — 2–3 candidate shapes, recommended first,
  with the single-sensible-path escape so it cannot become ceremony, feeding the ADR at L3/L4.
- **Wave 11 — plugin infrastructure & bugs.** ✅ **shipped in v0.16.0** →
  [wave-11-infrastructure.md](wave-11-infrastructure.md). The only wave with executable code, written
  test-first: a shared `hooks/lib.sh` (runner-aware command building, canonical `Mode:` parsing) sourced
  fail-safe by every hook, so `runner: host` is honored across all four gates — which also fixes the
  OpenAPI generation step silently no-opping, same root — and `pre-tool-guard` no longer denies host
  commands in a project that declared them. The `Mode:` value is now validated against
  {Discovery, Spec, Plan, Implementation, Review} after stripping Markdown, so `**COMMITTED**` yields no
  mode (the edit-lock fails open, the UI shows a placeholder) while `**Discovery**` is recognised. The
  test gate takes an atomic `mkdir` lock on the shared test database — waiting, then skipping **with a
  stated reason** rather than inventing a red — with stale-lock takeover and `gates.test_db_lock` /
  `test_lock_wait_seconds`; per-session git worktrees stay a documented practice, since a plugin cannot
  police them. The checkpoint guideline gained an accuracy rule (it is re-injected verbatim, so an
  overstatement becomes the next session's premise). **Found by the new tests, not in the brief:**
  `test-gate` and `done-gate` used `git status --porcelain` without `-uall`, so PHP inside a brand-new
  directory (`?? app/Services/`) skipped both gates silently — `openapi-gate` had already fixed this for
  itself. **Not reproduced:** the statusline pinned to 0.9.0 — no version string exists in `hooks/`;
  treated as already fixed. **Two blocking defects were introduced by this wave and caught by the
  adversarial review before release**, both now regression-tested: honoring `runner: host` created a path
  where an unreachable command produced a *false red* that would strand every Stop (the gates' own
  contract forbids blocking on an environment problem — `openapi-gate`'s allow-list was ported to the
  other two), and the project template pinned every `commands.*` to Sail, which — once an explicit
  override correctly beat the runner — made `runner: host` inert for any project created from it. 102 hook
  tests across 7 suites, one entry point (`hooks/tests/all.sh`).

- **Wave 12 — calibration & conflict resolution.** ✅ **shipped in v0.17.0** →
  [wave-12-calibration.md](wave-12-calibration.md). Run **before the author started using v0.16.0**, on the
  strength of an adversarial audit of the *combined* rule set, which returned REFUTED with 16 findings (4
  high) — every one re-verified against the source before being accepted. The root cause was an
  asymmetry: every rule that predated Wave 8 scaled across L0–L4, and **every rule Waves 8–11 added was
  written without a level**, so changing one error message came to demand ~32 obligatory actions. Wave 12
  adds no capability — it calibrates (per-level Definition of Done; L0 gets the automatic gates only, L1
  gets gates + regression test + a live exercise of the one thing fixed) and removes the contradictions:
  class-audit now *enumerates and reports* the sibling class instead of colliding with "keep scope tight"
  and the approval gate; the checkpoint may no longer be deleted while it is still the OpenAPI gate's
  escape hatch; `frontend-handoff` gained a stated degraded mode for when the live run legitimately did not
  happen; `spec` offers `/grill` instead of ordering an impossible invocation; review-agent calibration
  lives in one table; a blind spot the interview cannot admit becomes a recorded assumption rather than
  being dropped; sub-request re-mapping re-spawns the expensive agent only for model/table/service seeds;
  and the documented `test_lock_wait_seconds` default was corrected to match the code. Two hook additions,
  both test-first: repeat Stop-gate runs are skipped while the changed PHP is byte-identical to the last
  green one (`gates.reuse_green_run`), and a comment-only edit no longer trips the OpenAPI gate. 109 hook
  tests.

- **Wave 13 — real build time, no slop, and an interview that actually happens.** ✅ **shipped in
  v0.22.0 + v0.23.0** → [wave-13-estimates-and-interview-depth.md](wave-13-estimates-and-interview-depth.md).
  Author feedback, not an audit, and both findings have the same shape: a rule that was correct on paper
  and never changed the output. The estimate rule said "never man-days" while supplying human
  coefficients (1–2.5 h internal, 3–5 h with an integration) — so the unit changed and the number did
  not; it now measures the agent's own wall-clock time, calibrated against commit intervals inside a
  session, with everything a person must do (provider accounts, keys, access, decisions, review) on its
  own line and never added in. The clarify rule required an interview and then capped L2 — where most
  tasks land — at one round of blocking questions, offering the unbounded interview only in
  pathological cases; L2 now runs up to two rounds covering product forks, L3/L4 up to four, money /
  permissions / client-visible behaviour / external integrations each carry a mandatory round, and the
  unbounded interview is a standing choice in the first round rather than an exception. Whatever the
  agent still decided alone is shown before the plan as the **cost of silence**. Two supporting
  changes: `guidelines/writing-standards.md` (new) governs documents, estimates and reports, and the
  SessionStart context states that a task described in chat enters through `start-task` with no command
  — the author writes tasks as prose, so the protocol could not depend on him invoking a skill.

- **Wave 14 — a verification claim carries its denominator, and a silent decision does not stay silent.**
  ✅ **shipped in v0.24.0 (2026-08-11)** →
  [wave-14-coverage-and-silent-decisions.md](wave-14-coverage-and-silent-decisions.md). Author feedback
  again, and again a rule that was correct and toothless: the Definition of Done required "state what
  stayed unverified" at every level, which *"I checked it selectively"* satisfies literally while hiding
  whether that was eight of nine or one of nine — the **set** the claim is measured against was never
  required. A verification claim now takes one of three forms (total · fraction plus the enumerated gap ·
  "no verification was performed"), the denominator comes from an enumerable set named in the same
  sentence, and a fraction is never estimated. A fifth Stop hook reads `last_assistant_message` for
  bilingual hedges and **warns without blocking**, logging every trigger so the false-positive rate is
  measured before any later wave makes it block — the spike that preceded the design found that
  `additionalContext` re-enters the model (a soft block, not a warning), so warn-only is `systemMessage`.
  The same spike found the model refusing to invent a fraction where nothing had been verified, which is
  why the third form is named explicitly. On the other side, the cost-of-silence list gained its closing
  half in `final-check` — every decision taken without asking since plan approval, thresholded to items
  that move observable behaviour, money, permissions, or a contract — and the blind-spot taxonomy gained
  category 8, unconfirmed assumptions about the reader's own domain. Both new obligations carry level
  calibration from the first line, per Wave 12's lesson. 26 new hook tests, 163 across 9 suites.
  Research and the rejected alternatives: [modernization-research-2026-08.md](modernization-research-2026-08.md).

Deliberately **not** touched by this programme (verified working across the window — do not regress):
the plan-approval gate (never violated), test-first red→green, grounding by live probe (it caught a
non-existent `/payment/links` endpoint by probing before any code), and the agent's own self-catch of
unsound hypotheses before they reached implementation.

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
- ~~Adding external MCPs beyond Boost~~ — **reopened and shipped in v0.19.0** as the
  `groundwork-pack` companion bundle. What changed: the rejection assumed an MCP would be added
  for its own sake. The bundle inverts the test — a plugin enters only when a *named step* reaches for
  it (`start-task` → `LSP`/Sentry, `grounding-protocol` → Context7, `final-check` → a browser), every
  such step is conditional on the tool being present and must report when it did not run, and no gate
  depends on any of them. The second condition is cost: only MCP/LSP plugins qualify, because
  [tool search](https://code.claude.com/docs/en/mcp) defers MCP schemas while a plugin's skills sit in
  context on every turn. Three were considered and left out — `github` (no step needs it; `gh` covers
  PR work from `Bash`), `semgrep` (its plugin hooks scan on every file write and expect a cloud login;
  `risk-review` calls the CLI on the diff instead), `42crunch` (five model-invoked skills plus a paid
  account; `openapi-protocol` step 4 walks the same OWASP-API questions by hand).

## Source appendix (confidence)

- Claude Code official docs — best-practices · hooks · skills · sub-agents · plugins-reference
  (`verified`; the platform this plugin extends).
- Industry SDD standards — EARS requirements syntax, ADR decision records (`verified` as standards;
  ADR-for-AI usage `assumed`).
