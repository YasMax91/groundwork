# Spec: Wave 35 — parallel sessions work in lanes and see each other (follow-through v0.2.0 + groundwork v0.45.0)

- Type: plugin feature across both layers — new SessionStart / UserPromptSubmit / PreToolUse / PostToolUse
  / SessionEnd hooks in `follow-through`, a lane provisioning script and two guard changes in groundwork
  → **L3**.
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-05: *«Каждый раз, когда открываю новую сессию проекту, то они начинают
  конфликтовать. Я хочу иметь возможность работать во многих сессиях, чтобы они не ломали друг друга, но
  при этом знали, что происходит друг у друга, чтобы актуальность данных и кода сохранялись»*.
- Decisions taken with the author on 2026-10-05: each lane gets its **own copy** of the dev data ·
  editing a file a live sibling session is editing **stops once and the agent contacts that session** ·
  **all projects**, two layers (registry/awareness/base in follow-through, Docker/DB isolation in
  groundwork for Laravel+Sail) · a lane **starts from the freshest integration branch** (e.g.
  `origin/development`), and a second session in an occupied tree moves into its own lane.
- Added by the author the same day: *«сессии не меняют статус сделанных изменений… Я хочу, чтобы данные и
  знания об этих данных были максимально актуальными»* — decided: keep **plans («Ревизии»), repo
  documents, what is deployed where, and agent memory** current; the source of truth is a **file in the
  repo, mirrored** to the «Ревизия» artifact; updated **in the same turn** as the change.
- Status: **implemented** (2026-10-05), approved by the author the same day; verified live on otaje (see
  **Verification — result**).

## What breaks today

Evidence: ~500 mentions of a sibling session in agent replies across all main-session transcripts
(«соседняя сессия» 107, «параллельная сессия» 69, `deadlock` 33, «чужие изменения/правки/коммиты» 29,
«порт занят / уже занят» 26), plus the state of otaje's 26 worktrees on 2026-10-05.

