# Spec: Wave 27 — the standards know which Laravel they are talking about (v0.37.0)

- Type: plugin self-improvement → **L2** (one guideline, one hook branch, six tests, three skill
  descriptions).
- Author: Max Yastremskyi (YasMax91).
- Source: the gap named in [market-scan-2026-08-27.md](market-scan-2026-08-27.md) ("the standards lag
  the stack they claim") that fell out of the E26–E34 sequencing, plus one of the separate bugs listed
  there.
- Status: **implemented** (2026-08-27). Hook behaviour proven by tests: `session-start.sh` 15 cases
  (6 new), 313 across 15 suites, all green.
- Target version: **v0.37.0**.

## Problem (diagnosis)

`guidelines/laravel-standards.md` named no framework version and no PHP version — `grep -cE 'Laravel
1[0-9]'` returned 0. The agent reading it therefore wrote code from training memory, on a page whose
whole purpose is to replace guessing. Meanwhile Laravel 12 left its bug-fix window on **2026-08-13**,
fourteen days before this wave: a project on it now receives security patches and nothing else, and
nothing in the plugin said so.

## Design

**A resolved baseline, not a hardcoded one.** The standards file says the versions come from
`composer.lock` and Boost `application-info`, and carries the official support table verbatim from
[laravel.com/docs/releases](https://laravel.com/docs/releases) **with the date it was checked** and an
instruction to re-read the source if that date is far behind. Copying a table without a checked-on date
is how a document starts lying quietly.

**One notice per session, only when a date has actually passed.** `hooks/session-start.sh` reads the
locked `laravel/framework` version, maps the major to its bug-fix end date, and speaks only when today
is past it. An unknown major, an unreadable lock file, a missing `jq` — all silence. "Q3 2027" for
Laravel 13 is stored as its conservative end, `2027-09-30`.

**Three descriptions stop overstating.** `deep-discovery`, `deep-grounding` and `deep-review` described
themselves as "by explicit invocation" while the model can invoke them like any other skill. The fix is
the wording, not the manifest: `skills/start-task/SKILL.md:44`, `skills/ground-integration/SKILL.md:11`,
`skills/risk-review/SKILL.md:16` and `guidelines/ai-sdd-process.md:137` all instruct the model to
escalate into them, so `disable-model-invocation: true` would break the documented escalation path. The
descriptions now say "by deliberate escalation from <the skill that escalates> or by the user".

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | The standards name the framework and PHP versions and their source | met — a Framework baseline section with the support table, the source URL and the checked-on date |
| AC2 | A project on Laravel 12 is told once per session | met — `L12 is past bug fixes` |
| AC3 | A project on the current major is not | met — `L13 is current, no notice` |
| AC4 | An unknown major, a missing lock, or a broken lock stays silent | met — three cases; and the hook's JSON output stays valid |
| AC5 | The deep skills' descriptions match what the manifest actually permits | met — three descriptions reworded; no `disable-model-invocation` added, and the reason is recorded above |
| AC6 | The suite stays green | met — 313 cases, 15 suites |

## Deliberately not done

- **`disable-model-invocation: true` on the deep skills** — see above; it would break four documented
  escalation paths.
- **Reading the support dates at runtime.** It would put a network call in `SessionStart`. The dates
  live in two places (the guideline and the hook), both carrying the same checked-on date, and both are
  refreshed together.
