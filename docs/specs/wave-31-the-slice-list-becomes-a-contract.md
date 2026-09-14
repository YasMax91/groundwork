# Spec: Wave 31 — a closed slice must name what proves it (v0.41.0)

- Type: plugin self-improvement → **L2** (one blocking Stop gate that executes nothing, a checkpoint
  grammar, changes to three skills and one guideline).
- Author: Max Yastremskyi (YasMax91).
- Source: agents closing tasks with slices unbuilt while every Stop gate stayed green. Redirected
  2026-09-14 by a trial and an audit — see **What the measurement changed** below. Design input read
  from `Leonxlnx/unlazy` (MIT, commit `1667149`): the abandon protocol and the progress guard.
- Status: **planned**. Supersedes the first draft of this spec (commit `e2565f6`), which anchored on
  `red test:` pointers that the corpus does not contain.
- Target version: **v0.41.0**. The executing gate moves to wave-32.

## What leaks today

The seven Stop hooks check the **repository**. Nothing checks **the task**.

`done-gate.sh`, `test-gate.sh` and `openapi-gate.sh` resolve a command from `.groundwork.json`, filter
changed paths, and pass or refuse on what the tree contains. None reads
`.claude/groundwork/task-state.md`, so none knows how many slices the approved plan had. A task
planned as five slices and built as three produces changed PHP that formats, analyses and tests clean,
an OpenAPI document matching the endpoints that exist, and a checkpoint whose remaining `- [ ]` lines
the agent wrote itself.

`conformance-reviewer` is an LLM judging a diff against AC text: no exit code, and it reads what was
written rather than what was omitted. `gates.coverage_claim` is warn-only and matches hedging words —
it fires on "выборочно" and stays silent on a confident report of three slices as five.

## What the measurement changed

The first draft of this spec assumed the checkpoint already carried a dereferenceable pointer, because
`guidelines/working-memory.md` prescribes
`- [ ] <slice> — red test: <path> — status: red|green`. An audit of every checkpoint on the author's
machine on 2026-09-14 — **37 files, 11 projects, 80 slice lines, 71 marked `[x]`** — found:

| | |
|---|---|
| Closed slices carrying a `tests/*.php` pointer | **10 of 71** |
| …whose named file is missing | 0 of 10 |
| Closed slices using the canonical `red test:` label | **3 of 71** |
| Closed slices carrying no test pointer at all | **61** |

The prescribed format is not what projects write. What they write points at **acceptance criteria**:

```
- [x] Slice 4 — `Characteristic::ordered()` scope + `characteristics.blade.php:7` → AC9 **green**.
- [x] **AC5 verified by mutation**: forcing `COLLATE utf8mb4_bin` fails exactly
- [x] S1: `app/Models/Traits/OrdersByTranslatedColumn.php` — `scopeOrderByTranslated`
- [x] commit — 5f8320a
```

Three consequences, each of which moved a decision:

1. **An executing gate has almost nothing to execute.** Phase 2 of the first draft would have had
   material for 14% of this corpus. Execution moves to wave-32, after pointers exist.
2. **The anchor is the AC id, not the test path.** Projects already reference `AC9`, `AC5`. The gate
   binds to what they write.
3. **`## Plan (slices)` is a work journal**, carrying commits, docs and live checks as rows beside
   slices. The parser must expect rows that are not slices and must not fail on them.

A parallel trial — one L4 task in `otaje`, 11 slices, a per-slice runnable ledger written before the
code — returned 11 gates, 10 runnable, 0 unmet, 0 blind misses. It is recorded in
`~/.claude/wave-31-log.md` and it is **not** evidence that the discipline works: the agent authoring
the ledger was the agent writing the code, and it knew all eleven checks in advance. A zero under
observation does not separate "the ledger prevented omission" from "this task would have been clean
anyway". The audit above is the load-bearing measurement; the trial is context.

## Design

### `hooks/slice-gate.sh` (Stop) — executes nothing, reads everything

