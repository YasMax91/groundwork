# Working memory (Groundwork) — persist task state, don't re-derive it

Cheap, durable memory for the workflow so the **context window stays light but nothing is
forgotten** across stops, restarts, and compaction. Read together with
[ai-sdd-process.md](ai-sdd-process.md). The skills write these files; the plugin's `SessionStart`
hook re-injects them automatically (no re-reading), and `PreCompact` marks the checkpoint as the
source of truth before the transcript is thinned.

## Where state lives

All under `.claude/groundwork/` in the project (git-ignored by default — it is working memory, not a
deliverable; a team may un-ignore `impact/` to share the discovery cache):

- `task-state.md` — one active task at a time. Overwrite when a new task starts.
- `impact/<slug>.md` — cached blast-radius map per area (see below).

Honor the `.groundwork.json` `memory` toggles: `checkpoint` and `impact_cache` (both default `true`).
If a toggle is `false`, skip that mechanism silently.

## `task-state.md` — the checkpoint

Keep it **terse** — it is re-injected every session, so every line costs. **Close it when the work
ships**: set `Mode: Done — <what shipped>`, and the `SessionStart` hook stops injecting the body and
leaves a one-line pointer instead (measured: ~1100 tokens down to ~180 on every session in that
project). Any of the five working modes keeps the full injection, because a task you are still in is
exactly what the checkpoint exists to restore. Template:

```markdown
# Task: <short title>
- Mode: Discovery | Spec | Plan | Implementation | Review | Done — <what shipped>

- Level: L0..L4
- Kind: <one word: crud | integration | migration | bugfix | contract | rbac | ...>
- Started: <YYYY-MM-DDTHH:MM:SSZ — set once, when the checkpoint is created>
- Spec: docs/specs/<file>.md | (none yet)
- Impact map: .claude/groundwork/impact/<slug>.md | (n/a)
- OpenAPI: <endpoints this task documents> | n/a — <why the contract is untouched>
- Updated: <YYYY-MM-DD>

## Plan (slices)
- [ ] <slice> — red test: <path> — status: red|green
- [x] <done slice>

## Decisions
- <decision> — <option the user chose> — <YYYY-MM-DD>

## Verified vs assumed
- verified: <fact + evidence>
- assumed: <fact>

## Open unknowns / approvals needed
- <blocking item, or "none">
```

**Write what is true, not what the slice was aiming at.** The `SessionStart` hook re-injects this file
verbatim, so an overstatement is not a note — it is the next session's premise. "Asserted on
`POST /orders`; `PATCH /orders/{id}` not covered" beats "asserted on both endpoints"; a slice is `green`
only when its test passes **now**; `verified` requires the evidence to exist, everything else is `assumed`.
A checkpoint that rounds coverage up is how work gets declared done twice and finished once.

`Started:` and `Kind:` exist for the **estimate ledger**. `final-check` closes the window and records
how long the task actually took, in the agent's active minutes, so later estimates rest on measurement
rather than on a prior trained on human engineering hours (`hooks/estimate-ledger.sh`,
[ai-sdd-process.md](ai-sdd-process.md) §Estimates). Two rules: **`Started:` is written once, in UTC,
when the checkpoint is created, and is never edited afterwards** — a corrected start time is a
corrected measurement — and a checkpoint without it is skipped by the ledger rather than having a start
inferred from a file's mtime, which would produce a number that looks measured and is not. `Kind:` is
one word and free-form; it is what will eventually let an estimate say "a CRUD endpoint here is
typically N minutes" instead of quoting the level's median.

The `OpenAPI:` line is also the **`openapi` Stop gate's escape hatch**: when a task changes the
contract surface (routes, controllers, FormRequests, Resources) the gate demands matching spec
changes, and `n/a — <reason>` is the deliberate, visible way to declare a pure internal refactor.
Never write `n/a` to silence the gate on a real contract change — see
[openapi-protocol.md](openapi-protocol.md).

Who writes it:

- **start-task** — create/overwrite it once the plan is drafted (mode, level, spec path, slice list
  as the red list, assumptions, open approvals), and record every interview answer under
  `## Decisions`. Read that section before asking anything — a decision the user already made is never
  re-asked, whatever the transcript lost (see [clarify-protocol.md](clarify-protocol.md)).
- **implement-approved** — update it as each slice goes red→green; flip `[ ]`→`[x]` and `red`→`green`.
- **final-check** — on a clean handoff, mark the task done so the next session starts fresh. **Deleting
  the file is only safe once the change is committed** (or if it never touched the contract surface): the
  `openapi` Stop gate reads the `OpenAPI:` line from here against the *uncommitted* working tree, so an
  early deletion destroys the exemption the task declared and blocks its own "done".

## `impact/<slug>.md` — the blast-radius cache

`impact-mapper` is the most expensive fan-out in discovery; do not re-run it when nothing it covers
has changed. Each cache file begins with a header:

```markdown
<!-- BASE_COMMIT: <sha at write time> -->
<!-- SEEDS: app/Services/Foo.php, app/Models/Bar.php, <table/symbol> -->
```

In **start-task** (L2+), before spawning `impact-mapper`:

1. Pick a `<slug>` from the primary seed (e.g. the main model/service/table).
2. If `.claude/groundwork/impact/<slug>.md` exists, **reuse it instead of re-spawning** iff **all three**
   hold:
   - `git diff --quiet <BASE_COMMIT> -- <SEEDS>` (no committed change to the seeds since the cache)
   - `git diff --quiet -- <SEEDS>` (seeds clean in the working tree)
   - the cached `SEEDS` still **cover the seeds of the work at hand** — every file, model, table, or
     symbol this work touches is already in the header.

   The third condition closes a hole the first two cannot see: they prove the mapped seeds did not
   *change*, never that they are still the *right* ones. A new sub-request introduces seeds absent from
   `SEEDS:`, so both `git diff` checks pass while the map covers none of the new work.
3. Otherwise spawn `impact-mapper`, **overwrite** the cache with its map, and refresh the header
   (`BASE_COMMIT` = current `git rev-parse HEAD`, `SEEDS` = the seeds you mapped).

Run the staleness check through the project runner only if it touches the framework; plain `git`
commands run on the host. When in doubt about coverage, refresh rather than trust a stale map.

## Parallel sessions — one worktree is one workspace

Two sessions in the same checkout share more than files: they share the **test database**, the working
tree, and this checkpoint. The symptoms are recognisable and waste real time — a suite that fails with
`1412 Table definition has changed` then `1146 doesn't exist` (another session ran `migrate:fresh`
mid-run), fixtures overwritten under a running test, an `openapi` gate firing on a **different** session's
uncommitted controller, and a `task-state.md` describing someone else's task.

What the plugin does: the test gate takes an exclusive lock (`.claude/groundwork/locks/test-db`) around the
suite, so parallel runs queue instead of corrupting each other. If the lock cannot be had within
`gates.test_lock_wait_seconds` (default 45), the gate **skips and says so** rather than reporting a red
that belongs to no one. Opt out with `gates.test_db_lock: false`.

What it cannot do, so it is a practice rather than a rule: **give each parallel session its own git
worktree** (`git worktree add ../<repo>-<task> -b <branch>`). A plugin cannot create or police worktrees,
and the lock only protects the suite — the shared working tree and the shared checkpoint still belong to
whoever writes last.
