# Spec: Wave 3 — deep skills (Workflow-driven) (plugin v0.7.0)

- Type: plugin self-improvement (3 new skills + bundled workflow patterns + docs)
- Source: [plugin-enhancement-roadmap.md](plugin-enhancement-roadmap.md) E3; capability basis in
  [wave-0-capability-confirmation.md](wave-0-capability-confirmation.md)
- Status: approved → implemented (2026-06-26); AC1–AC6 conformance CONFORMS; AC7 live smoke PASSED (Workflow ran, plugin agentType resolved, schema return OK)
- Target version: v0.7.0
- Depends on: the `Workflow` tool (Dynamic workflows — paid plan, recent Claude Code). The skills must
  **degrade gracefully** when it is unavailable.

## Goal

Replace the by-hand, single-agent fan-out in the expensive phases with **deterministic multi-agent
workflows** (orchestrator-worker → adversarial verify → synthesize). Three skills, each escalating an
existing base skill for high-risk work — the headline being `deep-grounding`, the direct answer to
"thoughtful analysis of original documentation".

## Scope (Wave 3)

Three new skills: `deep-grounding`, `deep-discovery`, `deep-review`. Each authors and runs a `Workflow`
script of a fixed shape, using the plugin's existing agents as workers via `agentType`. **Strict
guardrails:** explicit invocation only, L3/L4 only, never auto-trigger, log the fan-out, graceful
fallback to the base skill if Workflow is unavailable.

Recommended build order within the wave: **`deep-grounding` first** (the headline), then
`deep-discovery`, then `deep-review`.

## Out of scope / future

Wave 4 (E5/E8/E9). These skills do not change the base skills' behavior for L0–L2 — those keep the
single-agent flow.

## Why workflows (grounding)

