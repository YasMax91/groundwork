# Spec: Wave 38 — the close tests while working, the change's tests before a push, the whole suite only when something shared changed (groundwork v0.48.0)

- Type: gate behaviour change (Stop test gate, push gate) + a test runner → **L3** (it decides what reaches a
  shared branch untested).
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-21: *«стало лучше, но все равно запускается полный прогон тестов, когда не
  надо»*.
- Decisions taken with the author on 2026-10-21: the whole suite only when something shared changed or the
  last green whole run is older than a day; otherwise the tests of everything that changed since the last
  verified code · paratest in otaje.
- Status: **implemented** (2026-10-21).

## What was measured (2026-10-06 12:17 UTC – 2026-10-21, 783 transcripts, groundwork 0.47.0)

- **Stop gate.** 436 stops checked tests; 54 actually ran some; 30 of those took ≥ 5 min (268 min in
  total), 12 reached the 10-minute hook limit and verified nothing. Median of the 54: 386 s. All in otaje.
- **Why the selection is wide.** Replayed on otaje's 81 PHP commits since 2026-10-06 against its 849 test
  files: median 62 files, p75 395, p90 679, max 791; 36 commits select ≥ 100 files. A routes file
  contributes every URI and name in the file, not the changed ones (`product` 418 files, `order` 346,
  `update` 233); a PHP file that is not a class contributes its basename (`bootstrap/app.php` → `app`, 257;
  `lang/vendor/backpack/*/custom.php` → `custom`, 141; `lang/*/validation.php` → `validation`); a central
  model's name is in almost every test (`Product`, 381).
- **A tighter selection, replayed on the same commits** (prototype): tests named after the changed class,
  tests naming the class *and* a method changed on the diff's lines, route names/URIs/controllers on changed
  lines, changed config/lang keys, changed tests → median 5, p75 22, p90 86, max 195 (6 commits ≥ 100).
  Adding the tests that merely name the class or a migration's table/columns → median 15, p75 178, p90 424.
- **Whole-suite runs by agents in otaje:** 51 episodes in 37 sessions, ~1049 min, median 17 min. The suite
  grew from 4542 to 5944 tests in the period and no longer fits one 10-minute Bash call, so agents split it
  by hand into 3–5 folder chunks — which `suite-record.py` never records.
- **Push gate:** 56 denials (53 otaje) in 31 sessions; 15 AskUserQuestions to the owner about recording a
  pass by hand. Two causes: a lane's `phpunit.xml` is skip-worktree with the lane's DB name, so the tree id
  built with `git add -A` never equals the commit's; and a docs-only commit needs a whole run again — 96 of
  the 180 non-merge commits on otaje's development since 2026-10-06 changed only `docs/` or `*.md`.
- otaje tests that read documents: 5 files (`DocsPortalTest`, `KitContractTest`, `StoreReservationContractTest`,
  `ImagePresetSlotTest`, `LegalPagesDescribeVisitsTest`).
- otaje has no `brianium/paratest` (the 2026-10-06 rollout stopped after the measurement: 397 s → 203 s on
  4 processes, the same failures). PCOV is enabled in its Sail image (not used by this wave).

## Changes