| # | Failure | Evidence | Root cause |
|---|---|---|---|
| F1 | A lane's `sail` runs the **main checkout's code** | otaje: 15 phpstan errors and 91 failures from another session's promo-code work | 4 of 26 otaje worktrees carry `COMPOSE_PROJECT_NAME=otaje` — the main stack, whose volume is the main checkout |
| F2 | **Shared test DB** collisions | `1213 Deadlock`, `1412 Table definition has changed`, `migrate:fresh` mid-run (otaje, next-lvl, coffee, asg) | one `*_test` DB per project; groundwork's lock lives in `.claude/groundwork/locks/` **inside each worktree**, so worktrees never see each other's lock, and it guards only the Stop gate |
| F3 | **Shared dev DB** data destroyed | an agent deleted `promo-codes.*` permissions as "leftovers" — a sibling's working data | 9 of 26 otaje worktrees use `DB_DATABASE=otaje` |
| F4 | **Same hostname, two stacks** | Traefik alternates requests between `otaje_app` and `otaje_wt4_app` | lanes copy `APP_SLUG`/`APP_DOMAIN` from main |
| F5 | **Two sessions in one tree** | next-lvl, coffee, shlomi, ra-devs: «чужие правки в дереве», a red gate owned by the other session | the second session opened without a worktree; main checkouts sit on feature branches (`chore/docs-ai-portal` in 4 projects) |
| F6 | **Stale base** | gateway lane on `2c103f7` without the needed code; vendor/.env missing in 2 otaje lanes | the app branches a worktree from `origin/HEAD` (`main`/`master`); 6 of 10 projects integrate on `development`; `worktree.baseRef` cannot name a branch (docs: worktrees.md#choose-the-base-branch) |
| F7 | **Dev servers / ports** | tiles: one session stopped the other's API; fam-sync/medai: port 80, 6001 taken | one fixed port per project |
| F8 | **Decisions not shared** | «видимо, это было в другой сессии» (next-lvl) | nothing tells a session what its siblings are doing; the app's `ListAgents`/`SendMessage` exist but nothing prompts their use |

## Layer A — follow-through v0.2.0 (any git project)

**The registry.** One JSON file per live session at
`<git-common-dir>/follow-through/sessions/<session_id>.json` — shared by every worktree of the
repository, never committed (inside `.git`): `session_id`, `title`, `cwd`, `branch`, `base`, `started`,
`heartbeat`, `task` (first 140 chars of the first user prompt), `files` (repo-relative paths edited),
`ports` (declared by the lane). Written by SessionStart, UserPromptSubmit, PostToolUse(Edit|Write|MultiEdit)
and Stop; removed by SessionEnd. A file whose `heartbeat` is older than 30 minutes is not live.

**LN-AC1 — the session knows its siblings.** SessionStart and UserPromptSubmit return
`additionalContext` listing live sibling sessions of the same repository: branch, task, edited-file
count, last activity, and the `ListAgents` name to message. On UserPromptSubmit only when the list or
the base moved since the last injection, so an unchanged state costs nothing.

**LN-AC2 — the base is the freshest integration branch.** The integration branch is
`.claude/follow-through.json` `base_branch`, else `origin/development` when it exists, else
`origin/HEAD`. At SessionStart in a worktree whose branch has **no commits of its own** and a clean tree,
the hook fetches and moves the branch to that base (`git reset --keep <base>`), and says so in context.
A branch with its own commits is never moved.

**LN-AC3 — the base moving is visible.** The awareness block carries "base moved by N commits since this
lane started; M touch files you edited" (`git log <merge-base>..<base>`), with the subjects. Stop blocks
once when M > 0 and the last message claims completion, asking to rebase and re-run the checks.

**LN-AC4 — one session per tree.** When another live session's `cwd` equals this one's, the first
Edit/Write is denied once with: this tree is used by <session> — enter your own lane
(`EnterWorktree`, then the base is corrected by LN-AC2). Reading, answering and planning are not blocked.

**LN-AC5 — overlap stops once and opens a conversation.** PreToolUse(Edit|Write|MultiEdit) on a path
in a live sibling's `files`: denied once with the sibling's branch, task and `ListAgents` name, and the
instruction to `SendMessage` it before proceeding. The same path then passes for this session.

**LN-AC6 — dev servers and ports.** PreToolUse(Bash) asks (native prompt) before `kill`/`pkill`/
`docker stop|compose down` of a process or container that a sibling's registry entry declares in
`ports`/containers. Lanes declare what they start (Layer B writes it; other stacks via
`.claude/follow-through.json` `ports` with an offset per lane).

**LN-AC7 — fail-safe.** Outside git, with an unreadable registry, or on any error: no output. The
registry never blocks a session from starting.

## Layer B — groundwork v0.45.0 (Laravel + Sail)

**GW35-AC1 — a lane provisions its own stack.** `hooks/lane-up.sh` (also exposed as the
`groundwork:lane` skill) in a worktree of a Groundwork project:
- `.env` from the main checkout's, with `COMPOSE_PROJECT_NAME=<project>_<slug>`, `APP_SLUG=<project>-<slug>`,
  `APP_DOMAIN`/`APP_URL` `<project>-<slug>.localhost`, `DB_DATABASE=<db>_<slug>`; `.env.testing` with
  `DB_DATABASE=<db>_test_<slug>`; free ports for anything the compose file publishes;
- databases created on the shared server and the dev DB **cloned** from the main checkout's
  (`mysqldump | mysql` inside the DB container); the test DB migrated fresh;
- `vendor/` and `node_modules/` cloned from the main checkout (`cp -c`, copy-on-write on APFS), then
  `composer install` only if the lock files differ;
- the stack started and its containers/ports written to the registry (LN-AC6).
A `lane-down.sh` stops the stack and drops the lane's databases when the worktree is removed.

**GW35-AC2 — no command reaches another lane's stack.** `pre-tool-guard.sh` denies a runner command
(`sail …`) from a worktree whose `.env` `COMPOSE_PROJECT_NAME` or `DB_DATABASE` equals the main
checkout's (or is missing), with the reason and the command to run (`lane-up`). This is F1 and F3.

**GW35-AC3 — the test-DB lock is shared and complete.** The lock moves to
`<git-common-dir>/groundwork/locks/test-db-<db name>` (keyed by the database, so separate lanes never
wait on each other and the same database is always one lock), and `pre-tool-guard.sh` takes it for the
agent's own `artisan test`, `migrate:fresh|refresh|reset` and `db:wipe` too, not only the Stop gate.

**GW35-AC4 — a refreshed copy on request.** `lane-up.sh --refresh-data` re-clones the dev DB from the
main checkout, so a lane can catch up with data entered elsewhere.

## Layer C — status that does not go stale (follow-through, groundwork for the spec status)

Evidence: «Отметь, что сделано по плану», «меняй состояние плана по-ходу» (budget-hub-api), «сразу
обновляй Ревизия Commerce Core» and the agent asking again whether to update it (radevs-commerce-core),
«api-reference актуальный?» (coffee), «на сервере все актуально?» twice (budget-hub-api), «актуальный ли
код на сервере» (budget-hub). Three live trackers exist only as claude.ai artifacts (Ревизия Commerce
Core, Budget Hub API, админка O.TAJE), which no hook and no sibling session can read.

**ST-AC1 — one status file per repository.** `docs/ai/status.md`: front-matter `mirror: <artifact url>`
(optional) and `environments:` (below); a table per phase — `| ID | Item | Status | Lane | Proof | Updated |`,
status one of `todo · doing · done · blocked · dropped`, proof a commit, PR, test or deploy. A
`follow-through:status` skill creates it — from an existing «Ревизия» by reading the artifact once.

**ST-AC2 — a status event updates the status in the same turn.** A turn that ran `git commit`, `git
merge`, `git push`, a deploy command (ST-AC5), or closed a slice in the groundwork checkpoint, in a
repository that has `docs/ai/status.md`, must also have edited that file — else Stop blocks once:
"N commits this turn, status.md untouched". Escape: a line «статус не меняется: <почему>».

**ST-AC3 — the mirror follows the file.** When `status.md` changed in the turn and declares `mirror:`,
the turn must contain an `Artifact` publish to that URL after the last edit — else Stop blocks once.
The agent no longer asks whether to update the «Ревизия»; it is part of the change.

**ST-AC4 — siblings see each other's status live.** The awareness block (LN-AC1) carries the `doing`
rows of every live lane, read from each sibling's working copy of `status.md` (its `cwd` is in the
registry), not only from the base branch — so a lane's progress is visible before it merges.

