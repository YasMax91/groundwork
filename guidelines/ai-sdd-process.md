# AI-SDD process (Groundwork)

Generic spec-driven workflow for any Laravel project. Domain facts live in the
project's `AGENTS.md`; this file is the process. Read together with
[grounding-protocol.md](grounding-protocol.md), [blind-spot-protocol.md](blind-spot-protocol.md),
[laravel-standards.md](laravel-standards.md), [tdd-protocol.md](tdd-protocol.md), and
[writing-standards.md](writing-standards.md).

## Operating modes

State the current mode when starting non-trivial work. Discovery is wide; the change is narrow —
scope the edit tightly, never the investigation.

- **Discovery** — inspect files, search code, read docs/CRD, summarize current behavior. Map the
  connections outward (callers, consumers, events, jobs, policies, FK/cascades, covering tests), not
  just the directly-involved files. Draft assumptions. Surface **blind spots** — the dimensions the
  request omits (unintended consequences, missing requirements, domain/product angles the user is not
  the expert in), per [blind-spot-protocol.md](blind-spot-protocol.md). Then **interview** the user for
  the decisions only they can make — facts are yours to find — per
  [clarify-protocol.md](clarify-protocol.md). No edits.
- **Spec** — create/update a spec under `docs/specs/`. No production code.
- **Plan** — propose steps, list changed files, tests, verification, deployment impact. No edits
  until approved.
- **Implementation** — test-first (red→green→refactor): write the failing test, implement to green,
  refactor under the gates. Edit per the approved spec; keep scope tight. A **new sub-request re-enters
  discovery for its own blast radius** before it is built — compare its seeds against the cached map and
  re-map when they fall outside it — the cheap seed comparison runs at every level, while re-spawning the
  expensive mapper is reserved for new model/table/service seeds (accumulated small additions count). See
  [tdd-protocol.md](tdd-protocol.md) and [working-memory.md](working-memory.md).
- **Review** — review the diff for violations, missing tests, risks, and **exercise the change live**
  against the running app (HTTP run / browser drive per `final-check`, scaled by level) — green gates
  prove the code, not the running app. No silent changes. Two review agents, spawned per the fan-out
  table above: the **conformance-reviewer** judges the diff against the spec's acceptance-criterion IDs
  (does it match?); the **adversarial-verifier** challenges "it works" claims (is the claim true?). A
  defect the **user** reports is a signal about a whole class: **enumerate the sibling sites and report
  them**, fix those inside the approved scope, and offer the rest as a named follow-up slice rather than
  silently widening the change.

## Task classification (classify before working)

- **L0 Tiny** — typo/comment/docs. No spec/plan/tests/approval if the user asked for it.
- **L1 Small bug fix** — short inline spec, plan, targeted regression test. Approval unless the
  user said apply now.
- **L2 Normal feature** — spec + plan + tests + approval.
- **L3 High-risk** (workflow state, payments/financial visibility, RBAC, schema migration, public
  API contract, deploy/runtime) — spec + plan + CRD check + tests + deployment notes + approval.
- **L4 Critical** (financial calc, order lifecycle, permission model, destructive migration,
  external integration behavior, queue/scheduler with business impact) — all of L3 + rollback
  notes + human approval always required.

## Estimates

The unit is **the wall-clock time the agent itself spends producing the work** — writing the code, its
tests and its OpenAPI, and running the gates. It is not how long a developer would have taken, and it is
not a man-day relabelled in a smaller-sounding unit. Work built on mechanisms this codebase already has
is normally **minutes**; hours appear only when something genuinely slow sits in the loop, and that thing
is named on the same line. An estimate that reads like a human work day for a CRUD endpoint is wrong by
construction — no calibration rescues it.

The **full format** — a line per block of work, a total, and human time on its own line — belongs to a
document or an explicit "how long will this take?", and is owned by the **`client-doc`** skill
([../skills/client-doc/SKILL.md](../skills/client-doc/SKILL.md)). A passing remark about time in
conversation just needs the right unit, not the whole table.

**Human time is its own line and is never added to the agent's.** Everything the agent cannot do itself
belongs there, each with its owner: registering an account with a provider, issuing API keys, configuring
a webhook in someone else's dashboard, passing a verification, granting access, deciding an open product
question, reviewing and accepting the result. Folding these into the development number is exactly how
twenty minutes of writing code is published as "a day of work".

**Calibrate against this repository's own clock.** Read how long the work here actually took — commit
timestamps inside one working session, not calendar days:

```bash
git log --format='%ad %s' --date=format:'%Y-%m-%d %H:%M' --since='2 months ago'
```