- **GW38-AC1 — selection in two circles** (`hooks/test-select.py`, `--json` prints
  `{"close": [...], "wide": [...], "shared": [...]}`; the plain output stays the close circle):
  - *close*: changed tests; tests whose file name carries the changed class's basename; tests naming the
    class and a method or constant changed on the diff's lines; for a routes file, the route names, URIs and
    controller classes on changed lines; for config and lang files, the changed keys (`<file>.<key>`); for a
    document, the tests that read its path (literal or glob); for a test trait or helper under `tests/`,
    the tests using it; for a factory or seeder, the tests naming its model or class.
  - *wide*: tests naming a changed class at all; a migration's tables and the columns on its changed lines.
  - *shared* (the whole suite is the only honest check): `composer.json`, `composer.lock`, `phpunit.xml*`,
    `.env.testing`, `tests/TestCase.php`, `tests/CreatesApplication.php`, `bootstrap/**`, `app/Providers/**`,
    `app/Http/Kernel.php`, `app/Console/Kernel.php`, `app/Exceptions/Handler.php`, `config/app.php`,
    `config/database.php`, `config/auth.php`, a migration that alters, renames or drops a table it did not
    create, and a routes line that changes a middleware, prefix or group.
  - Words that name nothing on their own are never needles: < 4 characters, and `index`, `show`, `store`,
    `update`, `destroy`, `create`, `edit`, `list`, `data`, `item`, `value`, `name`, `type`, `status`, `search`.
  - A shared file selects no close test of its own (the whole suite checks it; `tests/TestCase.php` would
    otherwise select every test). A needle found in more than 5 % of the tests (at least 20 files) goes to
    the wide circle, one needle at a time — found by the first replay of the real module, where a migration
    column (`position`), a common seeder and a central model's family of test names (`Product*Test`, 70-90
    files) each pulled 50-470 files into the close circle.
  - Replay on the same 81 otaje commits is part of the verification: close median ≤ 10 and p90 ≤ 100.
- **GW38-AC2 — the Stop gate runs the close circle within a budget** (`hooks/test-gate.sh`):
  `gates.test_budget_seconds` (default 180). Files are ordered changed tests → name match → method match →
  the rest of the close circle and taken while their recorded durations (AC4) fit the budget (1.5 s per file
  without a record). What did not fit is named on stderr and left to the push check, never dropped silently.
  The run is stopped at twice the budget (never past 540 s), the container's test process with it, and the
  gate says what was not verified — the harness's silent 10-minute kill no longer happens.
- **GW38-AC3 — a pass is remembered per file and per exact code** (`hooks/suite-record.py`): green targeted
  runs record their test files against the tree id — the gate's own runs and an agent's
  `artisan test <paths>` (PostToolUse; `--filter` runs are not recorded). The Stop gate and the push check
  skip files already green on this tree.
- **GW38-AC4 — durations per test file**: every run the plugin makes writes a JUnit log under the project's
  git-ignored `storage/framework/testing/` and folds it into `<git-common-dir>/groundwork/test-durations.json`;
  the log is removed after.
- **GW38-AC5 — a lane's run is the commit's run**: the tree id takes skip-worktree files from the index, so a
  green run in a lane with its own `DB_DATABASE` in `phpunit.xml` counts for the commit. The hand record and
  the `phpunit.xml` swap the otaje memories describe stop being necessary.
- **GW38-AC6 — the push check asks only for what changed since verified code** (`hooks/push-gate.py`,
  `gates.full_suite_before_push`: `"when-needed"` default, `"always"` = the 0.47.0 behaviour, `false` = off):
  - a *verified tree* is a tree with a green whole run, or one that this check accepted; each carries the
    time of the whole run at the root of its chain;
  - for the pushed commit, take the verified tree whose diff to it is smallest among those whose root is at
    most `gates.full_suite_max_age_hours` (default 24) old; none → the whole suite;
  - that diff touches a *shared* file → the whole suite; otherwise the close and wide circles of that diff
    must be green on the pushed tree (AC3); an empty selection passes (a docs-only commit whose documents no
    test reads needs no run);
  - an accepted push records its tree as verified; `gh pr merge` is checked the same way.
  - The denial names one command: `test-run.py --for-push <ref>` (AC7), to be started in the background.
- **GW38-AC7 — one runner** (`hooks/test-run.py`): `--close` (what the Stop gate would run, for an agent
  while working), `--for-push <ref>` (exactly what AC6 requires), `--whole`. A whole run uses
  `commands.test_full` when set (parallel); otherwise it splits the test files into chunks of ≤ 480 s by
  recorded duration and runs them in one process, so it must be started with `run_in_background`. Files that
  fail only with a lost database connection (`SQLSTATE[HY000] [2002]`, `2006`) are re-run once. It holds the
  test-database lock for the whole run, with a label the Stop gate prints instead of "another session".
  Results are recorded by AC3/AC6; it prints `RECORDED <tree>` or `NOT RECORDED: <n> failed`.
