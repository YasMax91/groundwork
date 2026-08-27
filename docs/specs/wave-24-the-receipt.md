# Spec: Wave 24 — measured facts stop sharing a paragraph with agent claims (v0.34.0)

- Type: plugin self-improvement → **L3** (a new hook, a new ledger mode, a new artifact, four prose
  files) — it changes what a finished task leaves behind.
- Author: Max Yastremskyi (YasMax91).
- Source: item E31 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). Ledger behaviour proven by tests: `estimate-ledger.sh` 28 cases
  (6 new), 300 across 15 suites, all green. The receipt itself is a skill step and a template —
  structural, and named as such.
- Target version: **v0.34.0**.

## Goal

A finished task left its evidence in the transcript. Nobody outside the session — a teammate, a
reviewer, the client — could see what actually ran. Leave one file behind, and make it impossible to
read an agent's claim as a measurement.

## Problem (diagnosis)

- `hooks/estimate-ledger.sh` was registered in **no hook** (`grep estimate-ledger hooks/hooks.json` →
  0). The only caller of `--record` was a sentence in `skills/final-check/SKILL.md:109`. Wave 18's
  entire measurement rested on the model remembering a command — the rule class this plugin exists to
  move into the engine.
- `guidelines/working-memory.md:23,30` documents `Mode: Done`; `hooks/lib.sh:15` does not accept it.
  Widening the canon would have been the obvious fix and the wrong one: `hooks/session-start.sh:50`
  **depends** on a finished checkpoint yielding no active mode — that is what stops it re-injecting a
  shipped task every session (v0.19.1, ~1100 tokens → ~180).
- Of the fields a receipt would carry, exactly five are machine-derivable. AC → test mapping and the
  conformance verdict are written by an LLM. A document that blurs the two is worse than no document:
  it looks like a review nobody performed.

## Design

**`--record-if-done` + `hooks/ledger-record.sh` (Stop).** The new ledger mode matches the terminal
marker itself — case- and emphasis-insensitive, `Done — shipped x` included — and dedups on the task
title plus `Started:`, kept in `.claude/groundwork/ledger-recorded`. The canon in `lib.sh` is untouched
and now carries a comment saying why. The hook is a thin wrapper (no arguments in `hooks.json`, matching
every other entry), never blocks, and is silent on the happy path. It runs **after** the gates, so a
blocked task is not recorded as finished.

Explicit `--record` keeps its old behaviour and does **not** dedup — it is the manual fallback for a
session that ended without the marker, and `final-check` now says to use it only when `--report` shows
the row is missing.

**`templates/specs/receipt.md` + a `final-check` step.** `docs/specs/<slug>.receipt.md`, next to the
spec, committed with the work, in three blocks: **Measured** (commit SHA, analyse exit code, suite exit
code, OpenAPI generation status, ledger minutes — each copied from a command's output, and a gate that
did not run written as *not run*), **Claimed by the agent** (the AC table, the verdict, what stayed
uncovered), and **Reviewed by** (a name and a date, left empty). The file states in its own last line
that an unsigned receipt is not a review. Not in `.claude/groundwork/`: `skills/init/SKILL.md:55`
requires that directory to be gitignored, where no one would ever see the file.

**The PR body carries the AC table at L2+** — the reviewer sees coverage without the transcript.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | A task still in progress records nothing | met — `W24 unfinished task, no row` |
| AC2 | A checkpoint marked `Done` records exactly one row | met — `W24 done records once` |
| AC3 | Repeated Stops never add a second row | met — `W24 never twice` (three further runs) |
| AC4 | `**DONE** — committed` and other hand-written shapes count | met — `W24 emphasised DONE counts` |
| AC5 | A later task with the same title gets its own row | met — `W24 second task, own row` |
| AC6 | `estimates.ledger:false` still disables everything | met — `W24 estimates.ledger=false` |
| AC7 | The hook survives a missing `lib.sh` like every other | met — `failsafe.sh` now runs 15 hooks plus its enforcement assertion, 16 cases |
| AC8 | The receipt separates measured from claimed, and says an unsigned receipt is not a review | met — structural: `templates/specs/receipt.md`, three blocks, stated in the file |
| AC9 | The whole suite stays green | met — 300 cases, 15 suites |

## Deliberately not done

- **Adding `Done` to `GW_MODES`.** It would re-inject every finished checkpoint at session start.
- **Git trailers linking commit → AC → test.** They reverse the deliberate one-line-commit decision at
  `skills/frontend-handoff/SKILL.md:86` and break corporate commit-lint.
- **Calling the receipt an audit trail.** What an auditor wants is reviewer identity, timestamp and
  attestation — a human signature. The receipt leaves the line; it does not sign it.
