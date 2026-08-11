# Spec: Wave 16 — the deep skills ship their orchestration (v0.26.0)

- Type: plugin self-improvement → **L2** (three new files, three skills edited, no methodology change).
- Author: Max Yastremskyi (YasMax91).
- Source: research item E10 in [modernization-research-2026-08.md](modernization-research-2026-08.md).
- Status: **implemented** (2026-08-11). Command registration verified live; the scripts themselves have
  not been executed — see Risks.
- Target version: **v0.26.0**.

## Goal

The orchestration the deep skills depend on was reference text the model had to reproduce. Ship it as
code the runtime executes.

## Problem (diagnosis)

Wave 3 put each deep skill's Workflow script in a bundled `workflow.md` and told the skill to "author
and run" it. Three costs followed, none of them visible in a single run:

1. **Reproduction can drift.** The adversarial panel, the dedup, the schema and the phase structure
   were retyped into the `Workflow` tool on every invocation. Nothing guaranteed the run matched the
   reviewed script — the property the deep skills exist for.
2. **No resume.** A workflow run is resumable only from a script the runtime holds. A stopped
   `deep-review` restarted from nothing, discarding every completed agent.
3. **Tokens per invocation.** A ~50-line script is retyped in full each time before any work begins.

Meanwhile the platform grew a plugin component for exactly this: a `workflows/` directory at the plugin
root, namespaced as `/<plugin>:<meta.name>`.

## Design

### A — Three executable scripts

`workflows/deep-review-run.js`, `workflows/deep-discovery-run.js`, `workflows/deep-grounding-run.js`.
Same orchestration as the Wave 3 reference scripts, with three additions:

- **Input validation.** `deep-discovery-run` throws without `args.seeds`; `deep-grounding-run` throws
  without `args.capabilities`. A workflow that silently maps nothing is worse than one that refuses.
- **Counts in the return value.** `examined`/`dropped`/`confirmed`, `seedCount`/`mappedSeeds`/
  `failedSeeds`, `edgesFound`/`edgesVerified`, `requested`/`returned`. This is Wave 14's denominator
  rule reaching the machinery: the skill can now report coverage instead of a list.
- **No silent caps.** `deep-discovery-run` logs how many dynamic edges it left unchecked when the list
  exceeds `maxEdges` (default 12), instead of truncating quietly.

`log()` messages are Russian, per the author's language rule for anything he reads.

### B — Naming, so nothing collides

Scripts are `deep-*-run`, not `deep-*`. The skills already own `/groundwork:deep-review` and the two
others; a workflow with the same `meta.name` would compete for the same command name. The suffix keeps
both reachable: the skill for the gated path, the script for the raw orchestration.

### C — The skills become entry points only

Each skill now invokes the `Workflow` tool by name with `args` and is told **not** to rewrite the
script inline. Level gating, cost disclosure, the impact-cache staleness check and the fallback when
`Workflow` is unavailable stay in the skill, which is where they belong.

The three `skills/deep-*/workflow.md` files are deleted: a second copy of an executable script is a
second thing to keep in sync.

## Acceptance criteria (EARS)

- [x] **W16-AC1** THE plugin SHALL ship the three orchestrations as executable scripts under
      `workflows/`. → check: `workflows/*.js`
- [x] **W16-AC2** WHEN a session loads the plugin, THE three scripts SHALL be registered as
      `/groundwork:deep-*-run` commands alongside the existing skills, with no name collision. → check:
      live `slash_commands` list from a headless session (verified 2026-08-11)
- [x] **W16-AC3** WHEN a deep skill runs, THE skill SHALL invoke the shipped script by name and SHALL
      NOT author the orchestration inline. → check: the three SKILL.md files
- [x] **W16-AC4** WHEN `deep-discovery-run` is called without `seeds`, or `deep-grounding-run` without
      `capabilities`, THE script SHALL refuse with a message naming the missing argument. → check:
      `workflows/deep-discovery-run.js`, `workflows/deep-grounding-run.js`
- [x] **W16-AC5** EACH script SHALL return the counts its skill needs to state coverage. → check: the
      three scripts' return values
- [x] **W16-AC6** WHEN a script bounds its own work (edge cap), THE bound SHALL be logged. → check:
      `workflows/deep-discovery-run.js`
- [x] **W16-AC7** THE superseded `skills/deep-*/workflow.md` files SHALL be removed and no skill SHALL
      still reference them. → check: `git rm`, plus a repository grep (only historical specs mention them)

## Risks / assumptions

- **The scripts have not been executed.** Registration is verified live; the orchestration is verified
  only by syntax check (parsed in its real wrapper shape) and by being a near-copy of the Wave 3
  scripts, which passed a live smoke test then. The first real `deep-review` run is the proof, and it
  costs ~15× a normal review — which is why it was not run for a verification exercise.
- **`args` is now a contract.** The scripts throw on missing input where the old text would have been
  adapted by hand. That is the intended trade: a loud refusal beats a workflow that maps nothing.
- **Direct invocation bypasses the level gate.** `/groundwork:deep-review-run` runs the fan-out without
  the L3/L4 check that lives in the skill. Documented as deliberate — the gating is advice to the
  agent, and a user who types the raw command has opted in explicitly.
- **Historical specs still mention `workflow.md`.** Waves 3, 4 and 6 describe the old layout. Those are
  records of what happened, not instructions, and are left alone.