The gap between consecutive commits in a session is the real cost of that slice. Where the log is
batched or too sparse to read that way, say so and estimate from the delta below rather than inventing a
coefficient. An older estimate document in the same repo is an **input, not an authority**: its numbers
were written before the work, and unless someone recorded actual-vs-estimated afterwards, nothing has
confirmed them. Inheriting its coefficients is how an estimate silently doubles.

**Know what actually costs the time.** Writing code is not the dominant cost — migrations, models, form
requests, resources, tests and OpenAPI are minutes. Three things are:

1. **External uncertainty** — reading a third-party API against its official docs, live sandbox probes,
   establishing what the provider really does. Nothing accelerates this.
2. **Undecided product questions** — wherever the requirement admits more than one reading and someone
   else has to choose. The waiting is human time, not development time.
3. **Cost of being wrong** — money, access, personal data. Those carry deliberately more testing.

**Estimate the delta, not a rewrite.** If the functionality existed and was removed or deferred, the
implementation is in git history — say so and estimate restoring it. The same holds for anything the
codebase already does elsewhere: the estimate covers adapting it, not inventing it.

**Calendar time is not development time.** If the reader needs a date, it is the agent's time plus the
wait on the human steps already listed — each named, so the reader can see which of them is actually the
long pole. Never pad the development number to cover that wait.

**Sanity-check before publishing.** Compare the total against the measured commit intervals and against
the delta actually being written. If it implies this repo ships far less per session than its own log
shows, the estimate is wrong — rework it rather than publish a padded number. Padding is not caution: it
costs the client money and it costs the schedule its credibility. An estimate the author cannot defend
against the repo's own history is not an estimate.

**No slop in the number.** No false precision (a range whose ends differ by minutes is one number), no
hedging disclaimers around it, no block invented to make the table look substantial. See
[writing-standards.md](writing-standards.md).

## Fan-out by level (effort scaling)

Match agent fan-out to task level. Over-spawning wastes ~15× the tokens; coding is a poor multi-agent
fit, so only Discovery and Verification fan out.

- **L0 Tiny** — no subagents. Inline.
- **L1 Small** — self-trace (a few targeted greps). No agent.
- **L2 Normal** — 1 `impact-mapper` (cache-aware). Add `grounded-researcher` only if an external API
  is touched; `blind-spot-mapper` optional when the task has real product/domain surface. For
  verification: `conformance-reviewer` on the diff-vs-spec.
- **L3 High-risk** — `impact-mapper` + `blind-spot-mapper` + `grounded-researcher` (if integration) for
  discovery; `conformance-reviewer` + `adversarial-verifier` for verification. May escalate to
  `deep-discovery` / `deep-grounding` / `deep-review`.

- **L4 Critical** — as L3 (blind-spot-mapper required), plus an adversarial panel (≥2 skeptics) on the
  riskiest claims and blind spots.

**This list is the single source of truth for review-agent fan-out** — `final-check`,
[grounding-protocol.md](grounding-protocol.md), and Review mode point here rather than restating it. In
short: **conformance-reviewer at L2+** (does the diff match the spec?), **adversarial-verifier at L3/L4
and whenever a claim about an external capability is made** (is the claim true?).

**Implementation is single-threaded.** Work one TDD slice at a time — no parallel coding agents. The
fan-out above is for Discovery and Verification only.

## Startup sequence (non-trivial tasks)

The ordered steps and the first-response structure belong to the **`start-task`** skill
([../skills/start-task/SKILL.md](../skills/start-task/SKILL.md)), which owns them — follow it there
rather than a second copy that drifts. Three rules bind every path through it: the first response
carries no code, no **production** file is edited before the plan is approved — the workflow checkpoint
under `.claude/groundwork/` and planning docs are the standing exception, which the `PreToolUse` guard
already implements — and a decision the user could have made is never assumed instead.

## Definition of Ready

Goal clear · current behavior inspected · affected files identified · connections mapped (callers,
events, jobs, policies, FK/cascades, consumers of the response shape, covering tests) — and the map
covers the seeds of the work actually at hand, not an earlier scope · candidate approaches presented with
a recommendation (or the single sensible path stated as such) · acceptance
criteria written · validation/authorization/API/DB/queue impact known · tests listed (the red list —
fail-first tests covering the criteria, for L2+/bug fixes) · deployment
risks identified · blind spots surfaced (resolved or explicitly accepted) · every blocking decision
answered by the user rather than assumed · assumptions documented.

## Human approval gates (stop and ask)

