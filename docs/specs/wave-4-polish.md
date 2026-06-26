# Spec: Wave 4 — polish (clarify/converge · ADR · pinning) (plugin v0.8.0)

- Type: plugin self-improvement (docs / templates / agent frontmatter — low risk, no platform dependency)
- Source: [plugin-enhancement-roadmap.md](plugin-enhancement-roadmap.md) E5, E8, E9
- Status: approved → implemented (2026-06-26); conformance review CONFORMS (W4-AC1–AC6)
- Target version: v0.8.0

## Goal

Close the roadmap with three low-risk refinements: catch under-specification earlier and re-audit at
the end (E5), give cross-cutting decisions a durable home (E8), and pin verification/research effort
(E9). All prose / template / frontmatter — no hooks, no scripts.

## Scope (Wave 4)

E5 (clarify + converge), E8 (lightweight ADR at L3/L4), E9 (effort-pinning + progressive-disclosure
audit). Final wave; closes the roadmap.

## Design — per item

### E5 — `clarify` pass (pre-plan) + `converge` re-check (post-impl)

- **clarify** — a short disambiguation step **between Spec and Plan**: surface logical inconsistencies,
  conflicting constraints, and gaps as explicit questions **before** producing the plan (cheapest place
  to fix under-specification). Files: `skills/start-task/SKILL.md` (a clarify step before the plan);
  `guidelines/ai-sdd-process.md` (Operating modes / startup sequence mention it).
- **converge** — a post-implementation re-audit: compare the spec's **full** acceptance-criteria set
  against implemented reality and append any unmet / deferred criteria to the checkpoint as remaining
  tasks (broader than the diff-scoped `conformance-reviewer`). Files: `skills/final-check/SKILL.md` (a
  converge step before closing the checkpoint).

### E8 — lightweight ADR at L3/L4 gates (hybrid, per the locked decision)

- New `templates/adr.md` — a 5-section MADR-lite: context · considered options (≥2) · decision ·
  rationale · consequences.
- Capture rule: when an **L3/L4** human-approval gate is hit for a **cross-cutting, durable** decision
  (new dependency, new architectural layer, workflow-state model), write
  `docs/adr/NNNN-<slug>.md` from the template (≥2 options + chosen + why). **Feature-local** trade-offs
  stay in the spec's existing "technical approach and tradeoffs" section — do not duplicate.
- Files: new `templates/adr.md`; `skills/spec/SKILL.md` (the ADR step for cross-cutting L3/L4);
  `guidelines/ai-sdd-process.md` (the "Human approval gates" list gains "write the ADR for a
  cross-cutting decision").

### E9 — effort-pinning + progressive-disclosure audit

- **Effort-pinning** (Wave 0: agent frontmatter honors `effort`): add `effort: high` to
  `grounded-researcher` and `adversarial-verifier` (careful research / refutation);
  `conformance-reviewer` already has it; set `impact-mapper` to `effort: medium` (mechanical breadth —
  grep/read fan-out). **`model` stays `inherit`** (unset) deliberately — pinning a tier could downgrade
  the user's session model; `effort` is the safe, task-appropriate lever. Files: the three agent files.
- **Progressive disclosure** — the audit (this spec's prep) found every `SKILL.md` already lean
  (largest 73 lines) and the `deep-*` skills already use bundled `workflow.md`; guidelines are loaded on
  demand via path. **No extraction needed** — record the audit result; do not invent moves. Files: none
  (audit recorded here).

### Rollout

- `.claude-plugin/plugin.json` → `0.8.0`; `README.md` "What's inside" notes clarify/converge + ADRs.

## Acceptance criteria (EARS — dogfooding E4)

Verification is structural (inspect the Markdown / frontmatter); no executable proof (no scripts).

- [ ] **W4-AC1** WHEN `start-task` runs for an L2+ task THE skill SHALL include a clarify pass that
      surfaces ambiguities / conflicts / gaps as explicit questions before the plan.
      → check: skills/start-task/SKILL.md
- [ ] **W4-AC2** WHEN `final-check` runs THE skill SHALL include a converge step that re-audits the
      spec's full acceptance-criteria set against reality and appends unmet/deferred items to the
      checkpoint. → check: skills/final-check/SKILL.md
- [ ] **W4-AC3** THE `templates/adr.md` SHALL exist with context · ≥2 considered options · decision ·
      rationale · consequences. → check: templates/adr.md
- [ ] **W4-AC4** WHEN an L3/L4 approval gate is hit for a cross-cutting decision THE process SHALL
      instruct writing `docs/adr/NNNN-<slug>.md` (≥2 options + chosen + why); feature-local trade-offs
      stay in the spec. → check: skills/spec/SKILL.md + guidelines/ai-sdd-process.md
- [ ] **W4-AC5** THE `grounded-researcher`, `adversarial-verifier`, and `conformance-reviewer` agents
      SHALL declare `effort: high`, AND `impact-mapper` SHALL declare an explicit `effort`; no agent
      SHALL pin `model` (stays inherit). → check: agents/*.md
- [ ] **W4-AC6** No `SKILL.md` SHALL inline reference material that belongs in a bundled/guideline file
      (progressive-disclosure audit recorded; no extraction required). → check: this spec + skills/

## Risks / assumptions

- **Ceremony creep** (clarify / ADR) — mitigated: clarify stays a short question pass; ADRs are
  L3/L4 + cross-cutting only, feature-local trade-offs stay in the spec.
- **Effort cost** — `effort: high` on research/verification agents raises their cost slightly; justified
  by their role (the place to spend care). `impact-mapper` at `medium` offsets it.
- **Assumption** — the progressive-disclosure audit is accurate (skills already lean); if a future
  SKILL.md grows reference bulk, extract then.

## Rollout

- Version **v0.8.0**. Additive — no behavior change. Closes the roadmap.
- Commit (single line, no AI attribution): `feat: v0.8.0 — clarify/converge passes, ADR capture, agent effort-pinning`.

## Verification plan

Inspect each touched file against W4-AC1–AC6; dogfood `conformance-reviewer` on the diff. Confirm agent
frontmatter stays valid (the plugin still loads the agents).