A closed slice must name what proves it. The gate parses `.claude/groundwork/task-state.md` and the
spec named by its `Spec:` line. It runs no test, no analyser, no HTTP call: one file read plus one
spec read, cheap enough for every Stop, with no runner and no approval boundary.

**A row is a slice** when it matches `- [ ]` / `- [x]` / `- [~]` inside the `## Plan` section. Rows
that name only a commit hash, a document path, or a live check are journal rows: the gate counts them,
never parses them as slices, and never refuses on them. The audit found these in the majority of real
checkpoints, so tolerating them is a requirement, not a kindness.

**A slice marked `[x]` must carry one of three proofs:**

```markdown
- [x] expired code is refused (AC3) — test: tests/Feature/PromoCodeExpiryTest.php
- [x] refusal wording (AC5) — manual: product owner read the 422 body on staging 2026-09-14
- [~] bulk import (AC6) — abandoned: CSV schema not agreed; handed off in the summary
```

- **`test: <path>`** — the file must exist. Whether it passes is wave-32's question; whether it exists
  is answerable now and separates a slice with a test from a slice with a claim.
- **`manual: <what a person observed>`** — accepted, counted, and named in the summary. The text must
  be non-empty and must not merely restate the slice title; a manual proof that says "verified" proves
  nothing and is refused.
- **`abandoned: <reason>`** — `HANDOFF REQUIRED`, **exit 1**. The task can be reported, never as
  complete. A blank reason is malformed.

A `[x]` with none of the three is refused, naming the slice. That single rule is what the audit says is
missing: 61 of 71 closed slices named nothing at all.

**`(ACn)` and the reconciliation.** At `Mode: Done`, when `Spec:` names a file, the gate collects that
spec's `ACn` ids and subtracts the ids claimed by slices. An AC neither claimed nor named in an
abandonment is reported by id, and the gate refuses. This is what answers deletion: removing a slice no
longer removes the obligation, because the obligation lives in the approved spec.

Slices with no `(ACn)` reconcile nothing — one warning naming the count, no refusal. That keeps L1
inline specs and every pre-v0.41.0 checkpoint working.

**Backward compatibility.** `— red test: <path> — status: green` is read as `test: <path>`. The ten
checkpoints using it stay valid; `status:` is parsed and ignored, because the gate derives nothing from
a word the agent typed.

### Oracle lint — static, no execution

Two rules survive from the first draft, both answerable by reading the test file:

| Rule | Refuses on |
|---|---|
| `no-assertion` | The named test file contains no assertion |
| `tautological-assert` | `assertTrue(true)`, `assertEquals(1, 1)`, or a body that is only `markTestSkipped` / `markTestIncomplete` |

Two rules are dropped, each for a measured reason:

- **`unmeasured-number`** — the trial produced a false positive on the gate title "tells the **Block-2**
  team…", reading an identifier as a measurable quantity. A lint that misfires on a project's own
  vocabulary trains its user to ignore it.
- **`mostly-manual`** — dead on arrival as a warning. On the audited corpus it would fire on nearly
  every task. Replaced by the stricter requirement above: a manual proof must say what a person
  observed.

### Not wedging the session

The eighth Stop hook, and the fourth that can refuse. The guard from `unlazy`: the gate records the set
of proven slice ids in `.claude/groundwork/slice-guard`, and after **three consecutive refusals with
that set unchanged** it releases with a notice naming what is still unproven. The `stop_hook_active`
re-entry check from `hooks/coverage-claim.sh` is reused verbatim.

### Scope, opt-out, and the dependency

L0/L1 are silent — no spec, often no slice list. L2+ follows the fan-out table in
`guidelines/ai-sdd-process.md` rather than restating it.

Opt-out is `gates.slice_ledger: false` plus `gates.slice_ledger_skip_reason`, the shape
`analyse_skip_reason` established.

The gate reads the checkpoint, so `memory.checkpoint: false` disables it structurally. In that
configuration it prints one line saying the slice ledger cannot be checked and exits 0 — the failure
mode of the PHP-only gates, where a silent pass read exactly like a real one, is not repeated.

## Acceptance criteria

