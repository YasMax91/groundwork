---
description: Deep, multi-agent risk review — find risks across every dimension, then adversarially verify each finding before reporting. Use ONLY for L3/L4 diffs, by explicit invocation; drives a Workflow (~15× tokens). Escalates risk-review.
effort: high
---

# Deep review (Workflow-driven)

The heavyweight form of `risk-review` for **L3/L4** diffs. It reviews each risk dimension in parallel
and **adversarially verifies every finding**, so only confirmed risks reach the report — no
plausible-but-wrong noise.

## When to use

- **Explicit invocation only**, **L3/L4 only.** For a routine diff use `risk-review` (single pass) —
  say so and stop.
- Drives the `Workflow` tool (~15× tokens) — invoking it is the opt-in.
- **If `Workflow` is unavailable**, fall back to `risk-review`'s single pass and say so.

## How to run

1. Ensure there is a diff (`git diff`) and, if a spec exists, its acceptance-criterion IDs.
2. Run the Workflow in `${CLAUDE_SKILL_DIR}/workflow.md`: per risk dimension, find → adversarially
   verify each finding (≥2 skeptics, refute-by-default) → keep only confirmed; plus a
   `conformance-reviewer` pass on the diff vs the spec criteria. `log()` the dimension count.
3. Present **confirmed** risks (ranked, with file:line) · required approvals · missing / after-the-fact
   tests · suggested fixes · spec-conformance gaps.

## Output

Ranked confirmed risks, each survived adversarial verification, plus spec-conformance gaps. Workers run
via `agentType: "groundwork:<agent>"`. Reference script: `${CLAUDE_SKILL_DIR}/workflow.md`.
