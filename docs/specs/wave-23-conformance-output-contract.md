# Spec: Wave 23 — the conformance reviewer's output becomes a structure the engine checks (v0.33.0)

- Type: plugin self-improvement → **L2** (one hook branch, one matcher, one agent file, seven tests).
- Author: Max Yastremskyi (YasMax91).
- Source: item E30 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). Hook behaviour proven by tests: `agent-contract.sh` 26 cases
  (7 new), 293 across 15 suites, all green.
- Target version: **v0.33.0**.

## Goal

`agents/conformance-reviewer.md:43-46` requires a table (every AC ID → met / partial / unmet →
`file:line`) and a verdict from `CONFORMS | GAPS | INSUFFICIENT`. Both were requirements in a prompt.
Wave 17 moved exactly this class of rule to the engine for two other agents; the third was left out.

## Problem (diagnosis)

The `SubagentStop` matcher at `hooks/hooks.json:36` read
`^groundwork:(grounded-researcher|adversarial-verifier)$` — `conformance-reviewer` was outside it, and
`grep conformance hooks/agent-contract.sh` was empty. The reviewer is the last gate before handoff, and
its table is what the task receipt (wave 24) has to read: free prose there ends the chain, and no
downstream step can recover it.

## Design

The matcher gains the third agent. `hooks/agent-contract.sh` gains a branch with **two distinct
blocks**, so the agent is told which requirement it missed:

- no acceptance-criterion id (`AC-?[0-9]+`) **or** no status word (`met` / `partial` / `unmet`) → the
  table is missing;
- table present, no verdict word → the review ends on nothing.

The patterns are deliberately loose — an id and a status word anywhere in the answer satisfy the first
check. A false block here costs more than a miss: the reviewer runs at the end of a task, and a
legitimate review sent back is work thrown away. Everything else is inherited: `stop_hook_active`
prevents a loop, `gates.agent_contract:false` disables the whole hook, and blocking travels in the JSON
(`decision: "block"`), not in the exit code.

`agents/conformance-reviewer.md` now states that its output shape is checked by the engine and read by
`final-check` — the agent should know the contract is enforced rather than discover it by being blocked.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | A review with no AC rows is blocked | met — `conformance: prose, no table` |
| AC2 | AC ids without a status word are blocked | met — `conformance: ids but no status` |
| AC3 | A table with no verdict word is blocked | met — `conformance: table, no verdict` |
| AC4 | A conforming return passes untouched | met — `table + CONFORMS`, `table + GAPS`, `INSUFFICIENT` |
| AC5 | The re-entry after a block never blocks again | met — `conformance: re-entry never blocks` (`stop_hook_active: true`) |
| AC6 | `gates.agent_contract:false` disables the new branch like the other two | met — inherited from the shared toggle at `agent-contract.sh:21`, covered by `toggle off` |
| AC7 | The whole suite stays green | met — 293 cases, 15 suites |

## Open — human step

Run one real conformance review and check the hook does not block a legitimate answer. The patterns
were chosen to under-block, but only a live review settles it.