| # | Criterion | Proof |
|---|---|---|
| AC1 | A slice marked `[x]` carrying none of `test:` / `manual:` / `abandoned:` is refused, naming the slice | 1 case |
| AC2 | `test: <path>` whose file is absent is refused; present passes; whether it passes is not checked | 3 cases, the third asserted by a deliberately failing test that the gate accepts |
| AC3 | `manual:` with substantive text passes; empty, or a restatement of the slice title, is refused | 3 cases |
| AC4 | `abandoned: <reason>` prints `HANDOFF REQUIRED` and exits 1; a blank reason is malformed | 2 cases |
| AC5 | A journal row (commit hash, doc path, live check) is counted and never refused on | 3 cases drawn verbatim from the audited corpus |
| AC6 | An `ACn` in the spec claimed by no slice and named in no abandonment is refused by id at `Mode: Done` | 3 cases |
| AC7 | Slices with no `(ACn)` warn once and do not refuse | 1 case |
| AC8 | `— red test: <path> — status: green` is read as `test: <path>`; `status:` changes nothing | 2 cases, one a v0.40.0 checkpoint verbatim |
| AC9 | `no-assertion` and `tautological-assert` refuse | 4 cases |
| AC10 | The guard releases after three refusals with the proven set unchanged, and resets when a slice gains a proof | 2 cases |
| AC11 | The gate executes nothing — no test, no analyser, no HTTP | 1 case, asserted by a `test:` file that writes a marker when run |
| AC12 | Inert with no `.groundwork.json`, no checkpoint, no jq, under opt-out, at L0/L1, and under `memory.checkpoint: false` — and the last one says so | 6 cases |
| AC13 | The whole suite stays green | `hooks/tests/all.sh`, 335 existing + ~30 new |

## Files

- new: `hooks/slice-gate.sh`, `hooks/tests/slice-gate.sh`
- changed: `hooks/hooks.json` (Stop, after `openapi-gate`); `hooks/tests/all.sh` (suite list)
- changed: `guidelines/working-memory.md` — the slice grammar, replacing a format the corpus shows is
  not written
- changed: `skills/start-task` (write `(ACn)` when drafting slices), `skills/implement-approved` (name
  the proof when closing a slice), `skills/final-check` (the ledger summary joins the handoff)
- changed: `README.md`, `.claude-plugin/plugin.json` → `0.41.0`

## Deliberately not done

- **Executing the checks.** Moved to wave-32, on the audit's evidence: 10 of 71 closed slices carry a
  pointer worth executing. Building the executor first would have shipped a gate with nothing to run.
  Wave-32 becomes worth writing when new checkpoints show the pointer rate rising — measurable by
  re-running the same audit.
- **Arbitrary `shell:` checks and their approval layer.** Nothing executes here, so the question does
  not arise. It returns with wave-32, together with AC9 of the first draft (denying edits to
  `.groundwork.json` while a task mode is active), which only matters once a command can run.
- **Proving red→green.** Unverifiable after the fact without re-running history. A gate inferring it
  from a timestamp would produce a number that looks measured and is not — the reason
  `estimate-ledger.sh` refuses to infer `Started:` from an mtime.
- **The Depth Tree.** `unlazy`'s own `references/method.md` states the v1 claim about depth multiplying
  effort is not reproducible from its artifacts. L0–L4 and the `deep-*` skills hold that role here.
- **Orchestration, `OWNS:`, leases, dispatch waves.** `deep-discovery`, `deep-grounding` and
  `deep-review` already fan out through the Workflow tool.
- **An evidence digest.** It binds stored proof to a definition; this gate stores no proof.

## Estimate

**~50–70 active agent minutes**, in one sitting.

The ledger holds 24 recorded tasks, median 32 active minutes, p75 80 (`estimate-ledger.sh --report`,
all projects, 2026-09-14). This sits between them: one hook that only parses, ~30 test cases, and edits
across three skills and one guideline. Dropping execution removed the runner-dependent cases, the
approval surface and the `pre-tool-guard` change — roughly half the first draft's 90–120.

Human time, not included: approving this spec; re-running the checkpoint audit later to decide whether
wave-32 has become worth writing.
