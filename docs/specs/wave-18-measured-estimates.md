# Spec: Wave 18 — an estimate is a measurement, not an opinion (v0.28.0)

- Type: plugin self-improvement. Adds a measurement mechanism, one skill, one warn-only gate, and
  rewrites the calibration rule four documents depend on → **L3** (cross-cutting change to when and
  from what an estimate is produced).
- Author: Max Yastremskyi (YasMax91).
- Source: author feedback (2026-08-27), not an audit. One statement: agents still return human-shaped
  numbers — "6 hours for a CRUD" — and correcting them by hand yields a smaller number of the same
  wrong kind. Wave 13 already declared the unit; the complaint is that the declaration did not move
  the number.
- Status: **implemented** (2026-08-27). 46 new hook tests, 261 across all suites, green. Verification is
  **mixed**: AC1–AC6 and AC10–AC13 are proven by executable tests against synthetic transcripts; AC7,
  AC9, AC14 and AC15 are **structural only** — the rules are in the files that own them and no
  behavioural run has been recorded yet. The ledger was seeded on this machine: 562 `commit-window`
  rows, median **12** active minutes per window across all projects (16 in `crm-wigs-back`, p75 27–40).
  Two defects were caught by the tests before shipping, both of the class this plugin exists to remove:
  `jq`'s `// empty` treats `false` as absent, so the `estimates.ledger` opt-out silently did nothing;
  and the backfill piped its commit list into a command whose stdin was already owned by a heredoc,
  so it read an empty log and wrote nothing while appearing to succeed.
- Target version: **v0.28.0**

## Goal

Wave 13 replaced the human coefficients with prose and a calibration procedure. The unit changed, the
number did not. Wave 18 replaces the prose with **a measured corpus of this author's own agent time**,
puts it in front of the model at the four points where a duration leaves the system, and logs every
hour-shaped answer so the false-positive rate is readable before anything blocks.

## Problem (diagnosis)

Each point verified against the source, not assumed.

### A. The rule never reaches the moment the number is born

`§Estimates` lives in `guidelines/ai-sdd-process.md` and is pulled in by exactly one skill:

```
$ grep -rn "estimate" skills/start-task/SKILL.md skills/spec/SKILL.md
(no matches)
```

`client-doc` is the only consumer. The three other places where a duration reaches the author carry no
rule at all: a plain "how long will this take?" in chat, a duration mentioned while a plan is approved,
and the closing report — which never states what the work actually took.

The `task-intent` hook does not close the gap either. It fires on task **verbs**
(`GW_TASK_VERBS_RU` / `_EN`) and exits on question openers; "сколько это займёт" matches neither list,
so a direct question about a deadline receives no Groundwork context whatsoever. The model answers from
its pretraining prior, and that prior is denominated in developer hours.

### B. The calibration procedure measures a different clock

`§Estimates` instructs:

```bash
git log --format='%ad %s' --date=format:'%Y-%m-%d %H:%M' --since='2 months ago'
```

and calls the gap between consecutive commits "the real cost of that slice". It is not. It is the rhythm
at which a human presses commit. Measured on `crm-wigs-back`, 2026-08-20: four commits at `12:59`,
`13:00`, `13:01`, `13:01` (a merge batch — near-zero gaps for real work), and a single 60-minute gap
`11:59 → 12:59` that covers writing one spec. The procedure therefore produces both noise and
hour-sized intervals, and the hour-sized ones **confirm** the inflated estimate instead of refuting it.

### C. Removing the anchor did not remove anchoring

Wave 13 deleted the 1–2.5 h / 3–5 h coefficients because they were human coefficients wearing a new
label. Correct, and incomplete: nothing measured took their place. An estimate is an anchoring task; with
no anchor in context the anchor is supplied by the prior. "Normally minutes" as prose loses to a prior
trained on human engineering estimates every time.

### D. Nothing records what the work actually took

Every other rule in this plugin that survived contact with real use has a mechanism behind it —
`test-gate`, `openapi-gate`, `coverage-claim`. Estimates have exhortation only. Worse: the actual
duration is never written down anywhere, so no estimate has ever been checked against its outcome, and
`§Estimates` itself warns that an unconfirmed prior estimate is "an input, not an authority" while
providing no way to ever confirm one.

