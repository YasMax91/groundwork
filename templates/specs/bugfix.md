# Spec: fix <bug>

- Type: bug fix (L1)
- Source / report:
- Status: draft | approved

## Current (wrong) behavior

## Root cause

## Source requirements (verbatim — every item of the request, subtasks and notes included)

<!-- Quote each item exactly as the person or the brief wrote it. One row per item; nothing summarised away.
     The last column is filled during the work. slice-gate blocks "done" while any row has no proof. -->

| ID | Requirement (verbatim) | Source (message time / file:line) | Proof (test, HTTP run, screenshot, or out of scope: <reason agreed>) |
|---|---|---|---|
| R1 | | | |

## Expected behavior

## Fix (smallest safe change)

## Acceptance criterion (EARS)

- [ ] **AC1** WHEN <repro condition> THE SYSTEM SHALL <correct behavior> (was: <wrong behavior>).
      → test: the regression test below

## Regression test (write first — red→green)

A failing test that reproduces the bug **before** the fix; passes after. Written first — a test that
is green on its first run proves nothing.

## Blind spots considered

Dimensions the report did not name but the fix should account for — regression scope, related callers,
rows already in the bad state (per the blind-spot protocol). Material only; "none" is valid.

- <what was missed> → <consequence if ignored> → <handled here / deferred because …>

## Risks
