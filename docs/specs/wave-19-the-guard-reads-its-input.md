# Spec: Wave 19 — the access hook stops switching itself off (v0.29.0)

- Type: plugin self-improvement → **L2** (one hook, three test suites, no methodology change).
- Author: Max Yastremskyi (YasMax91).
- Source: item E26 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). Proven by tests: 15 suites, all green; `run.sh` 32 cases
  (7 new), `trim-output.sh` 9 cases and `pre-compact.sh` 8 cases are new files.
- Target version: **v0.29.0**.

## Goal

`pre-tool-guard.sh` is the plugin's only PreToolUse denial: it keeps Laravel/PHP commands inside the
runner and refuses edits to a shipped migration. On a machine without `jq` both rules were silently
off. Make the hook read its input without `jq`, and make it say so when it cannot read it at all.

## Problem (diagnosis, reproduced before the fix)

`pre-tool-guard.sh:30` read `tool_name` through `jq` with no `command -v jq` guard — seven other hooks
have one (`agent-contract.sh:20`, `coverage-claim.sh:40`, `estimate-claim.sh:42`, `task-intent.sh:25`,
`estimate-ledger.sh:31,294`, `lib.sh:20`). Without `jq` the variable was empty, so the `case` fell to
its catch-all `*) exit 0` and **allowed everything**: `php artisan migrate` ran against the host `.env`
instead of the container, and a committed migration could be edited without a word.

This is the failure mode the plugin sells against — `guidelines/ai-sdd-process.md:218`, "a gate that did
not run has verified nothing" — inside the gate itself.

## Design

**`GW_PARSER` + `gw_get` / `gw_conf` (in the hook, not in `lib.sh`).** `jq` when present, `python3`
otherwise — already a dependency of `hooks/estimate-ledger.sh`, so no new requirement appears. The
helpers stay local to this file on purpose: `hooks/tests/failsafe.sh` proves every hook survives a
missing `lib.sh`, and moving them there would trade a real guarantee for tidiness.

All seven `jq` call sites now go through the helpers: `tool_name`, `tool_input.command`,
`tool_input.file_path`/`.path`, and the three `gates.*` toggles.

**`// empty` is not used.** jq's alternative operator also fires on a literal `false`, which would read
`gates.enforce_runner: false` as absent and switch a deliberately disabled gate back on. The helper
reads the raw value and treats only `null` as absent. This was caught by the existing
`AC3 toggle_off no-op` case, which failed on the first draft of this wave.

**Neither parser → allow, but never in silence.** After the `.groundwork.json` project gate the hook
prints to stderr that the runner lock and the shipped-migration lock did not run, then exits 0. Chosen
over `exit 2` deliberately: a machine with neither `jq` nor `python3` would otherwise have every Bash
call blocked by a condition the agent cannot fix. Outside a Groundwork project the hook stays silent,
as before.

**Two hooks got their first tests.** `trim-output.sh` rewrites what the agent sees, so its promises are
the test: opt-in only, never trim a failure, never trim what it cannot positively locate, keep the tail.
`pre-compact.sh` appends a breadcrumb to the checkpoint, so the test is that it lands, carries the
trigger, and does not stack duplicates.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | With `jq` off `PATH`, `php artisan migrate` under `runner=sail` is denied (exit 2) | met — `W19 nojq runner_deny` (before this wave the same input exited 0) |
| AC2 | With `jq` off `PATH`, editing a committed migration is denied | met — `W19 nojq migration` |
| AC3 | With `jq` off `PATH`, `gates.enforce_runner:false` is still honoured | met — `W19 nojq toggle off` |
| AC4 | With neither parser: exit 0 **and** non-empty stderr naming what did not run | met — `W19 no parser speaks` |
| AC5 | With neither parser and no `.groundwork.json`: silent, exit 0 | met — `W19 no parser quiet` |
| AC6 | `bash hooks/tests/all.sh` runs 15 suites, all green | met — `lib run test-gate gates openapi-gate coverage-claim estimate-ledger estimate-claim task-intent agent-contract statusline session-start trim-output pre-compact failsafe` |
| AC7 | `failsafe.sh` covers 14 hooks including `trim-output` and `pre-compact` | met — 15 cases, all green |

## Deliberately not done

- **`exit 1` in the Stop gates when git is missing** (the original E26 pitch). Only `exit 2` blocks; any
  other code produces a transcript notice and the action proceeds. Stop fires on every turn, so a
  git-less project would collect three notices per turn with no opt-out.
- **Calling `estimate-ledger.sh --record` from a `Mode: Done` checkpoint.** `hooks/lib.sh:15` does not
  contain `Done`, so the trigger would be dead code. The mismatch with
  `guidelines/working-memory.md:23,30` is a real bug and is filed on its own, not built on.
- **Hoisting shared helpers into `lib.sh`** — see above.
