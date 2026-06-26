---
description: Deep, multi-agent grounding of an external API — fan out cited readers across the docs, build a capability matrix, then an adversarial panel verifies every row. Use ONLY for L3/L4 integrations, by explicit invocation; it drives a Workflow (~15× tokens). Escalates ground-integration.
effort: high
---

# Deep grounding (Workflow-driven)

The heavyweight form of `ground-integration` for **L3/L4 external integrations**. It orchestrates a
multi-agent Workflow so a large or critical API doc is read in parallel and **every capability claim is
adversarially verified** before you trust it. This is the strongest defence against the worst failure
mode — confidently assuming a capability the provider does not have.

## When to use

- **Explicit invocation only**, **L3/L4 only.** For L0–L2 or a quick check, use `ground-integration`
  (single-agent) — say so and stop.
- This skill **drives the `Workflow` tool** (multi-agent, ~15× tokens). Invoking it is the opt-in.
- **If `Workflow` is unavailable** (plan/version), fall back to `ground-integration`'s single-agent
  flow and tell the user — never hard-fail.

## How to run

1. Establish the provider / product / API version, the **list of capabilities** the task needs (one
   row per capability), and the doc **sources** (URLs).
2. Author and run the Workflow in `${CLAUDE_SKILL_DIR}/workflow.md` (adapt `capabilities` + `sources`).
   It (a) fans out one `grounded-researcher` per capability — each returns a cited finding; (b) runs an
   adversarial panel (≥2 `adversarial-verifier` skeptics, distinct lenses, refute-by-default) per row;
   (c) synthesizes the matrix. `log()` the fan-out size so the cost is visible.
3. Present the **capability matrix** — per row: supported? · evidence (URL+quote) · adversarial verdict
   · confidence · fallback — plus the open-unknowns list. Resolve every `UNKNOWN`/REFUTED with the user
   **before** any integration code.

## Output

The verified capability matrix + open unknowns, ready to seed the `integration-change` spec. Label
every row `verified` (survived refutation, with evidence) or `assumed`. Workers run via
`agentType: "groundwork:<agent>"`. Reference script: `${CLAUDE_SKILL_DIR}/workflow.md`.
