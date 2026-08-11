# Groundwork — modernization research (2026-08-11)

Status: **research complete, nothing decided.** This document is a decision surface, not a plan.
Author: research pass requested by Max Yastremskyi (YasMax91) after v0.23.0.

Scope of the sweep: Claude Code platform capabilities the plugin does not use, SDD/agentic
methodology as it stands in 2026, companion plugins and MCP servers, and the Laravel/PHP toolchain.
Every item below is a delta on v0.23.0 — the plugin already owns grounded discovery, EARS + clause-ID
traceability, adversarial verification, blast-radius mapping, the interview loop, four Stop gates, and
a companion-plugin bundle.

## How this was verified

The plugin's own grounding protocol applies to its own roadmap. Three confidence levels are used:

| Label | Meaning |
|---|---|
| `runtime-verified` | Confirmed by executing something on this machine, output recorded below |
| `doc-verified` | Stated in official documentation fetched during this sweep, not executed |
| `assumed` | Practitioner-sourced or inferred; **must pass a spike before it is built** |

Runtime facts established on 2026-08-11:

| Fact | How it was established |
|---|---|
| Claude Code **2.1.212** (Homebrew, `/opt/homebrew/bin/claude`) | `claude --version` |
| Manifest fields `workflows`, `userConfig`, `experimental.monitors` are recognized by this build | `claude plugin validate --strict` on a probe plugin declaring all three plus a deliberate junk field; only the junk field was reported unknown |
| `groundwork` marketplace manifest passes `--strict` today | `claude plugin validate . --strict` → passed |
| `workflowSizeGuideline` in settings needs 2.1.219 → **not available here** | Version comparison against the workflows doc |
| Forked skills (`context: fork`) always block the turn on this build (background forking lands in 2.1.218) | Version comparison against the skills doc |
| A real onboarded project (`next-lvl-backend`) runs **PHPUnit 11, no static-analysis tool**, and its `.groundwork.json` sets `commands.analyse` to an `echo` no-op with `analyse_on_stop: false` | Read `composer.json` and `.groundwork.json` |

That last row matters more than any new feature below: on that project the done-gate's static-analysis
leg is inert by configuration, so E11 is scored above every platform item.

---

## Scoring summary

Estimates are the **agent's own wall-clock build time**, not man-hours. Human steps are listed
separately per item and never added into the agent figure.

| ID | Item | Category | Value | Agent time | Risk | Tier |
|---|---|---|---|---|---|---|
| E25 | A verification claim carries its denominator — no "spot-checked", no "briefly reviewed" | Methodology + platform | **High** | 50–80 min | **Med** | 1 |
| E24 | Surface what the author did not think to ask, through to the end of the task | Methodology + platform | **High** | 60–90 min | Med | 1 |
| E11 | Static analysis that actually runs (Larastan in `init`, gate un-no-op) | Laravel toolchain | **High** | 30–45 min | Low | 1 |
| E10 | Ship the deep skills as real plugin workflows (`workflows/`) | Platform | **High** | 40–60 min | Low | 1 |
| E12 | Skill evals via `skill-creator` — regression protection for the plugin itself | Methodology | **High** | 90–150 min | Low | 1 |
| E13 | `UserPromptSubmit` gate — the protocol engages on the task, not on session start | Platform | High | 30–45 min | Med | 1 |
| E14 | `SubagentStop` contract check — citations and verdicts enforced by the engine | Platform | Med–High | 30–40 min | Low | 2 |
| E15 | Laravel standards as executable architecture tests | Laravel toolchain | Med–High | 60–90 min | Low | 2 |
| E16 | `security-guidance` companion + Laravel pattern file template | Companion | Med–High | 40–60 min | Low | 2 |
| E17 | Pest 5 lane — `--agent` executable proof, `--tia` test gate | Laravel toolchain | Med (conditional) | 45–70 min | Low | 2 |
| E18 | Application-log monitor during implementation and final check | Platform | Med | 25–40 min | Med | 2 |
| E19 | Subagent `memory: project` for `impact-mapper` / `blind-spot-mapper` | Platform | Med | 40–60 min | **Med** | 3 |
| E20 | `SessionEnd` checkpoint write | Platform | Med | 15–25 min | Low | 3 |
| E21 | Manifest hygiene — `$schema`, `displayName`, `defaultEnabled`, `userConfig` | Platform | Low–Med | 15–25 min | Low | 3 |
| E22 | `context: fork` for `openapi-audit` | Platform | Low–Med | 15–20 min | Low | 3 |
| E23 | Path-scoped rules instead of always-loaded guidelines | Platform | Unknown | spike 20–30 min | Unknown | Spike |

