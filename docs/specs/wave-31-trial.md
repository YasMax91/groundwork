# Wave 31 — trial protocol and log

Read this before working a task that is being used to trial the acceptance-ledger discipline of
[wave-31](wave-31-the-slice-list-becomes-a-contract.md). The trial runs `Leonxlnx/unlazy` as an
external skill; nothing of wave-31 is implemented yet. The question the trial answers is narrow:
**does a per-slice runnable ledger catch work that the seven Stop gates pass?**

## When to run it

L2 or L3 only, with an approved plan that has three or more slices. At L0/L1 a ledger is ceremony
and would produce a friction reading that says nothing about the gate being designed.

Two or three tasks are enough. Prefer one L2 and one L3 over three of the same shape.

## What the agent does

Run these alongside the normal Groundwork flow, not instead of it. `start-task` and `spec` are
unchanged; the ledger is written after the plan is approved and before `implement-approved`.

1. **After plan approval, before any code.** Record the plan size: how many slices, how many
   acceptance criteria the spec carries.
2. **Write `GATES.md`** from `~/.claude/skills/unlazy/templates/gates-leaf.md` — one gate per slice,
   id `G<n>`, the gate title stating the observable outcome. For each slice with a `red test:`
   pointer, the gate is runnable:

   ```markdown
   - [ ] G2: an expired promo code is refused with 422
     CHECK: ./vendor/bin/sail artisan test --filter=PromoCodeExpiry
     EXPECT: OK
     EVIDENCE: pending
   ```

   A slice no command can decide is a manual gate — no `CHECK:`, no `EXPECT:`. **Count these.**
   `EXPECT:` for a phpunit run needs care: `OK`, `passed` and `0` are the vocabulary failure output
   also uses, which is what the linter's `weak-expect` rule is for. Prefer a distinctive substring
   from the passing summary and let the exit code do the deciding.
3. **Lint it** and record every finding verbatim:

   ```
   node ~/.claude/skills/unlazy/scripts/gate-lint.mjs GATES.md
   ```

4. **Implement** through `implement-approved` as usual. Do not edit `GATES.md` while implementing —
   a ledger rewritten to match what was built measures nothing. If a gate turns out to be impossible,
   add `ABANDON: G<n> <reason>` rather than deleting it, and say so in the log row.
5. **Before `final-check`, verify:**

   ```
   node ~/.claude/skills/unlazy/scripts/gate-check.mjs --approve GATES.md
   node ~/.claude/skills/unlazy/scripts/gate-check.mjs --reverify GATES.md
   ```

   The agent approving its own checks removes the trust boundary `unlazy` built approvals for. That
   is acceptable here and only here: the ledger was written this session, the commands are the
   project's own test runner, and the trial measures omission, not supply-chain risk. Never carry
   this habit to an inherited ledger.
6. **Classify every unmet gate.** For each one, check whether `git diff --name-only` contains any
   file belonging to that slice. A gate whose slice has **no code and no test in the diff** is a
   **blind miss**: nothing in `analyse`, `test` or `openapi` had anything to fail on, so the seven
   Stop gates would have passed the task with that slice unbuilt. That count is the trial's whole
   point.
7. **Append one row to the log below**, then report the row in chat in Russian.

## What the user does

Read the row, and add one sentence of friction in the last column — whether the ledger helped, got in
the way, or was invisible. That judgement is not the agent's to make.

## Log

One row per task. Append only; never rewrite a row.

| Date | Task | L | Slices | Gates | Runnable | Manual | Lint findings | Unmet at reverify | **Blind misses** | Abandoned | Friction (user) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | |

### Reading the log

- **Blind misses > 0 on any task** — the gap wave-31 targets is real and the spec ships as written.
- **Blind misses = 0 across all tasks** — the seven gates already cover this codebase's failure mode.
  Do not build `slice-gate.sh`; the honest outcome is to close wave-31 and say why.
- **Gates < Slices on any task** — the agent dropped slices while writing the ledger itself. A gate
  built on a list the agent authors inherits that, and AC5 (reconciling against the spec's AC ids) is
  the only part of the design that answers it. Raise its priority.
- **Manual > half of Gates** — `mostly-manual` must ship blocking, not warn-only. That is a one-line
  change to the spec, made before implementation rather than after.
- **A lint finding on a gate that later passed** — record the gate verbatim. It is a real example of
  an oracle that could not fail, and the `no-assertion` / `tautological-assert` rules should be
  tested against it.