Anthropic's multi-agent research system: a lead agent delegates to specialized subagents in parallel;
best for breadth-first independent work; ~15× the tokens of a single chat, so gate it behind value.
The `Workflow` tool gives this deterministically (pipeline/parallel/loop), with `agentType` to spawn
the plugin's own agents and `schema` for validated structured returns. Opt-in: invoking one of these
skills **is** the explicit opt-in (per the Workflow tool's own rule).

## Design — per skill

Each SKILL.md stays lean and references a bundled level-3 reference script (progressive disclosure,
dogfooding E9): `skills/<name>/workflow.md` holds the canonical Workflow shape the model adapts and
runs inline via `Workflow({script})`. Workers are spawned with
`agentType: "groundwork:<agent>"`.

### `deep-grounding` — verified capability matrix from a large API doc (escalates `ground-integration`)

Workflow shape:
- **Read (fan-out):** one `grounded-researcher` per needed capability/doc-area — each returns a cited
  finding (`supported? / evidence URL+quote / UNKNOWN`) for its slice. `parallel`.
- **Verify (adversarial panel):** for each matrix row, ≥2 `adversarial-verifier` skeptics, each a
  distinct lens (docs-literal, edge-cases/error-paths), each prompted to **refute** the "supported"
  claim against the cited evidence; default REFUTED when evidence is absent. `parallel` per row.
- **Synthesize:** the capability matrix with, per row, `supported / evidence / adversarial verdict /
  confidence / fallback`, plus the open-unknowns list. Feed into the integration spec.

Output ⊇ `ground-integration`'s matrix, but every row is independently refuted-or-survived.

### `deep-discovery` — consolidated blast radius from many seeds (escalates `start-task` L3/L4)

Workflow shape:
- **Map (fan-out):** one `impact-mapper` per seed (model/service/table); if an external API is
  involved, a `grounded-researcher` in parallel. `parallel`.
- **Merge:** dedup the connection maps into one blast radius + ranked hotspots (plain code, not an
  agent).
- **Verify dynamic edges:** the "unresolved/dynamic edges" each mapper flagged (string-dispatched
  events, container bindings, magic) get a focused `adversarial-verifier`/self-check pass.
- **Synthesize:** one blast-radius map + ranked read-list + hotspots + open questions. Cacheable to
  `.claude/groundwork/impact/<slug>.md` per the working-memory layer (reuse its staleness check).

### `deep-review` — adversarially-verified risk review (escalates `risk-review` L3/L4)

Workflow shape (the canonical review pipeline):
- **Dimensions:** the `risk-review` categories (API contract, RBAC, financial visibility, migrations,
  workflow state, queues/scheduler, N+1, integration).
- **Pipeline per dimension:** find (the dimension lens) → for each finding, `parallel` adversarial
  verify (≥2 skeptics, refute by default) → keep only confirmed. No barrier between dimensions.
- Plus a `conformance-reviewer` pass on the diff vs the spec's acceptance criteria.
- **Synthesize:** ranked **confirmed** risks · required approvals · missing/after-the-fact tests ·
  suggested fixes.

### Cross-links + docs

- `ground-integration`, `start-task`, `risk-review` each gain a one-line "for L3/L4, escalate to the
  `deep-*` variant" pointer (consistent with the E7 fan-out table).
- `guidelines/ai-sdd-process.md` "Fan-out by level" L3/L4 rows reference the deep skills by name (the
  rows already say "May escalate to the deep-* skills" — make the names concrete).
- `README.md` "What's inside" gains the deep-skills line.
- `.claude-plugin/plugin.json` → `0.7.0`.

## Guardrails (mandatory in every deep SKILL.md)

1. **Explicit invocation only** — never auto-trigger; the base skills handle L0–L2.
2. **L3/L4 only** — state it; refuse politely on lower levels and point to the base skill.
3. **Log the fan-out** — `log()` the number of agents/seeds/dimensions so the token cost is visible.
4. **Graceful fallback** — IF the `Workflow` tool is unavailable (plan/version), THEN fall back to the
   base skill's single-agent flow and say so; never hard-fail.
5. **Reuse caches** — `deep-discovery` honors the impact-cache staleness check before re-mapping.

## Acceptance criteria (EARS — dogfooding E4)

Verification is structural (the SKILL.md/workflow.md instruct the correct shape) plus one **smoke
test** (AC7). Live full runs against real APIs are validated in a real project (token cost).

- [ ] **AC1** THE `deep-grounding` skill SHALL instruct a Workflow that fans out cited readers per
      capability, runs an adversarial panel (≥2 skeptics, refute-by-default) per matrix row, and
      outputs a capability matrix with per-row evidence + adversarial verdict + confidence.
      → check: skills/deep-grounding/SKILL.md + workflow.md
- [ ] **AC2** THE `deep-discovery` skill SHALL instruct a Workflow that parallel-maps multiple seeds via
      `agentType` impact-mapper, dedups into one blast radius + hotspots, verifies dynamic edges, and
      MAY cache to `.claude/groundwork/impact/<slug>.md`. → check: skills/deep-discovery/SKILL.md + workflow.md
- [ ] **AC3** THE `deep-review` skill SHALL instruct a Workflow pipeline over the risk dimensions where
      each finding is adversarially verified (≥2 skeptics) before it is reported, output = ranked
      confirmed risks. → check: skills/deep-review/SKILL.md + workflow.md
- [ ] **AC4** WHILE the task level is L0–L2, WHEN a deep skill is invoked THE skill SHALL decline and
      point to the base skill; AND every deep skill SHALL `log()` its fan-out size.
      → check: each deep SKILL.md
- [ ] **AC5** IF the `Workflow` tool is unavailable THEN each deep skill SHALL fall back to its base
      skill's single-agent flow and state so (no hard failure). → check: each deep SKILL.md
- [ ] **AC6** EACH deep skill SHALL keep SKILL.md lean and hold the full Workflow reference script in a
      bundled `workflow.md`, and SHALL spawn workers via `agentType: "groundwork:<agent>"`.
      → check: skills/deep-*/
- [ ] **AC7** WHEN a minimal smoke-test workflow (tiny fan-out, 2–3 agents) is run, THE pattern SHALL
      execute and return the documented structured shape. → proof: one smoke-test run during impl
      (flag token cost; may be deferred to a real project if the user prefers).

## Risks / assumptions

- **Token cost (~15×)** — the defining risk. Mitigations: AC4 guardrails (explicit + L3/L4 + log),
  cache reuse, and the smoke test stays minimal.
- **Workflow availability** — paid plan + recent CC. Mitigation: AC5 graceful fallback; the plugin
  stays fully functional without Workflow (the base skills are unchanged).
- **`agentType` resolution for plugin agents inside a workflow** — must confirm the plugin's agents
  resolve as `agentType` from within a Workflow run; verify in the AC7 smoke test. If not, fall back to
  inline role prompts (general agent carrying the agent's instructions).
- **Opt-in semantics** — invoking the skill is the documented opt-in; the SKILL.md states this so the
  model proceeds without a second prompt.
- **Assumption** — L3/L4 tasks are rare enough that ~15× cost on them is justified (Anthropic: only
  worth it when task value is high).

## Rollout

- Version **v0.7.0**. Additive — three new skills; no change to existing behavior. Release note: the
  deep-* skills are opt-in, L3/L4, Workflow-backed, with graceful fallback.
- Commit (single line, no AI attribution): `feat: v0.7.0 — deep-* skills (Workflow-driven discovery, grounding, review)`.

## Verification plan

Structural review of the three SKILL.md + workflow.md against AC1–AC6; `conformance-reviewer` dogfood
on the diff. AC7: one minimal smoke-test workflow run (confirm `agentType` resolution + the structured
return). Confirm the live ~15× behavior + Workflow availability once in a real project.