## Measurement — binding on the design

The data already exists. Every event in `~/.claude/projects/<slug>/*.jsonl` carries a `timestamp`.
Active agent time is the sum of inter-event gaps below an idle threshold; gaps above it are the human
reading, deciding, or away.

Measured across every project transcript ≥ 50 KB, idle threshold 120 s, n = 293 sessions:

| corpus | n | median active | p75 | p90 | max |
|---|---|---|---|---|---|
| all projects | 293 | **30 min** | 59 min | 126 min | 445 min |

Per project (n ≥ 4), median active minutes against the median calendar span of the same sessions:

| project | n | median active | median span |
|---|---|---|---|
| next-lvl-backend | 56 | 38 | 119 |
| coffee-roasters-back | 53 | 41 | 82 |
| crm-wigs-back | 53 | 23 | 80 |
| maxsterling-back | 25 | 12 | 50 |
| shlomi-mor-wigs-back | 24 | 13 | 25 |
| groundwork | 14 | 21 | 54 |
| budget-hub-api | 11 | 126 | 369 |
| crm-wigs-ai-gateway | 8 | 32 | 101 |
| ra-devs-laravel-back | 6 | 17 | 54 |

Three findings bind the design:

1. **A whole working session is a median of 30 active minutes.** "6 hours for a CRUD" is roughly twelve
   medians of an entire session for one endpoint.
2. **Calendar span overstates work by ~3×** (80–119 min span against 23–41 min active). Any estimate
   derived from wall-clock-between-events, including the current `git log` procedure, inherits that
   factor.
3. **Worktree sessions live in sibling directories** (`…-crm-wigs-back--claude-worktrees-<name>`), 14 of
   40 project directories. Without collapsing them into the parent, `crm-wigs-back` reports a fraction
   of its 53 sessions and the per-project median is computed from the wrong sample.

## Design — per item

### A1 — The ledger script

`hooks/estimate-ledger.sh` — three modes, no dependency beyond `jq`/`python3` already required by the
existing hooks, silent and exit-0 on every failure like every other hook.

- `--record` — called by `final-check`. Resolves the transcript directory for the current project,
  takes the window `[Started, now]` from `.claude/groundwork/task-state.md`, sums inter-event gaps
  ≤ `estimates.idle_seconds`, appends one row.
- `--report [--kind=<k>] [--level=<L>]` — prints median, p75, n for the current project and for the
  whole corpus, per `source`.
- `--backfill` — walks every directory containing `.groundwork.json`, segments history by commit
  windows, appends rows marked `source=commit-window`.

Row format, tab-separated, appended to `~/.claude/groundwork/estimates.tsv`:

```
finished_at  project  level  kind  slug  active_min  calendar_min  promised_min  source  branch
```

**Only durations and identifiers are written. No transcript content ever enters the ledger.**

### A2 — The task window

`task-state.md` gains `Started: <ISO-8601>`, written when the checkpoint is created, documented in
`guidelines/working-memory.md` next to `Mode:` and `Level:`. `final-check` closes the window. A
checkpoint without `Started:` is skipped by `--record`, never guessed.

### A3 — Backfill, and why its rows are marked

The chosen unit is one Groundwork task, which only exists going forward. `--backfill` supplies a corpus
today by segmenting on commit windows — a different, noisier unit (see §B). Rows carry
`source=commit-window`; medians are computed **per source** and `source=task` is preferred whenever
n ≥ 5. Mixing the two silently would reproduce the defect this wave exists to remove.

### A4 — Worktree collapse

The project key strips the `--claude-worktrees-<name>` suffix, so a worktree session counts toward its
parent project.

### A5 — Configuration

`.groundwork.json` gains, all defaulting to on/120/5 when absent:

```json
"estimates": { "ledger": true, "idle_seconds": 120, "min_sample": 5 }
```

`gates.estimate_claim: true` joins the existing `gates` block.

### B1 — The `estimate` skill

