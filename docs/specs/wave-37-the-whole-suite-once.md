# Spec: Wave 37 — the change's own tests while working, the whole suite once before a shared push (groundwork v0.47.0)

- Type: gate behaviour change + a new PreToolUse gate → **L2**.
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-06: *«Почти все сессии запускали полный прогон тестов… это очень долго
  постоянно ждать… может где не нужно, то и не нужно полный прогон запускать?»*
- Decisions taken with the author on 2026-10-06: the whole suite only before a push to a shared branch ·
  wide changes (migrations, config, routes, providers) also targeted while working · parallel full runs
  measured on otaje, then rolled out to every Laravel project.
- Status: **implemented** (2026-10-06).

## What was measured (2026-09-29 – 2026-10-06, all main-session transcripts)

- The Stop gate ran the whole suite **79 times — 383 minutes**, median 322 s, max 1230 s (otaje). It ran it
  on every stop with PHP changed since the last push (`check_unpushed`), whatever the change was.
- Agents ran the whole suite themselves **171 times** (and 747 targeted runs). `final-check` told them to:
  «`--filter=…`, then `composer test`».
- No project's CI runs the tests (otaje, next-lvl-backend, coffee-roasters-back, crm-wigs-back,
  radevs-commerce-core: 0 test steps) — the local full run is the only one, so it cannot be dropped.
- Replayed on otaje's recent PHP commits: the change's own tests were a median of **2 of 647** files (max
  7, one commit touching a widely used model: 106); selection takes 0.1–0.6 s.
- Parallel on an otaje probe lane, the same 4277 tests: **397 s → 203 s** with `--parallel --processes=4`,
  peak lane memory 0.90 → 1.09 GiB, the same 40 failures in the same 7 classes in both runs.

## Changes

- **GW37-AC1** `hooks/test-select.py`: changed test files, plus tests naming a changed class (basename),
  a migration's tables, a config file's `<name>.` keys, a routes file's route names / URIs. "Changed" =
  uncommitted, untracked and unpushed.
- **GW37-AC2** `test-gate.sh` runs that selection (`gates.test_scope: "full"` restores the whole suite;
  a `commands.test` that is not artisan / phpunit / pest still runs whole). Nothing selected → nothing
  run, said on stderr.
- **GW37-AC3** `hooks/suite-record.py`: a green whole-suite run is recorded by the exact tree id
  (`<git-common-dir>/groundwork/suite-passes/`); the gate's own full runs and an agent's (`artisan test` /
  `composer test` with no paths or filter, summary with no failures — PostToolUse) both count.
- **GW37-AC4** `hooks/push-gate.py` (PreToolUse Bash): `git push` to `gates.shared_branches` (default
  development, develop, main, master, staging, production — including `src:dst` specs) and `gh pr merge`
  are refused until the pushed commit's tree has a recorded pass; a feature-branch push is never stopped;
  `gates.full_suite_before_push: false` turns it off.
- **GW37-AC5** `commands.test_full` (optional): the command for a whole run — what the push gate names and
  the full-scope gate runs, e.g. `./vendor/bin/sail artisan test --parallel --processes=4`. `lane.py up`
  grants the lane's DB user `<test db>_test_%` (the per-process databases `--parallel` creates); `down
  --purge` drops them and revokes the grants.
- **GW37-AC6** `final-check`: the change's own tests; no whole-suite run there — it happens once, before
  the shared push.

## Verification

- `hooks/tests/scope.sh` 27 of 27 (selection by class, table, config key, route, changed test; nothing
  selected; full scope; unpushed work covered; push to development / `HEAD:development` / `gh pr merge`
  denied without a pass, allowed after; a feature push allowed; a pass on the working tree counts for the
  commit; the gate's and an agent's green full runs recorded; filtered and red runs not; `test_full`
  named and run; opt-out). All groundwork suites green.
- Not yet measured: the waiting saved in real sessions — read the Stop-hook durations again after a week.
