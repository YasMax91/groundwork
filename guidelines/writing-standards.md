# Writing standards (Groundwork) — documents, estimates, reports

Applies to everything written for a human reader: `docs/client/`, `docs/specs/`, ADRs, the `ai/frontend`
handoff, estimates, and the final report of a task. It governs prose, not code — the code rules live in
[laravel-standards.md](laravel-standards.md).

The failure this file exists to prevent is **slop**: text that occupies space without giving the reader
anything he did not already have. It is not a matter of taste — slop costs the reader time, buries the
few sentences that matter, and makes a document impossible to check.

## The test

**Every sentence carries a fact the reader does not already have.** Before publishing, delete each
sentence and ask whether the document got worse. If it did not, it stays deleted. Length is whatever
survives — five sentences is a complete document if five sentences say everything.

## What is cut

- **Preambles and wrap-ups.** No "this document describes", no closing paragraph that restates the
  opening. The first sentence is already content; the last one is too.
- **Restating what was just said.** A fact lives in exactly one place. Everywhere else links to it.
  Repetition in three sections is not emphasis, it is three places to go stale.
- **Filler vocabulary.** `it is important to note` · `in today's fast-paced world` · `robust` ·
  `seamless` · `leverage` · `comprehensive solution` · `streamline` · `delve into` · `значительно` ·
  `стоит отметить` · `надёжное решение` · `бесшовно`. Connectives used only for rhythm
  (`furthermore`, `moreover`, `additionally`) go with them.
- **Self-praise about your own work.** Not "significantly improved", "fully covered by tests",
  "production-ready" — a number, a test name, or a command output instead. A claim the reader cannot
  check is worth less than the space it took.
- **Hedging around checkable facts.** "This may vary", "approximately", "should generally work" — where
  a probe is available, run it and write what it showed. Genuine unknowns are named as open, which is
  the opposite of hedging.
- **Structure with nothing in it.** A heading exists because there is content under it. An empty
  section is deleted, not filled. Where a template's section genuinely has no content, the template's
  own short answer ("Nothing", "None") is the whole section.
- **Decorative formatting.** Bold, tables and emoji carry meaning or they are removed. A table with one
  column of real data is a sentence.
- **Lists in place of thought.** Bullets are for genuinely enumerable things. A chain of reasoning is
  prose; splitting it into fragments loses the connections that made it an argument.

## A verification claim carries its denominator

A claim about verification takes exactly one of three forms, never a fourth:

- **Total** — "exercised 7 of 7 endpoints on the impact map".
- **Partial** — the fraction plus the enumerated remainder, each with its reason: "ran 3 of 12; the
  other 9 are «…», not run because «…»".
- **None** — "no verification was performed", stated plainly.

The denominator comes from a set named in the same sentence and enumerable from the work itself: the
impact map's consumers, the route list, the acceptance-criterion IDs, the changed files, a workflow's
states. **A fraction is never estimated.** Where no set can be enumerated, the answer is the third
form and not a guess — the same rule [grounding-protocol.md](grounding-protocol.md) applies to
research, applied here to the report.

"Checked it selectively", "went over it superficially", "mostly works" are none of the three. They
report an impression of effort and leave the reader unable to tell eight-of-nine from one-of-nine,
while satisfying "state what stayed unverified" on a technicality. The `coverage-claim` Stop hook
notices the crude form; the smooth form — "verified the endpoint works", no hedge, no denominator —
is caught by the review agents instead.

Level calibration is in [ai-sdd-process.md](ai-sdd-process.md) §Definition of Done: nothing at L0,
one sentence without a fraction at L1, fractions from L2 up.

## Estimates and reports specifically

- **No false precision.** A range whose ends differ by minutes is one number. A number that implies a
  measurement nobody took is invented.
- **No invented blocks.** The estimate has as many lines as there are genuinely different pieces of
  work — never one more to make the table look substantial. The unit and the separation of human time
  are governed by [ai-sdd-process.md](ai-sdd-process.md) §Estimates.
- **A report states outcomes, not effort.** What changed · what was verified and how · what stayed
  unverified · what is left. Not how hard it was, not how many files were read, no "Conclusion".
- **Failures are reported in the same voice as successes.** A failing test, a skipped step, an
  unverified claim is one plain sentence — not softened, not buried under what went well.

## Language

The artifact language rule (English canonical, Russian mirror only where a skill says so) belongs to the
individual skills — `client-doc` for client documents, `frontend-handoff` for handoff docs. This file
governs how the text reads in whichever language it is written: the cuts above apply to the Russian
mirror exactly as they apply to the English original, and a mirror is never allowed to be wordier than
what it mirrors.