**ST-AC5 — what is deployed where.** `status.md` front-matter `environments:` maps each environment to
how its version is read — `branch: origin/staging` (CD from a branch) and/or `version_url:` (a route that
returns the deployed commit) and/or `deploy_cmd:` (a pattern that marks a deploy). PostToolUse(Bash)
records a matching deploy (env, commit, time, session) in `<git-common-dir>/follow-through/deploys.json`.
The awareness block shows each environment's commit and how far it is behind the integration branch;
a deploy is a status event (ST-AC2).

**ST-AC6 — the spec says what happened.** groundwork `slice-gate.sh`: at `Mode: Done`, a spec whose
`Status:` line still reads draft / awaiting / in progress blocks once.

**ST-AC7 — memory that names what no longer exists.** SessionStart scans the project's memory files for
repo paths, class and function names in backticks; any that no longer exist in the tree are listed in
context as "possibly stale — verify and fix or delete in this session". The SessionStart rules add:
a memory fact that the turn's change made wrong is fixed in the same turn. To verify during build: that
worktree sessions resolve to the main repository's memory directory (the 26 otaje worktree project
dirs hold 0 memory files; the main one holds the project's memories).

## Deviations found while building (each one found by the live run, not by the suites)

1. **`phpunit.xml` beats `.env.testing`.** 6 of 10 projects set `DB_DATABASE` in `phpunit.xml`, otaje with
   `force="true"`, so two provisioned lanes still ran on the one `otaje_test` (167 and 123 failures,
   `1213 Deadlock`, `1412`). `lane.py up` now points the lane's working copy of `phpunit.xml` at the
   lane's test DB and marks it `skip-worktree` — never committed; `lane.py down` restores it. The
   test-gate lock reads the database name from `phpunit.xml` first for the same reason.
