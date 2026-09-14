# Spec: Wave 31 — the slice list becomes a contract (v0.41.0)

- Type: plugin self-improvement → **L3** (a new blocking Stop gate, a checkpoint format extension, an
  oracle linter, changes to four skills and two guidelines).
- Author: Max Yastremskyi (YasMax91).
- Source: agents closing tasks with slices unbuilt while every Stop gate stayed green. Design input
  read from `Leonxlnx/unlazy` (MIT, commit `1667149`, 2026-09-03) — the acceptance-ledger mechanics,
  not its Depth Tree.
- Status: **planned**.
- Target version: **v0.41.0**.

## What leaks today

The seven Stop hooks check the **repository**. Nothing checks **the task**.

`hooks/done-gate.sh`, `hooks/test-gate.sh` and `hooks/openapi-gate.sh` resolve their command from
`.groundwork.json`, filter changed paths, and pass or refuse on what the tree contains. None of them
reads `.claude/groundwork/task-state.md`, so none of them knows how many slices the approved plan had.
A task planned as five slices and built as three produces: changed PHP that formats, analyses and
tests clean; an OpenAPI document matching the endpoints that do exist; a checkpoint whose remaining
`- [ ]` lines the agent wrote itself. Every gate is green and two slices are missing.

The three mechanisms that should catch it do not:

| Mechanism | Why it misses this |
|---|---|
| `## Plan (slices)` in `task-state.md` | Prose. `working-memory.md` asks the agent to flip `[ ]`→`[x]` and `red`→`green` honestly. No hook parses those lines; nothing compares the box to a test result |
| `conformance-reviewer` | An LLM judging a diff against AC text. No exit code, and it reads what was written, not what was omitted — an AC with no code and no test is the case it is weakest on |
| `gates.coverage_claim` | Warn-only, and it matches hedging words in the final message. It fires on "выборочно"; it stays silent on a confident report of three slices as five |

The checkpoint already carries what a runnable gate needs. The current slice line is
`- [ ] <slice> — red test: <path> — status: red|green`, and `skills/spec/SKILL.md` step 4 gives every
acceptance criterion a stable ID and a `→ test:` pointer. The pointer exists. Nothing dereferences it.

## Design

### `hooks/slice-gate.sh` (Stop) — the box is set by the gate, not by the agent

Two phases, chosen by the checkpoint's `Mode:` (resolved through `gw_mode` in `hooks/lib.sh`, which
already returns nothing for the terminal `Done` marker — this gate matches `Done` directly, the way
`estimate-ledger.sh --record-if-done` does).

**Phase 1 — structure, on every Stop. Parses, never executes.**

Refuses on: a slice marked `[x]` with no check and no `manual:`; a malformed slice line; a duplicate
slice name; an `abandoned:` with a blank reason. Costs one file read, so it can run on every Stop
without a runner.

**Phase 2 — execution, only when `Mode: Done`.** Every runnable check is executed, including slices
already `[x]`. A slice is met only when its process exits `0`. The gate never reads `status: green`
as evidence — it re-derives the result, which is why no evidence digest is needed: there is no stored
proof to forge. This is `unlazy`'s `--reverify` semantics with its `--status` mode as phase 1.

Executing only at `Done` is deliberate. `test-gate.sh` already runs the suite on changed PHP at every
Stop; re-running per-slice filters alongside it would double the wait on every turn for a signal that
only matters at handoff.

### Checkpoint format — extended, backward compatible

```markdown
## Plan (slices)
- [x] promo code applies to cart total (AC1, AC2) — red test: tests/Feature/PromoCartTest.php — status: green
- [ ] expired code is refused (AC3) — check: test --filter=PromoCodeExpiry — status: red
- [ ] admin list shows redemption count (AC4) — check: http:GET /admin/promo-codes -> 200 — status: red
- [ ] wording of the refusal message (AC5) — manual: product owner reads the 422 body — status: pending
- [~] bulk import (AC6) — abandoned: the CSV schema is not agreed; handed off in the summary
```

- **`red test: <path>` keeps working unchanged** — it is read as `check: test <path>`. Every existing
  checkpoint in the eleven onboarded projects stays valid. This is the migration path; no rewrite.
- **`(ACn, ACm)`** — optional, and what makes deletion detectable (below).
- **`manual: <what a person must look at>`** — the gate counts it, names it in the summary, and never
  executes it. `unlazy`'s manual gate, kept because a wording decision has no command.
- **`[~] … abandoned: <reason>`** — a slice that cannot be built. The gate prints `HANDOFF REQUIRED`
  and **exits 1**: the task can be reported, but never as complete. A blank reason is malformed.

### Check forms — whitelist by default, shell by explicit project consent

