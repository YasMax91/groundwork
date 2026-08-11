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
2. Invoke the `Workflow` tool with `name: "groundwork:deep-review-run"`. Optional `args`: `scope` (what
   to review, default the working diff) and `criteria` (where the acceptance-criterion IDs live). The
   script ships with the plugin — do **not** rewrite it inline; it holds the dimension list, the
   two-lens adversarial panel, and the conformance pass, and it logs its own fan-out.
3. Present **confirmed** risks (ranked, with file:line) · required approvals · missing / after-the-fact
   tests · suggested fixes · spec-conformance gaps.

## Output

Ranked confirmed risks, each survived adversarial verification, plus spec-conformance gaps. The
workflow returns `examined` and `dropped` alongside `confirmed`, so the report states its denominator —
"12 findings examined, 5 confirmed, 7 dropped as false alarms" — rather than an unquantified list, per
`${CLAUDE_SKILL_DIR}/../../guidelines/writing-standards.md`.

Workers run via `agentType: "groundwork:<agent>"`. Script: `workflows/deep-review-run.js` in the plugin
root, which is also runnable directly as `/groundwork:deep-review-run` when you want the orchestration
without this skill's level gating.
