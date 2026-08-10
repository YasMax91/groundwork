# Spec: Wave 13 — real build time, no slop, and an interview that actually happens (v0.22.0 + v0.23.0)

- Type: plugin self-improvement. Two related complaints from the author, both about the plugin telling
  him what he already knew instead of what he needed → **L3** (cross-cutting change to when rules fire).
- Author: Max Yastremskyi (YasMax91).
- Source: author feedback (2026-08-10), not an audit. Two statements: estimates come back in human hours
  for work an agent writes in minutes, and `grill` "is never used" — the plugin should lead him to the
  decisions instead of waiting to be asked.
- Status: **implemented** (2026-08-10). Verification is structural — see the plan at the end; no
  behavioural run has been recorded yet.
- Target versions: **v0.22.0** (estimates + writing standards) and **v0.23.0** (interview depth).

## Goal

Two failures with the same shape: a rule existed, was correct on paper, and never changed the output.

- The estimate rule said "AI-hours, never man-days" and then supplied coefficients — 1–2.5 h internal,
  3–5 h with an integration — that are human coefficients wearing the new label. The unit changed; the
  number did not.
- The interview rule said the agent must clarify before planning and then capped L2 — the level most
  tasks land on — at **one round of blocking questions only**, offering the unbounded interview solely in
  pathological cases. The mechanism existed and was unreachable in normal work.

## Problem (diagnosis)

### A. Estimates (v0.22.0)

1. **The coefficients contradicted the unit.** `guidelines/ai-sdd-process.md` §Estimates published a
   typical shape of 1–2.5 h / 3–5 h per task. An agent writes a `FormRequest`, a resource, a migration
   and its tests in minutes; the range could only have come from what a developer would have taken.
2. **Calibration measured the wrong clock.** It read `git log --date=short` and grouped by day — daily
   throughput is a human planning unit and cannot detect that a task took eleven minutes.
3. **Human work had no home.** Registering a provider account, issuing keys, configuring a webhook,
   waiting for a product decision — all real, none of it development, and nothing in the rules said where
   it goes. It ended up folded into the development number.
4. **A sprint-capacity clause** (plan 45–60 % of nominal capacity) pulled the whole section back into
   man-days after the unit rule had pushed it out.

### B. Slop (v0.22.0)

No rule anywhere governed how a document reads. `client-doc` had a local style section; specs, handoff
docs and final reports had nothing. Filler, restated facts, self-praise and hedging were unconstrained,
and in a client document they read as padding on an invoice.

### C. The interview (v0.23.0)

1. **`grill` was reachable only through three pathological gates** — intent too unformed to plan
   (`start-task` 7b), the round cap reached while the frontier still refills (`clarify-protocol`
   §Convergence), decisions too unsettled to write into a spec (`spec`). None fires on a normal task.
2. **L2 was one round, blocking decisions only** (`clarify-protocol` §Calibration), and most tasks are
   L2. This, not `grill`, is why the plugin felt like it did not lead anywhere.
3. **The unbounded offer was written for the L3/L4 cap** and therefore did not exist at L2 at all;
   everything unresolved there became a silent assumption.
4. **Assumptions were recorded, never shown.** They went into the spec and the first response's risks
   section — the user never saw a list of what the agent had decided *for* him and what being wrong costs.
5. **The entry point assumed a command.** The author starts tasks as plain prose. Nothing in the session
   context said a described task enters through `start-task`, so the whole protocol depended on the model
   choosing to reach for the skill.

## Design — per item

### A1 — The unit is the agent's own wall-clock time

`guidelines/ai-sdd-process.md` §Estimates rewritten: the unit is the time the agent spends producing the
work; work on existing mechanisms is **minutes** and is published as minutes; hours appear only with
something genuinely slow in the loop, named on the same line. The 1–2.5 h / 3–5 h shape is deleted, and an
estimate that reads like a human work day for a CRUD endpoint is called wrong by construction.

### A2 — Calibrate against commit intervals, not calendar days

`--date=format:'%Y-%m-%d %H:%M'`; the gap between consecutive commits inside a session is the real cost of
that slice. Where the log is batched or too sparse to read that way, the rule requires saying so rather
than inventing a coefficient.

### A3 — Human time is a separate line with an owner

Provider accounts, API keys, webhook configuration, verifications, access grants, open product decisions,
review and acceptance. Never added to the agent's number. A calendar date, when asked for, is the agent's
time plus the wait on those named steps — never the development number padded to cover it. The
sprint-capacity clause is replaced by this rule. `templates/client-doc.md` gains a second table (what ·
who does it · time) and its estimate column becomes "Time".

### B1 — `guidelines/writing-standards.md` (new)

One test (delete the sentence; if the document did not get worse, it stays deleted) and a list of what is
cut: preambles and wrap-ups, restated facts, filler vocabulary, self-praise, hedging where a probe
exists, empty structure, decorative formatting, bullets in place of reasoning. Plus a section for
estimates and reports: no false precision, no invented blocks, outcomes rather than effort, failures in
the same voice as successes. Referenced from `client-doc`, `spec`, `frontend-handoff`, `final-check`.

### C1 — Calibration raised

L2 → up to **2** rounds, covering blocking decisions **and** any product fork whose two readings would
ship differently. L3/L4 → up to **4**. The fatigue paragraph is rewritten: fatigue comes from bad
questions (a fact that could have been looked up, an option needing translation, a round without a
recommendation), so the cure is question quality, not silence.

### C2 — Mandatory subjects