public API contract change · new dependency · destructive migration · workflow-state logic ·
financial calculation · weakening permissions · deploy/runtime change · new architectural layer ·
external integration behavior · behavior not supported by CRD/code/explicit user decision ·
broad refactor/formatting/file deletion.

For a **cross-cutting, durable** decision among these (new dependency, new architectural layer,
workflow-state model), capture an ADR in `docs/adr/NNNN-<slug>.md` (from `templates/adr.md`) — ≥2
considered options + the chosen one + why. Feature-local trade-offs stay in the spec.

## Definition of Done — scaled by level

**The list below is the L2+ Definition of Done.** Applying all of it to a typo is how a process stops
being used. What scales down is *breadth*, never *proof*:

- **L0 (typo, comment, docs)** — the gates that fire on their own. No live run, no consumer sweep, no
  domain-drift check, no frontend handoff, no approach block, no interview.
- **L1 (small bug fix)** — the gates · a fail-first regression test · a **live exercise of the one thing
  fixed** (not a sweep of every consumer). Domain-drift, the runnable request package, and the frontend
  handoff apply only if the change actually touched the frontend-facing contract.
- **L2+** — everything below.

Unconditional at **every** level, because they are what makes a report trustworthy rather than thorough:
state what stayed unverified · never report green tests as "works live" · never claim unqualified "done".

**Every verification claim carries its denominator** — the covered/total fraction against a named,
enumerable set, or the plain statement that no verification was performed. The three permitted forms
and the ban on estimating a fraction are in [writing-standards.md](writing-standards.md). Scaled:

- **L0** — nothing; the automatic gates are the whole Definition of Done.
- **L1** — one sentence, no fraction: what single thing was exercised live, and that nothing else was
  touched.
- **L2+** — a fraction per claimed set.

An item enumerated as not covered is a line of its own in the final report, never absorbed into prose:
"not covered" and "done" are not simultaneously true for the same item.

## Definition of Done (L2+)

implementation matches the approved spec · public API preserved or intentionally changed ·
validation via FormRequest · authorization handled · business logic in services · resources preserve
response shape · multi-step writes transactional · focused tests written test-first (red→green) and
passing · every acceptance-criterion ID mapped to a passing test (no AC unmapped) · **OpenAPI current and
complete for every touched endpoint** — annotations updated in the same change, every reachable status
code documented, request body from the FormRequest, response schema from the JsonResource, generation
clean (see [openapi-protocol.md](openapi-protocol.md); the `openapi` Stop gate enforces it) ·
format + static analysis run — and where either was skipped, the report carries the reason, not merely
the config (a gate that did not run has verified nothing, whatever its exit code) · **exercised live
against the running app** for
the touched surface — a real HTTP run for an endpoint, a real browser drive for admin/UI/CSS (asset
loads · effective computed style · no persisted state masking it), or an explicit statement of what
stayed unverified with repro steps; green tests are never reported as "works live" · **every consumer of
a touched shape verified** (List *and* Show, export, API resource, notifications — per the impact map)
with denormalized/derived values present on real data, or the consumer noted out of scope **with the
note stating who put it there** — the agent may propose it, the report shows whether the user agreed ·
migration/deployment impact
documented · **domain contract current** — the project's `AGENTS.md` reflects any entity, invariant,
permission rule, integration, or term the change introduced · frontend handoff docs in `ai/frontend` created/updated when the change touches the
frontend-facing surface (run the `frontend-handoff` skill after the gates are green) · final report
covers changed behavior, files, verification, risks, skipped work.

After the final implementation and the frontend handoff, **ask whether to commit**; on yes, make a
single-line commit with no AI attribution (the `frontend-handoff` skill drives this).

Never declare done with failing tests or static-analysis errors. Never use unqualified "100% done" —
see [grounding-protocol.md](grounding-protocol.md).

## Self-review checklist (before the final response)

followed the spec? · only related files changed? · impact map honored (each flagged consumer handled
or noted out of scope)? · API contracts preserved? · controllers thin? ·
logic in services? · validation in FormRequest? · authorization present where needed? · multi-step
writes transactional? · resources preserve shape? · N+1 handled? · migrations production-safe? ·
tests written test-first (red→green) for covered work? · each acceptance-criterion ID mapped to a
passing test? · gates run or skip-reason stated? · exercised live against the running app at the level's
depth (or stated what stayed unverified + repro)? · **L2+:** every consumer of a touched shape verified,
denormalized values present on real data? · a user-reported defect's sibling class enumerated, with each
sibling fixed in scope or offered as a slice? · blind spots surfaced (or none)? · risks/assumptions
documented?