New skill `estimate`, whose description triggers on a duration question in either language ("сколько
времени", "сроки", "оценка", "how long", "when will it be ready"). It runs `--report`, and its output
carries, mandatorily:

- the number, in the agent's active minutes, per block of work and as a total;
- the measured median and **the sample size it rests on**;
- human time on its own line, never added in;
- a calendar date only if asked, as agent time plus the named human waits.

When n < `min_sample` for the relevant slice, the skill says the sample is too small and names what it
fell back to. It does not silently produce a confident number from three rows.

### B2 — `§Estimates` rewritten

The `git log` calibration is removed as the primary procedure and demoted to an explicitly-labelled
coarse fallback for a repository with an empty ledger, carrying the warning from §B that it measures
commit rhythm and overstates by roughly 3×. The measured medians and the ledger take its place. The
existing rules that hold — human time on its own line, estimate the delta not a rewrite, no false
precision, no padding — are kept verbatim.

### B3 / B4 — The other three exits

`client-doc` §Estimating references the measured median instead of commit intervals. `start-task` and
`spec` each gain one line: any duration mentioned in a plan or a spec goes through `§Estimates`, and at
L2+ it carries its median and sample size.

### C1 — The gate, warn-only

`hooks/estimate-claim.sh`, Stop, modelled directly on `coverage-claim.sh` — same four-list structure,
same `stop_hook_active` guard, same log-before-notice discipline, same silent no-op when
`.groundwork.json` is absent or the gate is off.

- **Markers**: an hour/day-shaped duration in an estimating context — `\b\d+([.,]\d+)?\s*(h|hrs?|hours?)\b`,
  `\b\d+\s*(ч|часа?|часов)\b`, `\b\d+\s*(дн(я|ей|ями)?|days?)\b`, `man-day`, `человеко-`.
- **Exonerating evidence in the same message**: a named slow cause (external API, sandbox probe, waiting
  on a person, a migration over a large table), or a separate human-time line, or the duration being
  reported as an *actual* rather than an estimate.
- **Action**: `systemMessage` naming the measured median for this project, plus one line appended to
  `.claude/groundwork/estimate-claims.log`. **It never blocks in v0.28.0**, exactly as `coverage-claim`
  did not in v0.24.0. The log is what decides whether a later wave turns blocking on.

### D1 — The feedback loop

`final-check` calls `--record`, and its handoff summary gains one line: **what was promised and what it
took**. Without this the ledger stays empty of `source=task` rows, and a miss stays invisible.

### Deferred, deliberately

- Blocking on an hour-shaped estimate. Not until the log shows the false-positive rate.
- Estimating per work-kind (CRUD vs integration vs migration) from the ledger. The `kind` column is
  written from v0.28.0 so the data accumulates, but medians are reported per level until the per-kind
  sample clears `min_sample`.
- Any cross-machine or shared corpus. The ledger is local.

## Acceptance criteria (EARS)

- [x] **W18-AC1** WHEN `final-check` completes at L1+, THE ledger SHALL gain one row carrying active
      minutes, calendar minutes, level, kind, and source for that task. → check: hooks/estimate-ledger.sh ·
      skills/final-check/SKILL.md · hook test
- [x] **W18-AC2** THE ledger SHALL contain durations and identifiers only, and no transcript content.
      → check: hooks/estimate-ledger.sh · hook test
- [x] **W18-AC3** THE project key SHALL collapse `--claude-worktrees-<name>` into the parent project.
      → check: hook test with a synthetic worktree directory
- [x] **W18-AC4** THE active-time computation SHALL sum inter-event gaps ≤ `estimates.idle_seconds`
      (default 120) and SHALL NOT use the calendar span. → check: hook test with a fixture transcript
      containing a known idle gap
- [x] **W18-AC5** WHEN `task-state.md` carries no `Started:`, THE `--record` mode SHALL skip the task
      and SHALL NOT infer a start time. → check: hook test
- [x] **W18-AC6** THE `--backfill` mode SHALL mark its rows `source=commit-window`, and `--report`
      SHALL compute medians per source, preferring `source=task` when its n ≥ `estimates.min_sample`.
      → check: hooks/estimate-ledger.sh · hook test
- [x] **W18-AC7** *(structural)* WHEN a duration is stated at L2+ in chat, a plan, a spec, or a client document, THE
      statement SHALL carry the measured median and its sample size. → check: skills/estimate/SKILL.md ·
      guidelines/ai-sdd-process.md · skills/start-task/SKILL.md · skills/spec/SKILL.md ·
      skills/client-doc/SKILL.md
- [x] **W18-AC8** WHEN the relevant sample is smaller than `estimates.min_sample`, THE estimate SHALL
      say so and name its fallback. → check: skills/estimate/SKILL.md
- [x] **W18-AC9** *(structural)* THE `git log` interval procedure SHALL NOT be the primary calibration, and where it
      remains it SHALL be labelled coarse and SHALL carry the ~3× overstatement warning. → check:
      guidelines/ai-sdd-process.md
- [x] **W18-AC10** WHEN the final message states an hour- or day-shaped estimate with no named slow
      cause and no separate human-time line, THE Stop hook SHALL emit a notice naming the measured
      median, at most once per turn. → check: hooks/estimate-claim.sh + hook test
- [x] **W18-AC11** WHEN `stop_hook_active` is true, THE hook SHALL return an empty object and emit
      nothing. → check: hook test
- [x] **W18-AC12** THE hook SHALL NOT block in v0.28.0 and SHALL append one line per trigger to a log
      readable as a false-positive rate. → check: hooks/estimate-claim.sh + hook test
- [x] **W18-AC13** WHEN `.groundwork.json` is absent OR `gates.estimate_claim` is false OR
      `estimates.ledger` is false, THE corresponding mechanism SHALL be a silent no-op. → check: hook test
- [x] **W18-AC14** *(structural)* WHEN implementation completes, THE handoff summary SHALL state the promised duration
      against the actual one. → check: skills/final-check/SKILL.md
- [x] **W18-AC15** *(structural)* THE reported duration SHALL be the agent's active time, and human time SHALL remain
      a separate line that is never added into it. → check: guidelines/ai-sdd-process.md ·
      skills/estimate/SKILL.md

## Risks / assumptions

- **Transcript schema drift.** The parser reads `timestamp` from each line and tolerates unknown record
  types. A version whose records lack `timestamp` yields no rows rather than wrong rows — verified
  against the current corpus (293 sessions parsed).
- **Transcripts can be pruned.** The ledger accumulates independently in `~/.claude/groundwork/`, so
  deleting `~/.claude/projects` costs future measurement, not the corpus already recorded.
- **The 120 s idle threshold is a choice, not a measurement.** It separates "the agent is running" from
  "the human is reading". It is configurable, it is recorded per row implicitly by the corpus it
  produced, and changing it invalidates comparisons across rows — a change therefore requires a
  backfill, not a silent edit.
- **A regex over natural language has false positives.** This is why the gate is warn-only and why the
  log exists; the same reasoning Wave 14 recorded for `coverage-claim`.
- **The corpus is one author's.** It is exactly the right corpus for this author's estimates and would
  be wrong to ship as defaults for anyone else. Nothing measured here enters the plugin as a constant.

## Plan

1. `hooks/estimate-ledger.sh` — `--record`, `--report`, `--backfill`; worktree collapse; config keys;
   fixture-based hook tests (AC1–AC6, AC13).
2. `task-state.md` `Started:` field + `guidelines/working-memory.md` (AC5).
3. `skills/estimate/SKILL.md` (AC7, AC8, AC15).
4. `guidelines/ai-sdd-process.md` §Estimates rewrite (AC9, AC15); one line each into `start-task` and
   `spec`; `client-doc` §Estimating pointed at the ledger (AC7).
5. `hooks/estimate-claim.sh` + registration in `hooks/hooks.json` + tests (AC10–AC13).
6. `skills/final-check/SKILL.md` — record the actual, report promised-vs-actual (AC1, AC14).
7. Run `--backfill` once to seed the corpus; run `hooks/tests/all.sh`; bump to v0.28.0; README line.
