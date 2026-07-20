# Working memory (RaDevs) — persist task state, don't re-derive it

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

Keep it **terse** — it is re-injected every session, so every line costs. Template:

```markdown
# Task: <short title>
- Mode: Discovery | Spec | Plan | Implementation | Review
- Level: L0..L4
- Spec: docs/specs/<file>.md | (none yet)
- Impact map: .claude/groundwork/impact/<slug>.md | (n/a)
- OpenAPI: <endpoints this task documents> | n/a — <why the contract is untouched>
- Updated: <YYYY-MM-DD>

## Plan (slices)
- [ ] <slice> — red test: <path> — status: red|green
- [x] <done slice>

## Verified vs assumed
- verified: <fact + evidence>
- assumed: <fact>

## Open unknowns / approvals needed
- <blocking item, or "none">
```

The `OpenAPI:` line is also the **`openapi` Stop gate's escape hatch**: when a task changes the
contract surface (routes, controllers, FormRequests, Resources) the gate demands matching spec
changes, and `n/a — <reason>` is the deliberate, visible way to declare a pure internal refactor.
Never write `n/a` to silence the gate on a real contract change — see
[openapi-protocol.md](openapi-protocol.md).

Who writes it:

- **start-task** — create/overwrite it once the plan is drafted (mode, level, spec path, slice list
  as the red list, assumptions, open approvals).
- **implement-approved** — update it as each slice goes red→green; flip `[ ]`→`[x]` and `red`→`green`.
- **final-check** — on a clean handoff, mark the task done (or delete the file) so the next session
  starts fresh.

## `impact/<slug>.md` — the blast-radius cache

`impact-mapper` is the most expensive fan-out in discovery; do not re-run it when nothing it covers
has changed. Each cache file begins with a header:

```markdown
<!-- BASE_COMMIT: <sha at write time> -->
<!-- SEEDS: app/Services/Foo.php, app/Models/Bar.php, <table/symbol> -->
```

In **start-task** (L2+), before spawning `impact-mapper`:

1. Pick a `<slug>` from the primary seed (e.g. the main model/service/table).
2. If `.claude/groundwork/impact/<slug>.md` exists, **reuse it instead of re-spawning** iff the seeds
   are unchanged since it was written — both must hold:
   - `git diff --quiet <BASE_COMMIT> -- <SEEDS>` (no committed change to the seeds since the cache)
   - `git diff --quiet -- <SEEDS>` (seeds clean in the working tree)
3. Otherwise spawn `impact-mapper`, **overwrite** the cache with its map, and refresh the header
   (`BASE_COMMIT` = current `git rev-parse HEAD`, `SEEDS` = the seeds you mapped).

Run the staleness check through the project runner only if it touches the framework; plain `git`
commands run on the host. When in doubt about coverage, refresh rather than trust a stale map.
