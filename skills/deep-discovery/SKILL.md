---
description: Deep, multi-agent blast-radius discovery — fan out impact-mapper across every seed in parallel, dedup into one map, verify dynamic edges. Use ONLY for L3/L4 changes touching many seeds, by deliberate escalation from `start-task` discovery or by the user; drives a Workflow (~15× tokens). Escalates start-task discovery.
effort: high
---

# Deep discovery (Workflow-driven)

The heavyweight discovery fan-out for **L3/L4** changes that touch many seeds (models / services /
tables). It maps each seed in parallel and consolidates one blast radius, instead of running one
`impact-mapper` at a time.

## When to use

- **Explicit invocation only**, **L3/L4 only.** For L2 use `start-task`'s single `impact-mapper`; for
  L0/L1 a self-trace. Decline politely and point there otherwise.
- Drives the `Workflow` tool (~15× tokens) — invoking it is the opt-in.
- **Reuse the cache first:** honor `.claude/groundwork/impact/<slug>.md` staleness (see
  `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`) — do not re-run if the seeds are unchanged.
- **If `Workflow` is unavailable**, fall back to spawning a single `impact-mapper` (the `start-task`
  flow) and say so.

## How to run

1. List the seeds (models, services, tables, symbols) and pick a `<slug>` from the primary seed.
2. Invoke the `Workflow` tool with `name: "groundwork:deep-discovery-run"` and
   `args: { seeds: [...], integration: "<provider or null>" }`. The shipped script fans out one
   `impact-mapper` per seed (plus a `grounded-researcher` when an external API is involved), dedups into
   one blast radius with ranked hotspots, then verifies the dynamic edges. Do **not** rewrite it inline.
   It refuses to run without `seeds`, and it logs both the seed count and any edges left unchecked.
3. Write the consolidated map to `.claude/groundwork/impact/<slug>.md` and refresh the
   `BASE_COMMIT` / `SEEDS` header (working-memory layer).

## Output

One blast-radius map · ranked hotspots · checked dynamic-edge findings · a ranked read-list · open
questions. The workflow returns `seedCount`, `mappedSeeds`, `failedSeeds`, `edgesFound` and
`edgesVerified`, so the map is reported with its coverage — a seed that failed to map and an edge left
unchecked are named, never folded into the total.

Workers run via `agentType: "groundwork:<agent>"`. Script: `workflows/deep-discovery-run.js` in the
plugin root, also runnable directly as `/groundwork:deep-discovery-run`.
