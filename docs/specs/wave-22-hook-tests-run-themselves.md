# Spec: Wave 22 — the hook tests stop depending on the author's memory (v0.32.0)

- Type: plugin self-improvement → **L1** (one new CI file, no plugin code touched).
- Author: Max Yastremskyi (YasMax91).
- Source: item E29 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27), locally proven; the first hosted run is a human step.
- Target version: **v0.32.0**.

## Goal

The hooks are the only executable part of this plugin, and waves 19–21 added branches to them. The
repository had no `.github/` directory at all: the 15 suites ran when the author remembered to run them.

## Design

`.github/workflows/ci.yml`, two jobs:

- **`tests`** — `bash hooks/tests/all.sh` on `ubuntu-latest` and `macos-latest` (`fail-fast: false`, so
  a macOS-only failure is not hidden by Linux going red first). A step configures a git identity,
  because several fixtures commit inside throwaway repositories, and a step prints the resolved path of
  `bash`, `jq`, `python3` and `git` — when a suite behaves differently on a runner, the tool inventory
  is the first thing worth seeing.
- **`manifests`** — parses both manifests and fails if `plugin.json` and the marketplace entry describe
  the plugin differently (that description is the catalog's entire search surface). Then
  `claude plugin validate .` **when the CLI is present**, and an explicit notice that validation did not
  run when it is not. Whether the CLI exists on GitHub-hosted runners is unverified; a silent pass would
  be the same defect this plugin exists to catch.

`--strict` is not used: during the market scan's verification it turned an unknown-field warning
(`icon`, `screenshots`) into a failure, and the catalog's own review pipeline does not require it.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | The workflow is valid YAML with both jobs and a two-OS matrix | met — parsed; jobs `tests`, `manifests`; matrix `ubuntu-latest, macos-latest` |
| AC2 | Every `run:` step of the `manifests` job executes green locally | met — extracted from the parsed YAML and run: `version: 0.31.0`, `descriptions match`, `Validation passed` |
| AC3 | `bash hooks/tests/all.sh` is green: 15 suites | met — `lib run test-gate gates openapi-gate coverage-claim estimate-ledger estimate-claim task-intent agent-contract statusline session-start trim-output pre-compact failsafe` |
| AC4 | A deliberate regression turns the suite red | met — removing the `python3` branch from `hooks/pre-tool-guard.sh` failed exactly `W19 nojq runner_deny` and `W19 nojq migration` (`want 2, got 0`, the pre-wave-19 behaviour); restored, 32/32 green |
| AC5 | The first hosted run is green before a README badge is added | **open — human step.** No badge is added by this wave |

## Deliberately not done

- **`claude -p` in CI.** It duplicates the local Stop gates and pays tokens and Actions minutes for an
  answer already obtained.
- **A README status badge.** A badge for a workflow that has never run on the hosted runners would be a
  claim without a run — the same defect the plugin gates against. It goes in after the first green run.
