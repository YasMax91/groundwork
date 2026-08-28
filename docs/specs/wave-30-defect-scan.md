# Spec: Wave 30 — the defects that a rule forbade and prose did not prevent (v0.40.0)

- Type: plugin self-improvement → **L3** (a new blocking gate, one gate promoted from warning to
  refusal, a session notice, 21 tests).
- Author: Max Yastremskyi (YasMax91).
- Source: an audit of this author's eleven Groundwork projects on 2026-08-27 — eight mechanical checks
  per project, every hit read in the code before it was called a finding.
- Status: **implemented** (2026-08-27). Proven by tests: `defect-scan.sh` 16 cases (new),
  `test-gate.sh` 20 (5 new), 335 across 16 suites, all green.
- Target version: **v0.40.0**.

## What the audit found, and what it did not

Verified defects, each one already forbidden by a rule that nothing enforced:

| Defect | Where | Why it matters |
|---|---|---|
| `Mail::to()->send()` inside `DB::transaction` | `next-lvl-backend`, 2 services | A rollback does not un-send an invoice |
| `env()` in application code | `crm-wigs-back` ×3, `fam-sync` ×2 | Returns `null` after `config:cache` — works locally, silently not in production |
| A broadcast event dispatched inside a transaction without `ShouldDispatchAfterCommit` | `fam-sync`, `TaskDeleted` | Two sibling events in the same codebase have it; this one does not, and `after_commit` is `false` |
| Money as `double` | `crm-wigs-back`, `wigs.totalPrice`, `payments.amount` | The standards' oldest rule, in a payments table |
| A suite on in-memory SQLite while the project targets MySQL | `maxsterling-back`, `next-lvl-backend-wt-resend`, `fam-sync` | The standards call this a false green; the gate had been warning about it, unread |
| `Model::preventLazyLoading()` enabled | nowhere — 0 of 11 projects | An N+1 does not fail; it ships |

Equally important, what the first version of the audit **wrongly** flagged, and why the checks below are
shaped to stay quiet on it: ten of eleven "dispatch inside a transaction" hits in `fam-sync` were events
implementing `ShouldDispatchAfterCommit` (the grep looked for a literal `afterCommit`); the raw-SQL hits
in three projects interpolate column names the method builds itself, not user input; and "35 controllers
with no `authorize()`" was authorization living in route middleware — 31 of 39 groups carry `can:`.

## Design

**`hooks/defect-scan.sh` (Stop), over changed PHP only.** Two classes block, three report:

- **block** — `env()` outside `config/`; money as `float`/`double` in a changed migration. Both are
  deterministic: there is no shape of either that is correct.
- **report (exit 1, a notice)** — an irreversible side effect (`Mail::`, `Notification::send`,
  `Http::*`, `dispatchSync`) inside a transaction; a queued/broadcast event dispatched inside a
  transaction whose class lacks `ShouldDispatchAfterCommit`; a changed job with no retry or failure
  handling. Each has a legitimate shape, so each is a decision, not a refusal.
- The event check resolves the class file and reads its interfaces, and the whole check disarms when
  `config/queue.php` sets `after_commit => true` — the two things that turn a real signal into noise.
- Comment lines are not code: a guideline that mentions `env()` does not fail its own project.

**`hooks/test-gate.sh`: the SQLite warning becomes a refusal.** A green produced on SQLite for a MySQL
project is a false green, and three projects had been carrying that warning unread. The opt-out is a
stated reason (`gates.sqlite_tests_reason`), the same shape as `gates.analyse_skip_reason`.

**`hooks/session-start.sh`: one line when `preventLazyLoading()` is absent** from `app/Providers`.
Never blocking: enabling it changes which tests fail, and that is a decision to take deliberately.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | `env()` in app code blocks; in `config/` and in a comment it does not | met — 3 cases |
| AC2 | A money column as `double` blocks; `weight_kg` does not | met — 2 cases |
| AC3 | Mail inside a transaction is reported | met — `mail inside a transaction warns` |
| AC4 | A broadcast event without `ShouldDispatchAfterCommit` is reported | met — and the same shape **with** the interface stays silent, as does a plain synchronous event, as does any project with `after_commit => true` |
| AC5 | A job with no retry or failure handling is reported; one with `$tries`/`failed()` is not | met — 2 cases |
| AC6 | The gate is inert outside a project, outside git, with nothing changed, and under its opt-out | met — 4 cases |
| AC7 | A SQLite suite on a MySQL project is refused, and the refusal names the way out | met — 2 cases; a stated reason lets it run, a declared-sqlite project is untouched, a MySQL suite is unaffected |
| AC8 | The whole suite stays green | met — 335 cases, 16 suites |

## Deliberately not done

- **A raw-SQL injection check.** The audit's own hits were all internal column names; a check that
  cannot tell those from user input would train its user to ignore it.
- **An authorization gate.** Route-middleware authorization is legitimate and common in these projects;
  object-level authorization ("is this order mine?") is a real question, but proving a hole needs
  reading, not grepping.
- **Blocking on `preventLazyLoading`.** Turning it on changes test outcomes; a gate that fails a suite
  the moment it is installed would be uninstalled the same day.