New `clarify-protocol` section: from L2 up, money · permissions and access · what the client sees ·
external integrations · two or more open product forks each carry a round of their own, however settled
the request sounds. Where the cap cannot hold them, that is the trigger for C3 rather than a longer
assumption list.

### C3 — The unbounded interview becomes a standing choice

From L2 up, the first interview round carries the depth question (proceed at the level's calibration ·
run the unbounded interview now). The old signals — a problem rather than a change, no statable "done",
incompatible readings, an open goal at L3/L4, mandatory subjects overflowing the cap — now decide whether
it is **recommended**, not whether it is mentioned. `grill` keeps `disable-model-invocation: true` and
stays the manual entry point for something that is not a task yet; inside a task the agent runs the same
loop on acceptance.

### C4 — Cost of silence

New `start-task` step 8a and a `clarify-protocol` section: before the plan, every decision the agent took
on the user's behalf is listed — what was assumed · why · what it costs if wrong · the one line that
changes it — in plain language. An empty list is stated as empty, which is a claim that the frontier was
empty. `blind-spot-protocol` routes its capped-out items into this list.

### C5 — Entry without a command

`hooks/session-start.sh` adds one line to `additionalContext`: a task described in chat enters through
`start-task` with no command from the user, interview depth follows the clarify calibration, and from L2
up the first round offers the unbounded interview.

## Acceptance criteria (EARS)

- [ ] **W13-AC1** WHEN an estimate is produced, THE unit SHALL be the agent's own wall-clock build time,
      and work on existing mechanisms SHALL be expressed in minutes. → check: guidelines/ai-sdd-process.md
- [ ] **W13-AC2** THE §Estimates section SHALL NOT contain per-task hour coefficients or a sprint-capacity
      conversion. → check: guidelines/ai-sdd-process.md
- [ ] **W13-AC3** WHEN work requires a person (provider account, keys, webhook, access, decision, review),
      THE estimate SHALL carry it on its own line with an owner and SHALL NOT add it to the development
      number. → check: guidelines/ai-sdd-process.md · skills/client-doc/SKILL.md · templates/client-doc.md
- [ ] **W13-AC4** WHEN calibrating, THE agent SHALL read commit timestamps within a session, not calendar
      days. → check: guidelines/ai-sdd-process.md
- [ ] **W13-AC5** THE plugin SHALL carry a writing standard covering documents, estimates and reports, and
      `client-doc`, `spec`, `frontend-handoff`, `final-check` SHALL reference it. → check:
      guidelines/writing-standards.md + the four skills
- [ ] **W13-AC6** THE interview calibration SHALL allow up to 2 rounds at L2 and up to 4 at L3/L4, and L2
      SHALL cover product forks, not blocking decisions alone. → check: guidelines/clarify-protocol.md
- [ ] **W13-AC7** WHEN a task touches money, permissions/access, client-visible behaviour, or an external
      integration at L2+, THE agent SHALL spend a round on it regardless of how settled the request
      sounds. → check: guidelines/clarify-protocol.md · skills/start-task/SKILL.md
- [ ] **W13-AC8** WHEN the level is L2 or above, THE first interview round SHALL offer the unbounded
      interview as a choice, and the signals SHALL determine whether it is recommended. → check:
      skills/start-task/SKILL.md · guidelines/clarify-protocol.md
- [ ] **W13-AC9** BEFORE presenting the plan, THE agent SHALL list every decision it made for the user
      with the cost of being wrong, or state that the list is empty. → check: skills/start-task/SKILL.md ·
      guidelines/clarify-protocol.md · guidelines/blind-spot-protocol.md
- [ ] **W13-AC10** `grill` SHALL remain user-invoked (`disable-model-invocation: true`). → check:
      skills/grill/SKILL.md
- [ ] **W13-AC11** THE SessionStart context SHALL state that a task described in chat enters through
      `start-task` without a command. → check: hooks/session-start.sh
- [ ] **W13-AC12** THE README SHALL describe the new estimate rule, the raised calibration, the standing
      offer, and the cost-of-silence list, and SHALL list `writing-standards` in the layout. → check:
      README.md

## Risks / assumptions

- **More questions is the intended cost.** The raised calibration trades some rounds for fewer rebuilt
  features. The guard against fatigue is question quality — recommendation first, plain language, no
  question spent on a lookup — not a lower cap. If it over-fires in practice, lower L2 back to one round
  before touching the mandatory-subject list, which is where the value is.
- **The depth question consumes one of four slots** in the first round from L2 up. Accepted: the user
  choosing the depth is worth more than a fourth decision question in round one.
- **Minute-level estimates may read as undervaluing the work** to a client who equates price with hours.
  The author decided this explicitly: real numbers, and the human-side table shows where his own time
  goes.
- **Commit-interval calibration assumes commits land near the work.** A repo that batches commits cannot
  be measured this way; the rule requires saying so rather than substituting a coefficient.
- **The SessionStart line costs context on every session** (~60 words) and only fires in a
  Groundwork-initialized project — a repo without `.groundwork.json` gets nothing.

## Rollout

Two commits, already made: `feat: v0.22.0 — estimate the agent's real build time…` and this wave's
v0.23.0 commit. No migration; the rules apply to the next task started.

## Verification plan

Structural for the whole wave: inspect each touched file against W13-AC1–AC12, and confirm `grill`'s
frontmatter is unchanged. `bash -n hooks/session-start.sh` passes. Behavioural checks the author runs in a
real project: start an L2 task that touches money as plain prose and confirm the first round contains the
depth question and a money question; then confirm the pre-plan response carries a cost-of-silence list.
Not yet run — this wave is verified structurally only.