---

## Tier 1

### E25 — A verification claim carries its denominator

- **Persona:** developer, and the author reading the report.
- **Origin:** author feedback, 2026-08-11 — "no more *I checked selectively* or *I only went over it
  superficially*".
- **What:** three parts, in increasing hardness.
  1. **The rule.** Any claim about verification states a fraction and an uncovered list: "exercised 7
     of 7 endpoints", or "ran 3 of 12 — the other 9 are «…», not run because «…»". A claim with no
     denominator is not a report, it is an impression. The denominator comes from a set the agent can
     enumerate: the impact map's consumers, the route list, the acceptance-criterion IDs, the changed
     files.
  2. **The consequence.** Uncovered items are not prose hedges — they are entries in the same list the
     Definition of Done reads. "Not covered" and "done" cannot both be true for the same item.
  3. **The gate.** A `Stop` hook reads `last_assistant_message` for partiality markers in Russian and
     English (`выборочно`, `поверхностно`, `частично`, `бегло`, `spot-checked`, `briefly`,
     `should work`, `probably fine`, `mostly`). It blocks **not for the word** — the word is often
     honest — but for the word appearing without an accompanying uncovered list. The block reason
     names the marker and asks for the fraction plus the uncovered items.
- **Why:** Wave 8 made a live run mandatory. It never made the run's *coverage* statable, so "verified
  it works" can mean one endpoint out of nine and still pass every gate. Hedged language is the tell,
  and it is the one part of this that an engine can catch deterministically.
