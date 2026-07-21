# Clarify protocol (RaDevs) — ask for decisions, never for facts

An assumed decision is the cheapest defect to prevent and the most expensive to find. This protocol is
how the agent resolves what only the user can answer — before the plan exists, not after the code does.
It is the interview half of discovery; [blind-spot-protocol.md](blind-spot-protocol.md) is the
prediction half, and it feeds this one.

## Mandate — facts are yours, decisions are theirs

**Every fact the environment can answer, you find yourself.** Boost (`application-info`,
`database-schema`, `search-docs`), the code, the impact map, the CRD, the git history, a subagent — all
of it is your job. Asking the user for a lookup wastes the one resource the environment cannot supply.

**Every genuine choice goes to the user.** A choice is genuine when two defensible options exist and the
difference is a *preference*, not a *truth*: product behaviour, priority, scope, trade-offs the user
lives with, anything touching money, permissions, or what a client sees. Pick these yourself and you are
guessing at someone else's intent under the appearance of progress.

The test: *could I find this out?* → find it. *Would two reasonable people choose differently?* → ask it.

## The frontier — what a round contains

Decisions branch. Some questions only make sense once an earlier one is answered — ask them together and
you are asking the user to answer a question you have not yet framed.

The **frontier** is every decision whose prerequisites are already settled: exactly the questions askable
*now* without guessing at an answer you have not heard. Ask the whole frontier in one round. A question
that depends on another still open belongs to the next round — each answer settles a branch and pushes
the frontier outward.

Questions reach the frontier from four places: ambiguity in what was said · a requirement that conflicts
with the code or the CRD · a **blind spot that needs a product call** (per the blind-spot protocol —
surfaced as a decision, not a prose bullet) · a fork in the implementation where the options differ in
consequence rather than in taste.

## Mechanics — one `AskUserQuestion` call per round

- **One round = one `AskUserQuestion` call**, at most 4 questions (the tool's limit). Prose questions
  are not an interview — they get skimmed and answered partially.
- **Each question carries your recommendation first**, labelled as such, with the consequence of
  choosing it. You did the discovery; the user should be able to click through your recommendations and
  get a defensible result. A question without a recommendation hands your job back to them.
- 2–4 options per question, each a concrete outcome ("queue it, deliver by e-mail") rather than a
  restated question. Keep the header under 12 characters — it renders as a chip.
- **Subagents never ask.** A subagent cannot prompt the user; when one surfaces a decision, carry it
  into your next round yourself.
- **Check `## Decisions` in `.claude/groundwork/task-state.md` first**, then write every answer back to it
  (see [working-memory.md](working-memory.md)). A settled decision re-asked after a compaction reads as
  amnesia and costs trust.

## Convergence — when the interview is over

The loop ends when the frontier is empty: every blocking decision answered by the user, everything else
recorded as an explicit assumption in the first response and in the spec. "No further questions" is a
claim about the decision tree, not about patience — an unasked decision that shapes the build is a
defect whether or not anyone was tired of questions.

## Calibration — proportional to level

Interrogation fatigue is the failure mode that kills the mechanism: past a certain length the user stops
reading options and clicks the first one. So the loop scales with what an assumed decision would cost:

- **L0/L1** — no loop. At most one question, and only when a blocking ambiguity genuinely stops the
  work; otherwise proceed on a stated assumption.
- **L2** — one round, blocking decisions only.
- **L3/L4** — rounds until the frontier is empty, capped at **3**. Anything unresolved at the cap is
  recorded as an explicit assumption in the spec — visible and reversible, never silent.

## Anti-patterns

- **Asking a fact** — "which DB engine does this project use?" is in `.groundwork.json`. Look it up.
- **A question without a recommendation** — you have the impact map and the code; take a position.
- **Dependent questions in one round** — "sync or queued?" and "how is the file delivered?" in the same
  round, when the second only exists if the first came back "queued".
- **Re-asking a settled decision** — the checkpoint's `## Decisions` is there to prevent it.
- **Interviewing an L1 bug fix** — the protocol scales down to nearly nothing for a reason.

## Reference case

"Add an orders export." The agent looks up what it can: row volume from `database-schema`, the existing
export helpers, the `hide_financial` rule from the permission map, the soft-delete on `orders` — none of
these are questions. Then round 1 asks the two genuine decisions: **format** (CSV, recommended — every
client opens it) and **synchronous or queued** (queued past ~50k rows, recommended, with the volume it
just measured as the reason). The answer "queued" pushes the frontier outward, and round 2 asks what only
now exists: **how the finished file reaches the user** (signed link in the response · e-mail · in-app
notification) and **whether financial columns appear for roles with `hide_financial`** — a blind spot the
user never raised, arriving as a decision with its consequence attached. Two rounds, four questions, no
assumed behaviour in a report someone will send to a client.
