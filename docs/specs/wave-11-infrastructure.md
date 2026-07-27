# Spec: Wave 11 — infrastructure & hook bugs (plugin v0.16.0)

- Type: plugin self-improvement — **shell hooks + one shared library + tests**, plus a small prose pass.
  The only wave in the feedback programme that ships executable code → **L3** (a denying hook can strand
  the workflow).
- Author: Max Yastremskyi (YasMax91). Owner: RaDevs.
- Source: **Part C** of the session-mined complaint brief for the v0.12.0 window — parallel sessions
  sharing one test DB, an over-stating checkpoint, a brittle `Mode:` parser, `runner: host` ignored, and
  the OpenAPI generation step silently no-opping. Final package of the
  [feedback programme](plugin-enhancement-roadmap.md), after Waves
  [8](wave-8-live-verification.md) / [9](wave-9-audience-and-language.md) / [10](wave-10-process-depth.md).
- Status: **implemented & verified** (2026-07-27) — 102 hook tests across 7 suites. Two blocking defects
  were found by the adversarial review *after* the first implementation and are fixed and
  regression-tested: a false red on an unreachable host command, and a project template that pinned the
  gates to Sail. Authorised to run without a per-wave gate; the isolation mechanism was settled the same
  day as **lock + documentation**.
- Target version: v0.16.0

## Goal

The methodology waves fixed what the agent does. Wave 11 fixes the machinery underneath it, where the
failures were not judgement calls but bugs: a project that declares `runner: host` is still forced through
Sail, a checkpoint written in non-canonical prose silently disables a gate, and two parallel sessions
running the suite against one test database produce falsely-red gates (`1412 Table definition has
changed` → `1146 doesn't exist`) that cost real debugging time.

## Problem (diagnosis)

Confirmed by reading the hooks — the brief's Part C, corrected where it was imprecise:

1. **`runner` is declared and never honored — in any gate.** `.groundwork.json` carries `"runner"`
   (`templates/project/.groundwork.json:2`) and `session-start.sh:18` is the **only** hook that reads it
   (to print it). Every gate hardcodes a Sail default: `test-gate.sh:8`, `done-gate.sh:8`,
   `format-on-edit.sh:17`, `openapi-gate.sh:106`. Each can be worked around by filling in every
   `commands.*` by hand — except **`pre-tool-guard.sh:38`**, which has no override at all: it keys the
   runner enforcement purely on `[ -x ./vendor/bin/sail ]` and will deny host `php`/`composer`/`artisan`
   in a project that explicitly declared `runner: host`. That is the bug in its pure form.
2. **The same root silently disables the OpenAPI generation check.** `openapi-gate.sh:106-111` defaults
   `gen` to Sail and skips generation when Sail is absent. On a `runner: host` project the command is
   never reachable, so the "does the spec still generate cleanly?" half never runs. Precision the brief
   lacked: the gate does **not** go fully silent — the "surface changed but the spec did not" block
   (`:90-102`) always fires. Only the generation step no-ops.
3. **The `Mode:` parser accepts anything.** Three hooks extract it with the same fragile pipeline —
   `session-start.sh:52`, `statusline.sh:25`, `pre-tool-guard.sh:76-77` — taking the first whitespace-run
   after the colon with **no validation against the canon** `{Discovery, Spec, Plan, Implementation,
   Review}` and no stripping of Markdown emphasis. A checkpoint reading `- Mode: **COMMITTED**` yields the
   literal `**COMMITTED**`: the status line and banner render garbage, and `lock_edits_in_discovery` — the
   one hard gate keyed on mode — silently matches nothing.