- **Capability:** `Stop` hook. **`runtime-verified` on 2.1.212 by spike, 2026-08-11** — see
  [Spike: the E25 output channel](#spike-the-e25-output-channel). The check makes no model call, so it
  costs nothing.
- **Files:** new `hooks/coverage-claim.sh` + `hooks/tests/coverage-claim.sh`; `hooks/hooks.json`;
  `guidelines/writing-standards.md` (the claim format); `guidelines/ai-sdd-process.md` (per-level
  Definition of Done reads the uncovered list); `skills/final-check/SKILL.md`;
  `agents/conformance-reviewer.md` and `agents/adversarial-verifier.md` (a claim without a denominator
  is itself a finding); `templates/frontend/handoff.md`.
- **Risk (Med):** a regex over natural language over-fires, and the surface is bilingual — the author
  writes Russian, the artifacts are English. Mitigations, all of them already the plugin's house style:
  block at most once per turn, fail open when `.groundwork.json` is absent, match the marker only when
  no uncovered list is present in the same message, and keep the marker list in one place so it is
  editable without touching hook logic.
- **Decided (author, 2026-08-11): warn first, block later.** The first release ships the hook in
  warn-only mode — it appends the notice and lets the turn end — so the false-positive rate is measured
  on real transcripts before a regex over natural language can strand a turn. The *protocol* rule
  (parts 1 and 2) is binding from day one; only the engine-level block waits. Blocking is enabled in a
  following wave, on evidence, and the wave that enables it must state the measured rate.
- **Acceptance criteria:**
  - `E25-AC1` WHEN any skill reports verification, THE report SHALL state exactly one of: total
    coverage, a covered/total fraction plus the enumerated gap, or that no verification was performed.
    A fraction SHALL NEVER be estimated — an unenumerable denominator is the third outcome, not a guess.
  - `E25-AC2` WHEN the final message contains a partiality marker and no uncovered list, THE Stop hook
    SHALL emit a notice naming what is missing, at most once per turn, and SHALL NOT block in the
    first release.
  - `E25-AC2b` WHEN `stop_hook_active` is true, THE hook SHALL return an empty object and emit nothing.
  - `E25-AC3` THE hook SHALL record each trigger so the false-positive rate can be read before
    blocking is enabled.
  - `E25-AC4` WHEN an item is listed as not covered, THE Definition of Done SHALL NOT report the task
    as done without the user accepting that gap explicitly.
  - `E25-AC5` WHEN `.groundwork.json` is absent, THE hook SHALL be a silent no-op.

### E24 — Surface what the author did not think to ask, through to the end

- **Persona:** the author, in the domains where he is not the expert.
- **Origin:** author feedback, 2026-08-11 — "when I am not competent somewhere, or do not realise
  something, the agents should highlight it for me".
- **What:** the plugin already has three mechanisms for this and they all stop before the end of the
  task. Close the three gaps rather than add a fourth mechanism:
  1. **The closing cost-of-silence.** Wave 13 shows what the agent decided alone *before the plan*.
     Nothing shows what it decided alone *after* the plan was approved — which is where implementation
     choices about money, permissions, client-visible behaviour, and integration semantics actually
     get made. `final-check` gains a closing block: every decision taken without asking since
     approval, one line each, with the alternative that was not taken.
  2. **Competence-shaped, not code-shaped.** `blind-spot-mapper` is prompted for blind spots in the
     task. Extend its taxonomy with an explicit axis: what does this change assume the reader knows —
     about the domain, about the provider's rules, about the tax/legal/financial consequence, about
     what the client will do with it — and which of those assumptions has the author never confirmed
     in this project. That axis is what "I did not realise" means in practice.
  3. **Accumulation across sessions.** Today the same project-level blind spot is rediscovered from
     scratch every session, or missed. `blind-spot-mapper` with `memory: project` (see E19) can carry
     an index of which questions this project always turns out to need — **pointers, never
     conclusions**, per the discipline stated in E19.
- **Why:** the failure being described is not "the agent did not know", it is "the agent knew enough to
  decide and did not say it was deciding". The existing blind-spot block fires in discovery, when the
  agent has the least information; the decisions that hurt are made later.
- **Capability:** none for parts 1 and 2 (protocol + agent prompt). Part 3 needs subagent `memory`,
  which is **not** in the list of frontmatter fields ignored for plugin subagents. `doc-verified`.
- **Files:** `skills/final-check/SKILL.md`; `guidelines/blind-spot-protocol.md`;
  `agents/blind-spot-mapper.md`; `guidelines/clarify-protocol.md` (cost-of-silence gains its closing
  half); `skills/frontend-handoff/SKILL.md`.
- **Risk (Med):** this is the mechanism most prone to becoming ceremony — Wave 6 already had to
  calibrate it against noise. Keep the same filter: an item earns its line only if the agent decided
  it alone **and** it changes observable behaviour, money, permissions, or a contract. Everything else
  is not a blind spot, it is an implementation detail.
- **Acceptance criteria:**
  - `E24-AC1` WHEN implementation completes for L2+, THE closing report SHALL list every decision made
    without asking since plan approval, or state that there were none.
  - `E24-AC2` THE blind-spot taxonomy SHALL include unconfirmed assumptions about domain, provider
    rules, financial/legal consequence, and client use.
  - `E24-AC3` An item SHALL be reported only when it changes observable behaviour, money, permissions,
    or a contract.

### E11 — Static analysis that actually runs

- **Persona:** developer.
- **What:** `init` detects the absence of a static-analysis tool, offers Larastan (`larastan/larastan`
  as a dev dependency) with a starting level and a generated baseline, and writes the real command into
  `commands.analyse`. When the user declines, `init` records the decline in `.groundwork.json` so the
  done-gate reports "static analysis declined by the project" instead of printing a fabricated pass.
- **Why:** on `next-lvl-backend` the analyse command is `echo 'no static-analysis tool configured…'`
  and `analyse_on_stop` is `false`. The Definition of Done claims a static-analysis leg that never
  runs. This is the one place where the plugin's own contract is currently untrue on a live project.
- **Capability:** none — a step in `init` plus gate reporting. `runtime-verified` (the no-op was read
  from the project's own config).
- **Files:** `skills/init/SKILL.md`; `templates/project/.groundwork.json`; `hooks/done-gate.sh`
  (report a declared no-op as a skip with a reason, matching the Wave 11 "state the skip" rule);
  `guidelines/laravel-standards.md`; `README.md`.
- **Risk (Low):** a fresh Larastan install on a mature codebase produces hundreds of errors — hence the
  baseline, so only new code is gated.
- **Human step:** approving the dependency and picking the level per project.
- **Acceptance criteria:**
  - `E11-AC1` WHEN `init` runs on a project with no static-analysis tool in `composer.json`, THE skill
    SHALL offer to install one and SHALL NOT write a passing no-op command.
  - `E11-AC2` WHEN `commands.analyse` is a declared no-op, THE done-gate SHALL report a skip naming
    the reason rather than a pass.

### E10 — Ship the deep skills as real plugin workflows

- **Persona:** architect.
- **What:** move the scripts in `skills/deep-*/workflow.md` into `workflows/*.js` at the plugin root.
  They become `/groundwork:deep-review`, `/groundwork:deep-discovery`, `/groundwork:deep-grounding` —
  runtime-executed scripts rather than reference text the model retypes into the `Workflow` tool each
  run. The SKILL.md files stay as the level-gating entry points (L3/L4 only, cost disclosure, seed
  collection) and hand the workflow its input through `args`.
- **Why:** today the orchestration is a document the model must reproduce faithfully. Reproduction can
  drift, costs tokens on every invocation, and forfeits `resumeFromRunId` (a stopped run currently
  restarts from nothing). Shipping the script makes the fan-out, the adversarial panel, and the
  dedup deterministic — the property the deep skills were built for.
- **Capability:** plugin `workflows/` directory, namespaced `/plugin:name`. `runtime-verified` that
  this build's validator accepts the `workflows` manifest field; `doc-verified` for namespacing and
  `args`.
- **Files:** new `workflows/deep-review.js`, `workflows/deep-discovery.js`, `workflows/deep-grounding.js`;
  edit the three `skills/deep-*/SKILL.md` to invoke them with `args`; delete or shrink the
  `workflow.md` reference files; `README.md`.
- **Risk (Low):** a workflow file is versioned with the plugin, so a bad edit ships to every project —
  mitigated by the same conformance pass every wave already runs.
- **Note:** `workflowSizeGuideline` is **not** available on 2.1.212, so the scripts must keep logging
  their own fan-out (the existing `E3-AC2` rule) rather than relying on the platform's size warning.
- **Acceptance criteria:**
  - `E10-AC1` WHEN a deep skill is invoked, THE orchestration SHALL execute from the plugin's shipped
    script, not from a script the model composes.
  - `E10-AC2` THE fan-out count SHALL still be logged to the user before agents spawn.

### E12 — Skill evals: regression protection for the plugin itself

- **Persona:** plugin author (cost/quality).
- **What:** adopt the `skill-creator` plugin's eval loop for the plugin's own skills. Per skill, store
  realistic prompts and expected behaviour in `evals/evals.json`; run each case in an isolated
  subagent; grade assertions; benchmark with-skill against without-skill; and run a blind A/B between
  two versions before a wave ships. Start with the three skills whose descriptions decide routing:
  `start-task`, `spec`, `implement-approved`.
- **Why:** thirteen waves have been validated by author feedback and a conformance agent reading the
  diff. Neither measures whether a skill still triggers on the prompts it should, or whether its
  output got better. Wave 12 was triggered by exactly this blind spot — a rule set that was correct
  on paper and wrong in combination. `skill-creator` also tunes descriptions against
  should-trigger / should-not-trigger prompt sets, which is the mechanism for the recurring
  "the protocol did not engage" complaint.
- **Capability:** `skill-creator@claude-plugins-official`. `doc-verified` (the skills doc documents the
  eval loop, file formats, and benchmark modes); the plugin is present in the marketplace catalog on
  this machine.
- **Files:** `evals/` directories under the selected skills; `docs/skill-hygiene.md` (the hygiene pass
  gains a measured step); a short section in `README.md` under Develop locally.
- **Risk (Low):** eval runs cost tokens and take wall-clock time; keep the case count small and run
  them per wave, not per commit.
- **Human step:** reading the HTML review report and recording qualitative feedback.
- **Acceptance criteria:**
  - `E12-AC1` WHEN a wave changes a skill's description or its routing rules, THE wave SHALL report the
    trigger hit-rate before and after.
  - `E12-AC2` THE eval cases SHALL run in fresh contexts, never in the session that authored the change.

### E13 — `UserPromptSubmit`: engage the protocol on the task, not on session start

- **Persona:** developer.
- **What:** a `UserPromptSubmit` hook that inspects the submitted prompt together with the current
  `Mode:` from the checkpoint and injects `hookSpecificOutput.additionalContext` when a prompt looks
  like a task statement while the session is not in a Groundwork mode — restating that the task enters
  through `start-task`, and naming the current mode. It never blocks.
- **Why:** v0.23.0 put "a task described in chat enters through `start-task` with no command" into the
  SessionStart context, because the author writes tasks as prose. SessionStart fires once; a long
  session states dozens of tasks, and the reminder is far behind in context by then.
  `UserPromptSubmit` fires on every prompt and is the event designed for this.
- **Capability:** `UserPromptSubmit` hook with `additionalContext`; 30-second timeout. `doc-verified`.
- **Files:** new `hooks/task-intent.sh`; `hooks/hooks.json`; `hooks/tests/` (new suite); `README.md`.
- **Risk (Med):** a noisy classifier that fires on every message would be worse than the current
  reminder. Mitigations: keep the match narrow and cheap (no model call), fire at most once per N
  prompts per session, honour a `.groundwork.json` toggle defaulting to on only inside Groundwork
  projects, and fail open exactly like every existing hook.
- **Acceptance criteria:**
  - `E13-AC1` WHEN `.groundwork.json` is absent, THE hook SHALL be a silent no-op.
  - `E13-AC2` THE hook SHALL never block a prompt; it SHALL only add context.
  - `E13-AC3` WHEN the session is already in a Groundwork mode, THE hook SHALL stay silent.

---

## Tier 2

### E14 — `SubagentStop`: the output contract checked by the engine

- **What:** a `SubagentStop` hook matched to `groundwork:grounded-researcher` and
  `groundwork:adversarial-verifier` that inspects the returned text for the contract each agent
  promises — a source or an explicit `UNKNOWN` per claim for the researcher, a verdict with evidence
  for the verifier — and returns `decision: "block"` with the missing element when it is absent.
- **Why:** the grounding protocol's central rule ("never guess; every claim carries a source or is
  marked UNKNOWN") is enforced today only by the agent's own prompt. `SubagentStop` can block the
  return, which turns the rule from an instruction into a gate. This is the same move Wave 2 made for
  runner and migration rules.
- **Capability:** `SubagentStop` hook with agent-type matcher and `decision: "block"`. `doc-verified`.
  Hyphenated agent names in matchers need ≥2.1.195 — satisfied here (2.1.212); use `^name$` form.
- **Risk (Low):** a shape check that is too strict loops the agent. Cap at one block per agent run.
- **Acceptance criteria:**
  - `E14-AC1` WHEN a researcher returns a claim with neither a citation nor `UNKNOWN`, THE hook SHALL
    block once and name the offending claim.
  - `E14-AC2` THE hook SHALL block at most once per subagent run.

### E15 — Laravel standards as executable architecture tests

- **What:** `init` generates an architecture-test file from `guidelines/laravel-standards.md` — the
  rules that are currently prose: no repository/DDD/CQRS layer, controllers stay thin, form requests
  carry validation, models declare casts, no direct facade use where a service is prescribed. Pest's
  arch testing expresses these directly; a PHPUnit project gets the equivalent as a PHPStan rule set
  or an explicit skip with a stated reason.
- **Why:** the standards are the plugin's most frequently violated surface and the only major rule set
  with no gate behind it. Converting them to tests puts them under the existing test gate at zero
  additional protocol.
- **Capability:** none (project test code). `doc-verified` for Pest arch testing.
- **Risk (Low):** an existing codebase violates its own standards on day one — generate the file with
  the violations recorded as a baseline, same shape as E11.
- **Acceptance criteria:**
  - `E15-AC1` WHEN `init` runs on a project whose test framework supports architecture tests, THE skill
    SHALL offer to generate them from the standards it just wrote.

### E16 — `security-guidance` companion + a Laravel pattern file

- **What:** add `security-guidance@claude-plugins-official` to the recommended set (not necessarily to
  `groundwork-pack`), and ship `templates/project/security-patterns.yaml` with Laravel-specific
  deterministic patterns: raw-SQL interpolation in `DB::raw`, a write route with no policy or
  `authorize` call nearby, mass assignment with `$request->all()`, a query on a tenant-scoped model
  without the scope, a hardcoded credential prefix. `init` offers to drop the file.
- **Why:** the per-edit layer of that plugin is a **string match with no model call** — near-zero cost,
  which is the exact bar the v0.19.0 bundle rule sets. It fires while code is being written, whereas
  `risk-review` fires on a finished diff. The two layers do not overlap: this one catches generic
  vulnerability shapes, `risk-review` catches domain and permission risk.
- **Capability:** `security-guidance` plugin; `.claude/security-patterns.yaml` (also `.yml`/`.json`;
  the YAML forms need PyYAML importable — **ship the JSON form** to avoid that dependency).
  `doc-verified`.
- **Risk (Low):** the plugin's Stop-review and commit-review layers *do* cost model calls; the
  recommendation must state that, and note they can be disabled independently via
  `ENABLE_STOP_REVIEW=0` / `ENABLE_COMMIT_REVIEW=0` while keeping the free per-edit layer.
- **Acceptance criteria:**
  - `E16-AC1` THE shipped pattern file SHALL be in a format that loads without an extra Python
    dependency.
  - `E16-AC2` THE README SHALL state which layers of the companion plugin cost model calls.

### E17 — The Pest 5 lane

- **What:** two conditional capabilities, both gated on the project actually running Pest 5:
  - **`--agent` executable proof.** `pest --agent='<php>'` runs a snippet inside a full test
    environment — factories, database refresh, Laravel fakes — which is precisely what
    `grounding-protocol`'s executable-proof step and Wave 8's live verification ask for. Today that
    proof is produced with Boost's `tinker` tool, which runs against the dev database rather than a
    test environment.
  - **`--tia` test impact analysis.** Re-runs only tests affected by the change and replays the rest
    from cache. The test gate currently runs the full suite on every Stop and works around the cost
    with a shared-database lock and the `reuse_green_run` byte-identity check. TIA addresses the same
    cost at the source.
- **Why:** both are direct answers to problems the plugin already solved with heavier machinery.
- **Capability:** `pestphp/pest-plugin-agent` and the Tia engine (needs PCOV or Xdebug for the baseline
  run). `doc-verified`. **Applicability is conditional:** Pest 5 requires PHP 8.4 and PHPUnit 13, and
  the reference project here runs PHPUnit 11 — so this lane is inert on it until that project migrates.
- **Risk (Low):** TIA must stay local-only; CI keeps the full suite. The gate must detect Pest 5 and
  fall back silently, per the plugin's fail-open rule.
- **Human step:** deciding whether any given project migrates to Pest 5.
- **Acceptance criteria:**
  - `E17-AC1` WHEN the project does not run Pest 5, THE gate behaviour SHALL be unchanged.
  - `E17-AC2` WHEN `--tia` is used, THE gate SHALL state that the run was impact-scoped, not full.

### E18 — Application-log monitor during implementation

- **What:** a plugin monitor (`monitors/monitors.json`) with
  `when: "on-skill-invoke:implement-approved"` tailing the configured application log, so a runtime
  error raised by the code just written arrives as a notification instead of waiting for someone to
  look.
- **Why:** the dominant complaint mined in the v0.12.0 window was "said done, but it doesn't work
  live". A monitor is the cheapest continuous form of live evidence.
- **Capability:** plugin monitors. `runtime-verified` that the manifest field is recognized on 2.1.212
  (needs ≥2.1.207); `doc-verified` for `when: on-skill-invoke`.
- **Risk (Med):** a chatty log floods the context, and monitors keep running after the plugin is
  disabled mid-session. Mitigation: a `.groundwork.json` toggle defaulting to **off**, a filtered tail
  (errors only), and a documented log path per project.
- **Acceptance criteria:**
  - `E18-AC1` THE monitor SHALL start only on skill invocation, never at session start.
  - `E18-AC2` THE monitor SHALL be off unless the project opts in.

---

## Tier 3

### E19 — Subagent `memory: project`

Give `impact-mapper` and `blind-spot-mapper` a `memory: project` directory
(`.claude/agent-memory/<agent>/`, shareable via version control). The 2026-06 roadmap listed subagent
memory as out of scope for being speculative; the mechanism is now documented, and the `memory` field
is **not** in the list of frontmatter keys ignored for plugin subagents (unlike `permissionMode`,
`mcpServers`, and `hooks`, which are).

**Risk (Med) — and it is the plugin's own core risk.** A memory file is an unverified claim that a
future session inherits as a premise, exactly the failure the checkpoint accuracy rule in Wave 11 was
written to prevent. If this is built, memory must hold **pointers, not conclusions**: where a coupling
lives, which files a seed touches, which questions this domain always raises — never "X is safe" or
"Y has no consumers". Requires auto memory to be enabled (`autoMemoryEnabled`); the field is inert
otherwise.

### E20 — `SessionEnd` checkpoint write

The checkpoint is currently maintained by `PreCompact` and by explicit protocol steps. `SessionEnd`
fires on clear, resume, and logout, catching sessions that end without a compaction. Constraint:
SessionEnd hooks share a ~1.5-second budget, so this may only append a small pre-computed file, never
run a gate.

### E21 — Manifest hygiene

Add `$schema` (editor autocomplete and validation), `displayName`, and consider `defaultEnabled`.
Evaluate `userConfig` for **author-global** preferences only — `pluginConfigs` values are read from
user, managed, and `--settings` scopes and **ignored in project settings**, so per-project
configuration must stay in `.groundwork.json`. Note that `${user_config.*}` is rejected in shell-form
hook commands; hooks read `CLAUDE_PLUGIN_OPTION_<KEY>` from the environment instead.

### E22 — `context: fork` for `openapi-audit`

The audit is mechanical, produces high-volume output, and needs no conversation history — the profile
`context: fork` exists for. On this build (2.1.212 < 2.1.218) a forked skill blocks the turn until it
finishes, so the gain is context isolation, not parallelism. Do not fork the interview-bearing skills
(`start-task`, `grill`, `spec`): they depend on conversation history and on `AskUserQuestion`.

### E23 — Spike: path-scoped rules

The skills documentation warns against reusing `paths` as a `metadata` key, and the `InstructionsLoaded`
hook has a `path_glob_match` load reason — both imply instruction files that load when matching files
are touched. If that works for plugin-shipped rules, the migration protocol could load when
`database/migrations/**` is touched and the OpenAPI protocol when a controller changes, instead of
being pulled in wholesale by a skill. **`assumed` — measure before building.** Deliverable: one page
recording whether a plugin can ship a path-scoped rule on 2.1.212 and what the load reason looks like.

---

## Spike: the E25 output channel

Run 2026-08-11 on Claude Code 2.1.212, before any of E25 was designed, because the whole item rests on
what a `Stop` hook actually receives and what each output field does to the turn. Method: an isolated
directory outside any project, a `.claude/settings.json` registering one `Stop` hook that dumps its
stdin and echoes a chosen payload, driven by `claude -p … --settings … --tools ""`. Three runs.

| Question | Result |
|---|---|
| Does the `Stop` hook receive the assistant's final text? | **Yes.** `last_assistant_message` held the reply verbatim. The payload also carries `session_id`, `transcript_path`, `cwd`, `prompt_id`, `permission_mode`, `effort`, `background_tasks`, and `stop_hook_active` |
| Does `hookSpecificOutput.additionalContext` end the turn? | **No — it continues it.** The hook fired a second time, and the model answered the injected notice on the record. This is a soft block, not a warning |
| Does `systemMessage` end the turn? | **Yes.** One turn, one hook call, `stop_reason: end_turn` |
| Is there a loop guard? | **Yes.** `stop_hook_active` is `false` on the first call and `true` on the re-entry after a continuation |
| Does `systemMessage` reach the user? | **Not established.** It did not appear in the `stream-json` output. The docs describe it as user-facing, which points at the interactive UI; headless cannot answer this |

Consequences for the design, all three of which change what the spec must say:

1. **Warn-only cannot be built from `additionalContext`.** That field re-enters the model and forces an
   answer — the exact behaviour the author deferred. Warn-only means `systemMessage`, plus the hook's
   own log for the false-positive count that gates the later blocking release.
2. **The hook must return an empty object when `stop_hook_active` is true**, or a blocking release
   would re-trigger on the very message it demanded.
3. **The user-visible channel needs one more check in an interactive session.** If `systemMessage` is
   not visible enough, the fallback is the plugin's existing status line, which already carries gate
   state.

One unplanned finding, worth more than the three above: given the notice, the model **refused to
manufacture a denominator**, answering that no verification had occurred so no fraction existed and
inventing one would be fabrication. The rule as worded does not push toward fake numbers — but it must
name that third outcome explicitly, alongside "total coverage" and "partial coverage plus the gap
list": *no verification was performed*, stated plainly.

## Considered and rejected

- **Agent teams.** Experimental, off by default (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), with
  documented limitations around resume, task-status lag, and shutdown. The adversarial debate shape it
  enables is already covered by the deep-review verifier panel at lower cost. Watch, do not adopt.
- **Rector in the gates.** Automated refactoring across a diff conflicts with "keep scope tight" and
  with the approval gate. A user-invoked modernization skill would be a separate product.
- **`lspServers` in the groundwork manifest.** Duplicates `php-lsp@claude-plugins-official`, which the
  pack already carries, and would fight it for the `.php` extension — the first server registered wins
  and the other never starts.
- **Postman MCP for the frontend handoff.** The handoff's runnable request package is satisfied by a
  curl/Postman collection generated from the OpenAPI spec; an MCP server plus an account is a worse
  trade for the same artifact.
- **`sonarqube`, `semgrep`, `42crunch`.** Unchanged from the v0.19.0 decision: server or account
  dependencies, or hooks that fire on every write.
- **Sandbox configuration.** Real value for prompt reduction, but it is a security boundary belonging
  to the user's settings; a plugin should document it, not set it.
- **Dedicated observability plugin (dash0, Honeycomb, Datadog) for estimate calibration.** Tempting for
  the Wave 13 estimate rule, which currently calibrates against commit intervals. All three are
  external services; revisit only if Claude Code's built-in usage monitoring exposes per-task
  wall-clock locally.

---

## Suggested sequencing

De-risking first, then value. Each is independently shippable under the one-wave-per-minor-bump rule.

Author decisions, 2026-08-11:

- **Selected:** E25, E24, E11, E10, E12 — E25 and E24 raised from the author's own feedback, the other
  three from the research sweep.
- **Next wave:** E25 + E24 together, as one wave.
- **E25 gate hardness:** warn-only in the first release, blocking enabled later on measured evidence.

1. **E25 + E24** — the two the author asked for. They travel together: E25 makes an incomplete check
   impossible to state as a complete one, E24 makes a silent decision impossible to leave silent.
   Both are the same failure seen from two sides — work that reads as finished because what is
   missing was never named.
2. **E11** — the only item that fixes a currently untrue claim in the Definition of Done, and a
   precondition for E25: a gate that reports a fabricated pass is a coverage claim with no denominator.
3. **E12** — before more rules are added, get a measurement that catches the next Wave-12-shaped
   regression. E25 and E24 add rules to the most crowded part of the rule set, so the measurement is
   worth having early rather than late.
4. **E10** — moves existing behaviour onto a supported component; no methodology change.
5. **E13 + E14** — the two remaining engine-level enforcements, both narrow and fail-open.
6. **E15 + E16 + E17 + E18** — toolchain and companion work, each conditional on project shape.
7. **E19–E22** — tuning. E19 is a dependency of E24's third part, so it is pulled forward if that part
   is kept. **E23** first as a spike; build only if the spike says yes.

One sequencing caution: E25's Stop hook and E24's closing report both add obligatory output to the end
of every L2+ task, which is exactly the asymmetry Wave 12 had to unwind — rules written without a
level. Both must carry per-level calibration from the first line of their spec, not after the fact.

---

## Sources

Fetched 2026-08-11 unless noted.

- Claude Code documentation: [hooks reference](https://code.claude.com/docs/en/hooks),
  [plugins reference](https://code.claude.com/docs/en/plugins-reference),
  [skills](https://code.claude.com/docs/en/skills),
  [subagents](https://code.claude.com/docs/en/sub-agents),
  [workflows](https://code.claude.com/docs/en/workflows),
  [agent teams](https://code.claude.com/docs/en/agent-teams),
  [security guidance](https://code.claude.com/docs/en/security-guidance),
  [sandboxing](https://code.claude.com/docs/en/sandboxing).
- Laravel: [AI-assisted development (13.x)](https://laravel.com/docs/13.x/ai) — Boost tool list,
  version-aware guidelines, Agent Skills.
- Pest: [Pest 5 announcement](https://pestphp.com/docs/pest5-now-available) and
  [Laravel News coverage](https://laravel-news.com/pest-5) — Tia engine, agent plugin, evals plugin,
  first-party PHPStan plugin.
- SDD landscape 2026: GitHub Spec Kit's specify → plan → tasks → implement loop and the AGENTS.md
  convention, surveyed via [the GitHub Spec Kit announcement](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/)
  and secondary 2026 surveys. The plugin's pipeline already covers this loop; no gap found, which is
  itself a finding.
- Official plugin catalog read from the local marketplace cache
  (`~/.claude/plugins/plugin-catalog-cache.json`, `claude-plugins-official`).
