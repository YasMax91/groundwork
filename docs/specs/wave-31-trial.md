# Wave 31 — trial protocol and log

Read this before working a task that is being used to trial the acceptance-ledger discipline of
[wave-31](wave-31-the-slice-list-becomes-a-contract.md). The trial runs `Leonxlnx/unlazy` as an
external skill; nothing of wave-31 is implemented yet. The question the trial answers is narrow:
**does a per-slice runnable ledger catch work that the seven Stop gates pass?**

## When to run it

L2 or L3 only, with an approved plan that has three or more slices. At L0/L1 a ledger is ceremony
and would produce a friction reading that says nothing about the gate being designed.

Two or three tasks are enough. Prefer one L2 and one L3 over three of the same shape.

## Where the operational copy lives

The runnable protocol and the log are **outside this repository**, so no branch or checkout state can
hide them from an agent working in a Laravel project:

- `~/.claude/wave-31.md` — the full protocol the agent follows (self-contained).
- `~/.claude/wave-31-log.md` — the log rows.
- `~/.claude/skills/wave-31-trial/SKILL.md` — makes "обкатка wave-31" enough to start it.

The ledger itself is written to `.claude/groundwork/gates-<slug>.md`, already git-ignored in every
onboarded project.

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