- **GW38-AC8 — the agents follow the same rules** (`skills/final-check`, `skills/implement-approved`,
  `guidelines/tdd-protocol.md`, the session-start line): while working, the change's own file or
  `test-run.py --close`; no hand-picked folders as a regression sweep (the push check runs the wide circle);
  the whole suite only through `test-run.py`, only when the push check asks.
- **GW38-AC9 — otaje runs in parallel**: `brianium/paratest` as a dev dependency and
  `commands.test_full: "./vendor/bin/sail artisan test --parallel --processes=4"`, from a lane, through the
  new push check. Accepted only if the parallel run fails exactly the tests the serial run fails.
- **GW38-AC10 — the 2026-10-06 `lane.py` fixes land as their own commit**: the test database named from
  `phpunit.xml` when there is no `.env.testing`, and the stack's start errors shown without compose
  warnings (uncommitted in the main checkout since 2026-10-06).

## Verification

- `hooks/tests/scope.sh` extended: each close/wide/shared rule above, the generic-word list, the budget
  (ordering, deferral named, the stop at twice the budget), per-file records (gate run, agent run, `--filter`
  not recorded), the lane tree id, the push check (docs-only with and without a test reading it, a shared
  file, a stale root, a chain of two pushes, a merge onto a moved branch, `"always"`, `false`), the runner's
  chunking and its 2002 re-run. All groundwork suites green.
- Replay of AC1 on the 81 otaje commits, numbers in the commit message.
- otaje: one whole run through `test-run.py --whole` serial and one parallel; failures compared file by file.
- A week after release: Stop-hook durations, whole-suite episodes and push denials recounted with the same
  scan as above.

## Result (2026-10-21)

- **Selection, replayed on otaje's 79 PHP commits since 2026-10-06 at their own trees** (`gw_tests.select` on
  `TreeDiff(parent, commit)`): close circle median **11** (target ≤ 10 — missed by one), p75 36, p90 **53**
  (≤ 100), max 107; one commit ≥ 100 files. Before: median 62, p90 679, max 791, 36 commits ≥ 100. Close + wide
  (what the push check runs): median 64, p90 486. 22 of 79 commits change a shared file — 20 of them a
  migration that alters an existing table. Selection takes a median 2.4 s per commit.
- Three rules came from replaying the real module, not from the prototype: a shared file selects no close
  test (`tests/TestCase.php` alone pulled 3322 picks into 12 commits); a needle in > 5 % of the tests goes
  wide; a controller's routes are close only for a changed action a route names (it was 35 % of all close
  picks), migration columns are wide (13 %), and a test "reads" a file only through a quoted path in its code
  (a spec named in comments pulled 100 tests).
- **otaje, lane `paratest-parallel`**, `brianium/paratest` ^7.8 added: `test-run.py --whole` serial — 6081
  tests green in 3 parts (788 + 421 + 224 s, the machine busy with twelve mapping agents); parallel
  (`commands.test_full`, 4 processes) — the same 6081 green, 288 s. Both recorded by the runner, no hand record.
- A session restart mid-run killed the host-side runner while the suite went on in the container, holding the
  lock: both gates now take over a lock whose holder process is gone and stop what it left in the container.
- Suites: `scope.sh` 89 of 89, `test-gate.sh` 23 of 23, `lane.sh` 33 of 33; all groundwork suites green.

## Not in this wave

- An execution map (which code each test runs, from PCOV during whole runs) as the selection's source:
  revisit after a week of AC1–AC2, with the misses the push check catches as the measure.
- Running the whole suite on GitHub after a push.