`CHECK:` in `unlazy` is arbitrary shell, which is why it needs `~/.unlazy/approved`, binding to shell,
`PATH`, platform and timeout, and a `SECURITY.md`. Groundwork's hooks run commands from
`.groundwork.json`, not from text an agent writes. Keeping that property costs one whitelist:

| Form | Resolves to | Default |
|---|---|---|
| `test <path>` / `test --filter=X` | `gw_cmd artisan test …`, honouring `commands.test` | on |
| `analyse` | `gw_cmd composer analyse`, honouring `commands.analyse` | on |
| `format:test` | `gw_cmd composer format:test` | on |
| `openapi` | `commands.openapi_generate`, clean generation | on |
| `http:<METHOD> <path> -> <status>` | a real request against the running app | on |
| `shell:<command>` | executed as written | **off** |

`shell:` runs only when `.groundwork.json` sets `gates.slice_ledger_shell: true` **and** the exact
command string appears in `gates.slice_ledger_allowed[]`. Consent lives in a tracked file that passes
through review, not in a home directory.

**The hole this opens, named:** an agent can edit `.groundwork.json` and approve its own command.
`hooks/pre-tool-guard.sh` already denies edits by path and already reads the checkpoint mode; adding
`.groundwork.json` to its denied set while a task mode is active closes it, and that is AC9 below.
Without AC9, `shell:` is a gate the subject of the gate can rewrite.

### Deletion is caught by reconciling against the spec

A gate over a list the agent maintains cannot see a line that was removed. The reconciliation is what
sees it: at `Mode: Done`, when the checkpoint's `Spec:` names a file, the gate collects the `ACn` IDs
from that spec and subtracts the IDs claimed by the slices. Any AC that is neither claimed by a slice
nor named in an `abandoned:` reason is reported by ID, and the gate refuses.

This is `unlazy`'s `PLAN.md` inventory check. It is the mechanism that answers "they skip items on
purpose": removing the slice no longer removes the obligation, because the obligation is anchored in
the approved spec.

Slices with no `(ACn)` suffix reconcile nothing — the gate warns once naming the count, and does not
refuse. That keeps L1 inline specs and pre-v0.41.0 checkpoints working.

### Oracle lint — a check that cannot fail is not a check

`done-gate.sh` already refuses a declared no-op in `commands.analyse` (`echo`, `true`, `:`, `printf`
as the first word). The same class exists one level down, in the test a slice points at.
`gate-lint.mjs` in `unlazy` carries seven rules; four survive translation to a PHP suite, and they run
inside phase 1:

| Rule | Refuses / warns on |
|---|---|
| `no-assertion` | The named test file or filter contains no assertion — **refuse** |
| `tautological-assert` | `assertTrue(true)`, `assertEquals(1, 1)`, or a body that is only `markTestSkipped`/`markTestIncomplete` — **refuse** |
| `unmeasured-number` | A number in the AC text that appears in no assertion of its test — **warn** |
| `mostly-manual` | More than half the slices are `manual:` at L2+ — **warn** |

`weak-expect` and `path-read-as-regex` do not translate: this gate reads exit codes, not stdout, so
there is no expectation string to weaken.

### Not wedging the session

This is the eighth Stop hook and the fourth that can refuse. It carries a progress guard modelled on
`unlazy`'s: the gate records the set of met slice IDs in `.claude/groundwork/slice-guard`, and after
**three consecutive refusals with that set unchanged** it releases with an explicit notice naming what
is still unmet. A gate that can strand a session gets uninstalled; one that says "I am letting go, and
here is what stays unproven" does not. The `stop_hook_active` re-entry check from
`hooks/coverage-claim.sh` is reused verbatim.

### Scope by level, and the opt-out

L0/L1 have no spec and often no slice list — the gate is silent. L2+ is where the plan exists and
where `conformance-reviewer` already runs; the calibration follows the fan-out table in
`guidelines/ai-sdd-process.md` rather than restating it.

Opt-out is `gates.slice_ledger: false` plus `gates.slice_ledger_skip_reason`, the shape
`analyse_skip_reason` established: turning it off is a project's decision, leaving the Definition of
Done promising a check nobody runs is not.

**The dependency worth stating:** this gate reads the checkpoint, so `memory.checkpoint: false`
disables it structurally. In that configuration it prints one line saying the ledger cannot be checked
and exits 0 — the failure mode from the PHP-only gates, where a gate returned before reading its own
command and a silent pass read exactly like a real one, is not repeated.

## Acceptance criteria

