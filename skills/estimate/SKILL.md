---
description: Answer "how long will this take?" in the agent's own measured build time. Reads the estimate ledger — this author's real active minutes per task — and reports a number that rests on a median and its sample size, with human time on its own line. Use whenever a duration, deadline, or delivery date is asked for or is about to be stated, in chat, in a plan, in a spec, or in a client document.
---

# Estimate

A duration is a **measurement of this codebase's own history**, not an opinion about how long the work
feels. The measurement exists: `hooks/estimate-ledger.sh` records the agent's active minutes per task
and per commit window across every Groundwork project on this machine.

**Read the ledger before writing a number. Every time.** An estimate produced without it is the model's
pretraining prior, and that prior is denominated in developer hours — which is exactly the failure this
skill exists to prevent.

## Get the measurement

```bash
${CLAUDE_PLUGIN_ROOT}/hooks/estimate-ledger.sh --report
```

Add `--level=L2` or `--kind=crud` to narrow it. The output carries, per source and per scope, the
sample size `n`, the median and p75 in **active agent minutes**.

Two sources, never mixed:

- **`task`** — one Groundwork task, start to `final-check`. The right unit. Preferred whenever
  `n ≥ estimates.min_sample` (default 5).
- **`commit-window`** — the seed, backfilled from git history. A noisier unit: it measures the slice of
  work between two commits, which is smaller and more arbitrary than a task. Usable, and always named
  as what it is.

If the ledger is empty, run `--backfill` once. Only if that also yields nothing does the coarse
fallback in [`../../guidelines/ai-sdd-process.md`](../../guidelines/ai-sdd-process.md) §Estimates
apply — and it is labelled coarse in the answer.

## What the answer contains

1. **A line per genuinely different block of work**, then a total. In minutes, unless something
   genuinely slow sits in the loop.
2. **The median and the sample size it rests on** — "median 14 min over 76 measured windows in this
   project". A number without its denominator is an opinion again.
3. **Human time on its own line, never added in.** Registering an account with a provider, issuing API
   keys, configuring a webhook in someone else's dashboard, deciding an open product question,
   reviewing and accepting the result. Each with its owner.
4. **A date only if asked**, as the agent's time plus the named human waits — never the development
   number padded to cover the waiting.

## When the sample is too small

Say so, in one line, and name what you fell back to. `n = 3` is not a median; presenting it as one
rebuilds the confident wrong number out of new material.

## Hours need a reason on the same line

An estimate in hours is not forbidden — it is **unexplained hours** that are wrong. If the number
exceeds an hour, the slow thing is named right there: reading a third-party API against its official
docs, live sandbox probes, a migration over a large table, waiting on a human decision. If no such
thing can be named, the number is wrong and the ledger will say so. The `estimate-claim` Stop hook
watches for exactly this shape and logs it.

## What never appears

Man-days · developer hours · "a day of work" · a range whose ends differ by minutes · padding for
caution · a block invented to make the table look substantial · a total that implies this repository
ships far less per session than its own ledger shows.

## Three things that actually cost time

Writing code is not the dominant cost — migrations, models, form requests, resources, tests and
OpenAPI are minutes. These are not:

1. **External uncertainty** — establishing what a third-party provider really does.
2. **Undecided product questions** — the waiting is human time, not development time.
3. **Cost of being wrong** — money, access, personal data carry deliberately more testing.

## Estimate the delta, not a rewrite

If the functionality existed and was removed, it is in git history — say so and estimate restoring it.
The same holds for anything the codebase already does elsewhere: the estimate covers adapting it.

## Where the full format belongs

A line-per-block table with a total belongs in a document or in an explicit "how long will this take?".
A passing remark about time in conversation needs the right unit and the sample size, not the whole
table. The client-facing presentation of these numbers is owned by
[`../client-doc/SKILL.md`](../client-doc/SKILL.md).