4. **Nothing serialises access to the test database.** `test-gate.sh:42` runs the suite unconditionally
   whenever PHP changed. Two sessions in the same worktree (the brief's repeated `next_level_test` case)
   interleave `migrate:fresh` and a running suite, producing failures that describe neither session's
   code. There is no lock of any kind in the plugin.
5. **The checkpoint invites overstatement.** `guidelines/working-memory.md:22-46` prescribes a terse
   template but says nothing about the *accuracy* of what is written, so "asserted on both endpoints" gets
   recorded when one was covered — and, because `SessionStart` re-injects the file verbatim
   (`session-start.sh:36-40`), the overstatement becomes the next session's premise.
6. **Not reproduced — do not "fix".** The brief's "status line pinned to 0.9.0": there is **no version
   string anywhere in `hooks/`**. Treated as already fixed; recorded so it is not re-litigated.
7. **Found by the new tests, absent from the brief: the test and analysis gates miss a brand-new PHP
   directory.** `test-gate.sh:17` and `done-gate.sh:17` detect changed PHP with `git status --porcelain`,
   which reports an untracked **directory** as itself (`?? app/Services/`) and never lists the files
   inside it. A task whose only PHP lands in a new directory — a new `app/Services/`, a new
   `app/Http/Resources/` — therefore skipped both gates silently. `openapi-gate.sh:33-35` already carries
   the `-uall` fix and the comment explaining it; the other two never got it. Folded into this wave: same
   class of bug, same one-flag fix.

## Boundaries — what may and may not block

The plugin's existing philosophy is absolute and Wave 11 keeps it: **a gate blocks on a real defect, never
on an environment problem.** Every new path here fails open.

| Situation | Behavior |
|---|---|
| tests fail / analysis fails / contract undocumented | **block** (exit 2) — unchanged |
| Sail down, no git repo, missing config, unparsable field | allow (exit 0) — unchanged |
| **test DB busy with another session** (new) | wait, then **allow with a stated reason** — never a falsely-red gate |
| **`runner: host`** (new) | run the host command; the runner guard does not deny |
| **non-canonical `Mode:`** (new) | treat as unknown → the edit-lock does not fire (fail-open), the UI shows `—` |

## Design — per item

### C1 — one shared resolver: `hooks/lib.sh`

A tiny sourced library holding the two things three-to-five hooks each re-derive, so a fix lands once:

- `gw_cmd <tool> [args]` — builds the gate command for the configured runner (`.runner`, default
  `sail`): `gw_cmd artisan test` → `./vendor/bin/sail artisan test` or `php artisan test`.
  **Revised during implementation** (the red test caught it): a plain "prefix" is wrong, because the host
  forms genuinely differ per tool — `php artisan`, not `artisan`; `./vendor/bin/pint`, not `pint`. The
  resolver is per-tool for exactly that reason.
- `gw_runner_ready` — true when the resolved runner can actually be invoked (for `sail`, the binary
  exists and is executable; for `host`, always true). Replaces the bare `[ -x ./vendor/bin/sail ]` checks.
- `gw_mode` — extracts `Mode:` from the checkpoint, strips Markdown emphasis (`*`, `_`, backticks) and
  surrounding whitespace, and **validates case-insensitively against the canon**
  `{Discovery, Spec, Plan, Implementation, Review}`, echoing the canonical spelling or **nothing**.

Sourcing is itself fail-safe: hooks resolve the library relative to their own path and continue with their
current hardcoded defaults if it is missing or unreadable. A broken library must not break a hook.

### C2 — `runner: host` honored everywhere (bug 1 + bug 2)

- `pre-tool-guard.sh` — when the resolved runner is `host`, the runner enforcement (a) is a **no-op**; a
  project that declares `runner: host` may run host `php`/`composer`/`artisan`. The shipped-migration lock
  (b) and the discovery edit-lock (c) are unaffected.
- `test-gate.sh`, `done-gate.sh`, `format-on-edit.sh`, `openapi-gate.sh` — defaults built from
  `gw_cmd`; the availability check becomes `gw_runner_ready`, **but only for a default the resolver
  built** — an explicit `commands.*` override keeps its old semantics (AC13). On a `runner: host` project
  the OpenAPI generation step therefore **runs** instead of silently skipping, closing bug 2 through the
  same root. Explicit `commands.*` overrides keep winning over both.

### C3 — a test-database lock (settled: lock + documentation)

`test-gate.sh` serialises the suite across sessions with an **atomic `mkdir` lock** (`flock` is absent on
macOS, the author's platform) at `.claude/groundwork/locks/test-db`:

- acquired before the suite, released on exit via `trap`; the lock records an **owner id** (`$$`) and the
  trap removes it **only if we still own it** — otherwise a slow session would delete a lock another
  session had legitimately taken over;
- **busy → wait** (poll up to `gates.test_lock_wait_seconds`, default **45**) — the other session's run is
  finite, and waiting is what prevents the interleaving in the first place;
- **still busy at the timeout → allow the stop with a stated reason on stderr** (exit 0). A gate that
  could not run is an environment problem, not a defect: never a falsely-red result;
- **stale lock** — older than a **fixed 30 minutes**, deliberately *not* derived from the wait window: a
  suite legitimately longer than the wait must never have its own lock declared stale and stolen;
- **unmanageable lock → run unlocked, and say so.** If the lock cannot be created (permissions, read-only
  FS) or a stale one cannot be removed, the gate proceeds without it instead of retrying — a hook that
  spins is the failure mode this wave exists to prevent;
- toggle `gates.test_db_lock` (default **true**), opt-out like every other gate.

**Wait window vs the harness hook timeout.** The default is 45 s so the "waited, then explained" path
completes inside a conservative hook timeout; a longer window risks the harness killing the hook before it
can report anything. Whether `hooks.json` accepts a per-hook `timeout` field is **UNKNOWN — not verified
against the documentation in this wave**, so no such field is written; raising
`test_lock_wait_seconds` past the harness limit is documented as the user's call.

`guidelines/working-memory.md` and `README.md` document the complementary practice the plugin cannot
enforce: **a git worktree per parallel session**, since a plugin cannot create or police worktrees and
declaring otherwise would be a rule with no mechanism.

### C4 — a checkpoint that does not overstate

`guidelines/working-memory.md` gains an accuracy rule: **write what is actually true, not what the slice
was aiming at.** "Asserted on `POST /orders`; `PATCH /orders/{id}` not covered" rather than "asserted on
both endpoints"; a slice is `green` only when its test passes now. The file is re-injected verbatim into
the next session, so an overstatement is not a note — it is a false premise the next session inherits. Ties
to the Wave 8 rule that unverified work is stated as unverified.

### C5 — tests first, then rollout

Every change above is proven by a case in `hooks/tests/`, written before the fix (the plugin's own
red→green rule applies to its own shell): new `hooks/tests/lib.sh` (the resolver's units) and
`hooks/tests/test-gate.sh` (lock behaviour), plus new cases in the existing `run.sh` (host runner, mode
canon) and `statusline.sh` (mode canon). A single entry point `hooks/tests/all.sh` runs every suite —
today the four files must each be invoked by hand.

`.claude-plugin/plugin.json` → `0.16.0`; `templates/project/.groundwork.json` gains `test_db_lock` and
`test_lock_wait_seconds`; `README.md` documents the new toggles and the worktree practice; the roadmap
marks Wave 11 shipped and the programme complete.

## Acceptance criteria (EARS)

- [x] **W11-AC1** WHEN `.groundwork.json` declares `runner: host`, THE `pre-tool-guard` hook SHALL NOT
      deny host `php`/`composer`/`artisan`/`phpunit`/`pest`, AND SHALL keep denying them when the runner is
      `sail` and available. → check: hooks/pre-tool-guard.sh + hooks/tests/run.sh
- [x] **W11-AC2** WHEN the runner is `host`, THE gate commands in `test-gate`, `done-gate`,
      `format-on-edit`, and `openapi-gate` SHALL default to un-prefixed host commands and SHALL NOT skip on
      a missing Sail binary; an explicit `commands.*` override SHALL still win.
      → check: hooks/*.sh + hooks/tests/
- [x] **W11-AC3** WHEN the runner is `host` and the contract surface changed with annotations updated,
      THE OpenAPI generation step SHALL actually run rather than silently no-op.
      → check: hooks/openapi-gate.sh + hooks/tests/openapi-gate.sh
- [x] **W11-AC4** THE `Mode:` value SHALL be accepted only when it matches
      `{Discovery, Spec, Plan, Implementation, Review}` case-insensitively after stripping Markdown
      emphasis; a non-canonical value (`**COMMITTED**`) SHALL yield no mode — the discovery edit-lock does
      not fire and the status line shows the neutral placeholder.
      → check: hooks/lib.sh + hooks/pre-tool-guard.sh + hooks/statusline.sh + hooks/session-start.sh
- [x] **W11-AC5** WHEN a `- Mode: **Discovery**` checkpoint is written with Markdown emphasis, THE parser
      SHALL still recognise `Discovery`. → check: hooks/tests/run.sh + hooks/tests/statusline.sh
- [x] **W11-AC6** WHEN the test gate runs while another session holds the test-database lock, THE gate
      SHALL wait up to the configured window, THEN allow the stop with a stated reason (exit 0) rather than
      reporting a failure; AND it SHALL release its lock on exit and take over a stale one.
      → check: hooks/test-gate.sh + hooks/tests/test-gate.sh
- [x] **W11-AC7** THE lock SHALL be opt-out via `gates.test_db_lock` and its wait window configurable via
      `gates.test_lock_wait_seconds`, both present in the project template.
      → check: hooks/test-gate.sh + templates/project/.groundwork.json
- [x] **W11-AC8** THE shared library SHALL be sourced fail-safe — a missing or unreadable `lib.sh` SHALL
      leave every hook working on its current defaults. → check: hooks/*.sh + hooks/tests/lib.sh
- [x] **W11-AC9** THE working-memory guideline SHALL require the checkpoint to state what is actually
      covered rather than what the slice aimed at, AND SHALL document the per-session git-worktree practice
      as a practice the plugin cannot enforce. → check: guidelines/working-memory.md
- [x] **W11-AC10** EVERY change above SHALL carry a test case in `hooks/tests/`, AND a single entry point
      SHALL run all suites. → check: hooks/tests/all.sh + hooks/tests/*
- [x] **W11-AC11** `.claude-plugin/plugin.json` SHALL be `0.16.0`; `README.md` SHALL document the new
      toggles and the worktree practice; AND the roadmap SHALL record Wave 11 and the programme's
      completion. → check: .claude-plugin/plugin.json + README.md + plugin-enhancement-roadmap.md
- [x] **W11-AC12** THE test and analysis gates SHALL detect PHP inside a brand-new untracked directory
      (`git status --porcelain -uall`), so a change whose only PHP lands in a new directory cannot skip
      them silently. → check: hooks/test-gate.sh + hooks/done-gate.sh + hooks/tests/test-gate.sh

Added after the first conformance review, which found each of these breaking or unproven:

- [x] **W11-AC13** WHEN an explicit `commands.*` override is configured, THE gate SHALL run it and check
      only *its* Sail dependency — never the configured runner's — so a project that pointed a gate
      elsewhere keeps working. → check: hooks/test-gate.sh + hooks/done-gate.sh + hooks/format-on-edit.sh
      + hooks/openapi-gate.sh + hooks/tests/gates.sh
- [x] **W11-AC14** WHEN the lock can neither be created nor cleared, THE gate SHALL run unlocked with a
      stated reason and SHALL NOT spin or hang. → check: hooks/test-gate.sh + hooks/tests/test-gate.sh
- [x] **W11-AC15** THE lock SHALL carry an owner id and THE release SHALL remove it only while still
      owned, so a lock belonging to another live session is never deleted.
      → check: hooks/test-gate.sh + hooks/tests/test-gate.sh
- [x] **W11-AC16** THE fail-safe behaviour of AC8 SHALL itself be covered by an automated suite that
      hides `lib.sh` and asserts every hook still runs and still enforces its rules.
      → check: hooks/tests/failsafe.sh

Added after the adversarial review, which found the wave had introduced a *new* way to strand the
workflow — the exact failure the gates' own headers promise never to cause:

- [x] **W11-AC17** WHEN a gate command cannot run at all (undefined command, missing binary, container
      down), THE test and analysis gates SHALL treat it as an environment problem and allow the stop with
      a stated reason — never as a red. Before this wave the Sail-only default made that path impossible;
      honoring `runner: host` created it. → check: hooks/test-gate.sh + hooks/done-gate.sh + hooks/tests/gates.sh
- [x] **W11-AC18** THE shipped project template SHALL NOT pin `commands.*` to Sail, since an explicit
      override wins over the runner (AC13) and a pinned template would make `runner: host` inert for every
      project created from it. → check: templates/project/.groundwork.json + hooks/tests/gates.sh

## Risks / assumptions

- **A denying hook is the highest-risk surface in the plugin (primary).** Wave 2 shipped `pre-tool-guard`
  with 15 test cases for exactly this reason. Mitigation: every branch keeps its fail-open default, the
  full suite must stay green, and the runner change only ever *removes* a denial (a `host` project stops
  being blocked) — it cannot introduce a new one.
- **The lock could strand a session.** A crashed run leaving a lock directory behind would block the gate
  forever. Mitigated by stale-lock takeover, the bounded wait, and the exit-0-with-reason timeout — the
  worst case is a gate that did not run and said so, which is the pre-Wave-11 status quo.
- **Waiting adds latency to the Stop gate.** Accepted: the wait only happens when another run is genuinely
  in flight, which is precisely when running now would produce a meaningless result.
- **A sourced library is a new failure mode.** Mitigated by AC8 — hooks must work with it deleted — and by
  keeping it to three pure functions with no side effects.
- **Assumption.** The atomic-`mkdir` lock is sufficient for same-machine parallel sessions. It does not
  coordinate across machines or containers; the documented worktree practice covers what it cannot.

## Rollout

- Version **v0.16.0**. Behavior-changing for hooks — the release note must flag that a `runner: host`
  project is no longer denied host commands, and that the test gate may now wait.
- Commit (single line, no AI attribution):
  `fix: v0.16.0 — honor runner:host across gates, canonical Mode parsing, test-DB lock for parallel sessions`.

## Verification plan

Write the failing cases first, then the fixes. Run **all** hook suites via `hooks/tests/all.sh` — the
pre-existing 15 `pre-tool-guard` cases must stay green (no regression) alongside the new ones. Inspect each
file against W11-AC1–AC11 and run `conformance-reviewer` on the diff.