2. **The test DB must be migrated at provision time.** Unit tests that do not refresh the database
   (otaje: `PromoCodeStackingTest`, `DashboardStatsServiceTest`) relied on the shared test DB having
   tables from earlier runs. `lane.py up` runs `migrate --env=testing` on the lane's test DB.
3. **SQL through `sh -c "…"` executed the backticks** around a database name as command substitution, so
   `CREATE DATABASE` silently did nothing. SQL now goes through stdin.
4. **A re-run must keep the lane's own ports**; it now keeps them, unique per variable.
5. **`.claude/lane.json` would have been committed** in projects that do not ignore `.claude/`; it is
   added to the repository's local `info/exclude`.
6. GW35-AC3's "the guard takes the lock for the agent's own test runs" was not built: a PreToolUse hook
   cannot hold a lock for the duration of a command. Per-lane test databases remove the shared resource
   instead, and `lane-guard` refuses runner commands from an unprovisioned lane.
7. `lane.py down --purge` also removes the lane's Docker volumes (`sail down -v`) — the probe left four
   behind without it — and asks first through follow-through's destructive check.

## Out of scope

- Normalising the 26 existing otaje worktrees (deleting stale ones loses work) — offered separately
  after this ships, worktree by worktree.
- Non-MySQL dev databases (Postgres in asg) for GW35-AC1 — the script reports "clone not supported"
  and provisions an empty migrated DB; Postgres clone next wave.
- Port allocation for non-Docker dev servers beyond declaring them (LN-AC6).

## Verification

- Hook suites: registry write/read/staleness, awareness text, base move only on an empty branch, overlap
  deny-once, one-tree deny-once, freshness Stop, lane-up `.env` rewrite on a fixture project, guard on
  a lane pointing at the main stack, lock path shared across two worktrees of one fixture repo.
- Status: a commit with no status.md edit blocks once; the escape line passes; a status.md edit with a
  `mirror:` and no Artifact publish blocks once; a sibling's `doing` row appears in the other lane's
  context; a deploy command lands in deploys.json; a Done checkpoint with a draft spec blocks.
- Live: two sessions in otaje — one in the main checkout, one in a new lane — run the full suite at the
  same time with no deadlock; each sees the other in its context; an edit to the same file stops once.

## Verification — result (2026-10-05)

- Suites: groundwork 23 of 23 green (new `lane` 27 cases, `test-gate` 22 incl. 2 new, `slice-gate` 49
  incl. 2 new); follow-through 63 of 63 (19 new in `test_lanes.py`, real git repositories).
- Live on otaje, two probe lanes created the way the app creates them (from `origin/main` `a4865d0`):
  both moved to `origin/development` `edd221f` at session start; `sail` refused before provisioning;
  `lane.py up` 20–21 s each, own stack (5 containers each), own domain answering through Traefik (302),
  dev DB cloned, migrations applied. Concurrent run of the same 989 tests in both lanes:
  **989 of 989 passed in each, 0 deadlocks** — before deviations 1–2 the same run gave 167 and 123
  failures. Bravo's session start listed alpha; bravo's first edit of a file alpha had edited was
  denied with alpha's name, the second passed; `docker stop otaje_probealph_app` from bravo asked.
  The main checkout's `.env` and its 5 containers were untouched. Probes torn down: 0 containers,
  0 databases, 0 volumes, 0 registry entries left.
- Not run live: SessionEnd/UserPromptSubmit inside a real app session (the scripts were driven with real
  payload shapes), Layer C against a real «Ревизия» (no project has `docs/ai/status.md` yet — created
  with `follow-through:status` when a project adopts it).

