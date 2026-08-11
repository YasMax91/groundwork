# Spec: Wave 15 — static analysis that actually runs (v0.25.0)

- Type: plugin self-improvement → **L2** (one gate, one skill step, three prose files).
- Author: Max Yastremskyi (YasMax91).
- Source: research item E11 in [modernization-research-2026-08.md](modernization-research-2026-08.md),
  found by reading a live project's own configuration rather than by an audit of the plugin.
- Status: **implemented** (2026-08-11). Gate behaviour proven by 5 new tests (30 in the `gates` suite,
  170 across 9 suites, all green); the `init` step and the prose are structural.
- Target version: **v0.25.0**.

## Goal

The Definition of Done promised a static-analysis step that, on at least one real project, could not
run and reported success anyway.

## Problem (diagnosis)

Read from `next-lvl-backend/.groundwork.json` on 2026-08-11:

```json
"analyse": "echo 'no static-analysis tool configured (see CLAUDE.md) — no-op override for the ra-devs done-gate'",
"analyse_on_stop": false
```

Two distinct failures sit in those two lines.

1. **A no-op passes as a clean run.** `echo` exits 0. Had the toggle been on, `done-gate.sh` would have
   run the placeholder, seen status 0, and allowed the Stop — reporting a clean static-analysis run for
   a project with no analyser installed. The gate could not tell a passing analyser from a command
   whose only job is to exit 0.
2. **The opt-out is silent.** With `analyse_on_stop: false` the gate returned 0 before looking at
   anything, so a change to a hundred PHP files produced no analysis and no mention of its absence,
   while the L2+ Definition of Done kept listing "static analysis run" among the things that make a task
   done.

Neither is a project misconfiguration to be scolded; the project did the only thing available to it.
The plugin offered no way to say "we have no analyser" that was not a lie or a silence.

## Design

### A — A declared no-op is not a pass

`hooks/done-gate.sh` inspects the first word of the resolved analyse command. `echo`, `true`, `:` and
`printf` are no-ops: the gate refuses to run them, reports that nothing was analysed, and exits 1 (the
plugin's "did not run, and said so" code — never 2, because a missing analyser is not a red analysis).
Matching is on the first word only, so `./echoes.sh` is a real command and runs.

### B — An opt-out states its reason

The `analyse_on_stop: false` check moves **after** the changed-PHP check, so a disabled gate stays
completely silent on a change with no PHP in it. When PHP did change:

- `gates.analyse_skip_reason` present → silent. The project made a decision and recorded it.
- absent → one line on stderr saying changed PHP was not analysed, exit 1. Not a block.

### C — `init` stops creating the situation

New step 8: detect an analyser; if absent, offer Larastan with a level the existing code can hold and a
generated baseline so the gate judges new code. Writing a placeholder into `commands.analyse` is named
as forbidden, with the reason. A decline is recorded as `analyse_on_stop: false` **plus**
`analyse_skip_reason`.

### D — The Definition of Done stops overclaiming

`ai-sdd-process.md` L2+: where format or analysis was skipped, the **report** carries the reason, not
only the config — a gate that did not run has verified nothing, whatever its exit code.
`laravel-standards.md` documents the honest opt-out next to the tool itself.

## Acceptance criteria (EARS)

- [x] **W15-AC1** WHEN `commands.analyse` resolves to a no-op (`echo`/`true`/`:`/`printf`), THE gate
      SHALL NOT run it, SHALL report that nothing was analysed, and SHALL exit 1. → check:
      hooks/tests/gates.sh (`echo`/`true`/`colon`/leading-space cases)
- [x] **W15-AC2** WHEN a command merely contains a no-op word (`./echoes.sh`), THE gate SHALL run it
      normally. → check: hooks/tests/gates.sh
- [x] **W15-AC3** WHEN the gate is off AND no PHP changed, THE gate SHALL stay silent. → check:
      hooks/tests/gates.sh
- [x] **W15-AC4** WHEN the gate is off AND PHP changed AND no `analyse_skip_reason` is set, THE gate
      SHALL report the unanalysed change and exit 1. → check: hooks/tests/gates.sh
- [x] **W15-AC5** WHEN `analyse_skip_reason` is set, THE gate SHALL stay silent. → check:
      hooks/tests/gates.sh
- [x] **W15-AC6** THE `init` skill SHALL offer an analyser when none exists, SHALL forbid a placeholder
      command, and SHALL record a decline as toggle + reason. → check: skills/init/SKILL.md
- [x] **W15-AC7** THE Definition of Done SHALL require a skipped gate's reason in the report. → check:
      guidelines/ai-sdd-process.md
- [x] **W15-AC8** THE README and Laravel standards SHALL document the honest opt-out. → check:
      README.md · guidelines/laravel-standards.md

## Risks / assumptions

- **This turns a previously silent configuration into a reported one.** A project running with
  `analyse_on_stop: false` and no reason will start seeing one line per Stop that touches PHP. That is
  the intended cost: it is the shortest path to either an analyser or a recorded reason, and it stops
  at once when either lands.
- **The no-op list is deliberately short.** A shell function or an alias that exits 0 is not detected.
  The gate catches the placeholder people actually write, not every possible way to fake a pass.
- **Existing projects are not migrated.** `.groundwork.json` files in other repositories are theirs;
  the plugin reports and offers, and does not edit them. `next-lvl-backend` in particular needs either
  Larastan or a recorded reason, and that is the author's call per project.