| # | Criterion | Proof |
|---|---|---|
| AC1 | A slice marked `[x]` whose test fails is refused at `Mode: Done`, naming the slice | `slice-gate.sh` case: green box, failing filter |
| AC2 | A slice marked `[x]` with neither check nor `manual:` is refused in phase 1, on any Stop | 2 cases: no attribute; `manual:` present and accepted |
| AC3 | An existing `red test: <path>` line is read as `check: test <path>` and is not malformed | 2 cases: a v0.40.0 checkpoint verbatim; the same with `--filter=` |
| AC4 | `[~] … abandoned: <reason>` prints `HANDOFF REQUIRED` and exits 1; a blank reason is malformed | 2 cases |
| AC5 | An `ACn` in the spec claimed by no slice and named in no abandonment is refused by ID | 3 cases: missing AC; AC claimed by a slice; AC named in an abandonment |
| AC6 | Slices with no `(ACn)` suffix warn once and do not refuse | 1 case |
| AC7 | `shell:` does not execute without both `gates.slice_ledger_shell` and a matching allowlist entry | 3 cases: both absent; toggle only; toggle + exact match executes |
| AC8 | `no-assertion` and `tautological-assert` refuse; `unmeasured-number` and `mostly-manual` warn | 4 cases |
| AC9 | `pre-tool-guard.sh` denies editing `.groundwork.json` while a task mode is active | 2 cases: active mode denies; no checkpoint allows |
| AC10 | The guard releases after three refusals with the met set unchanged, and resets when a slice is met | 2 cases |
| AC11 | Phase 2 runs only at `Mode: Done`; an intermediate Stop executes nothing | 2 cases, asserted by a check command that writes a marker file |
| AC12 | The gate is inert with no `.groundwork.json`, no checkpoint, no jq, under its opt-out, at L0/L1, and under `memory.checkpoint: false` — and the last one says so | 6 cases |
| AC13 | The whole suite stays green | `hooks/tests/all.sh`, 335 existing + ~28 new |

## Files

- new: `hooks/slice-gate.sh`, `hooks/tests/slice-gate.sh`
- changed: `hooks/hooks.json` (Stop, after `openapi-gate`, before `coverage-claim`);
  `hooks/pre-tool-guard.sh` + `hooks/tests/run.sh` (AC9); `hooks/tests/all.sh` (suite list)
- changed: `guidelines/working-memory.md` (slice grammar), `guidelines/ai-sdd-process.md` (the gate in
  the Definition of Done)
- changed: `skills/start-task` (write `(ACn)` when drafting slices), `skills/implement-approved`
  (stop writing `status: green` by hand — the gate sets it), `skills/spec` (AC IDs are what the
  reconciliation subtracts), `skills/final-check` (the ledger summary joins the handoff)
- changed: `README.md`, `.claude-plugin/plugin.json` → `0.41.0`

## Deliberately not done

- **Proving red→green.** The plugin asks for a failing test before the code and cannot verify it after
  the fact without re-running history. A gate that inferred it from a timestamp or a commit would
  produce a number that looks measured and is not — the reason `estimate-ledger.sh` refuses to infer
  `Started:` from an mtime.
- **The Depth Tree.** `unlazy`'s own `references/method.md` states that the v1 claim about depth
  multiplying effort is not reproducible from the repository's artifacts, and that agents treated depth
  as a thoroughness cue. L0–L4 and the `deep-*` workflow skills already occupy that role here.
- **Orchestration, `OWNS:`, leases, dispatch waves.** `deep-discovery`, `deep-grounding` and
  `deep-review` already fan out through the Workflow tool. A second coordination model would compete
  with them.
- **An evidence digest.** `unlazy` binds a SHA-256 of the parsed check definition into its evidence
  because it stores proof between runs. Phase 2 re-executes instead of storing, so a stale record
  cannot exist. Its own documentation calls the digest structural drift detection, not tamper proof.
- **Blocking on the `unmeasured-number` and `mostly-manual` lints.** Both are lexical heuristics over
  prose. `coverage_claim` shipped warn-only in v0.24.0 for the same reason, and its log is what a later
  wave would read before turning either one blocking.

## Estimate

**~90–120 active agent minutes**, in one sitting.

The ledger holds 24 recorded tasks, median 32 active minutes, p75 80 (`estimate-ledger.sh --report`,
all projects, 2026-09-14). This wave sits above p75 and the number leans on that tail, not on the
median: two hook bodies, a format extension with a backward-compatibility path, ~28 test cases, and
edits across four skills and two guidelines. No row in the corpus is a plugin wave with two hooks, so
the sample supporting this particular shape is thin.

Human time, not included above: approving this spec; deciding whether `shell:` ships in v0.41.0 or
waits; running the trial that tells whether the ledger discipline holds on real L2/L3 tasks.
