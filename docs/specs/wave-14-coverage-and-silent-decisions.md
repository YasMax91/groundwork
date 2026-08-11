# Spec: Wave 14 — a verification claim carries its denominator, and a silent decision does not stay silent (v0.24.0)

- Type: plugin self-improvement. Two author complaints that are one failure seen from two sides →
  **L3** (cross-cutting change to what every L2+ task must output).
- Author: Max Yastremskyi (YasMax91).
- Source: author feedback, 2026-08-11, during the modernization research pass. Two statements: "no more
  *I checked selectively* or *I only went over it superficially*", and "when I am not competent
  somewhere, or do not realise something, the agents should highlight it for me".
- Research and options: [modernization-research-2026-08.md](modernization-research-2026-08.md), items
  E25 and E24. The output-channel spike is recorded there and its result is binding on A4 below.
- Status: **implemented** (2026-08-11). Hook behaviour is proven by 26 new tests (163 across 9 suites,
  all green); the prose changes are structural. No behavioural run in a real task has been recorded yet,
  and the interactive visibility of `systemMessage` (A4c) is still unobserved.
- Target version: **v0.24.0**.

## Goal

Work stops reading as finished when what is missing was never named. Two mechanisms:
a verification claim must state the set it covered, and a decision the agent took alone must be
visible at the end of the task, not only before the plan.

## Problem (diagnosis)

### A. A coverage claim with no denominator

The rules that should have caught this exist and do not bite.

1. **The unconditional rule names the wrong thing.** `ai-sdd-process.md` §Definition of Done requires,
   at every level, "state what stayed unverified". The phrase *I checked it selectively* satisfies it
   literally — something unverified was stated. What is never required is the **set** the claim is
   measured against, so the reader cannot tell whether "selectively" means eight of nine or one of
   nine.
2. **`writing-standards.md` bans hedging around checkable facts** and requires a report to carry "what
   was verified and how · what stayed unverified". It does not require a number, so a qualitative
   hedge passes a rule written against hedging.
3. **The one place a denominator already exists is unenforced.** The L2+ Definition of Done says every
   consumer of a touched shape is verified "per the impact map" or noted out of scope. The impact map
   is an enumerable set — the only one in the whole protocol — and nothing checks that the report
   walked it.
4. **Nothing observes the final message.** Four Stop gates run format, static analysis, tests, and
   OpenAPI. None reads what the agent actually said, which is where the claim lives.

### B. A decision taken alone after the plan

1. **Cost of silence fires once, at the earliest possible moment.** Wave 13 put it at `start-task`
   step 8a, before the plan — when the agent knows least. Every implementation decision made after
   approval is outside it.
2. **`final-check` re-passes for blind spots, not for decisions.** `blind-spot-protocol.md` §How to run
   it has `final-check` re-pass "for blind spots the finished implementation itself created". A blind
   spot is something nobody saw. A decision the agent made deliberately, without asking, is not a blind
   spot and falls through the gap between the two.
3. **The taxonomy is shaped like an engineering checklist.** Its seven categories run from data and
   state to external integrations; category 6 covers domain and product. None of them asks the question
   the author's complaint is actually about: *what does this change assume the reader knows, and has he
   ever confirmed it?*

## Spike result — binding on the design

Run on Claude Code 2.1.212, 2026-08-11. Full record in the research document.

- The `Stop` hook receives `last_assistant_message` verbatim. Also present: `stop_hook_active`,
  `transcript_path`, `permission_mode`, `effort`.
- `hookSpecificOutput.additionalContext` **continues the turn** — the hook fired again with
  `stop_hook_active: true` and the model answered the notice on the record. It is a soft block, not a
  warning, and therefore cannot implement warn-only.
- `systemMessage` **ends the turn**. It did not appear in the headless `stream-json` output; its
  visibility in an interactive session is the one open item (A4c).
- Given the notice, the model refused to invent a fraction where no verification had happened. The
  format must name that outcome explicitly, or the rule will push toward fabricated numbers.

## Design — per item

### A1 — The claim format

`guidelines/writing-standards.md` §Estimates and reports gains the denominator rule. Every claim about
verification takes exactly one of three forms:

- **Total** — "exercised 7 of 7 endpoints on the impact map".
- **Partial** — the fraction plus the enumerated remainder, each with its reason: "ran 3 of 12; the
  other 9 are «…», not run because «…»".
- **None** — "no verification was performed", stated plainly.

The denominator comes from a set named in the same sentence and enumerable from the work itself: the
impact map's consumers, the route list, the acceptance-criterion IDs, the changed files, the states of
a workflow. **A fraction is never estimated.** Where no set can be enumerated, the answer is the third
form, not a guess — this is the same rule as `grounding-protocol`'s "don't guess instead of check",
applied to the report rather than to the research.

### A2 — Calibrated by level, from the first line

The lesson of Wave 12 is that a rule written without a level becomes 32 obligatory actions on a typo.

- **L0** — nothing. The automatic gates are the whole Definition of Done.
- **L1** — one sentence, the third form permitted: what single thing was exercised live, and that
  nothing else was touched. No fractions.
- **L2+** — the fraction, per claimed set.

### A3 — "Not covered" and "done" cannot both be true

`ai-sdd-process.md` §Definition of Done (L2+): an item enumerated as not covered appears as its own
line in the final report and is not absorbed into prose. The existing "or the consumer noted out of
scope" escape stays, and gains its missing half — the note states **who** put it out of scope. An
agent may propose it; the report shows whether the user accepted it.

### A4 — The gate (warn-only in this release)

New `hooks/coverage-claim.sh`, registered on `Stop` alongside the existing three.

- **a. What it reads.** `last_assistant_message`. Markers in both languages, held in one editable list
  at the top of the script: `выборочно` · `поверхностно` · `частично` · `бегло` · `вроде бы` ·
  `spot-check` · `briefly` · `superficially` · `should work` · `probably fine` · `mostly`.
- **b. What it decides.** A marker alone is not a fault — it is often the honest word. The fault is a
  marker **with no accompanying fraction and no uncovered list** in the same message. On a fault it
  emits `systemMessage` naming the marker and asking for the fraction plus the gap, and appends one
  line to `.claude/groundwork/coverage-claims.log`. It returns `{}` when `stop_hook_active` is true,
  and it never blocks in this release.
- **c. The visibility fallback.** If `systemMessage` proves not to reach the user in an interactive
  session, the notice goes to the plugin's existing status line, which already carries gate state.
  Decide this by observation in the first session after release, not by assumption.
- **d. Fail-open, like every other hook.** No `.groundwork.json` → silent no-op. New toggle
  `gates.coverage_claim`, default **on** inside Groundwork projects.
- **e. The measurement that unlocks blocking.** The log is the evidence. The wave that turns blocking
  on must publish the observed false-positive rate; without that number blocking is not enabled.

### A5 — The reviewers learn the rule

`agents/conformance-reviewer.md` and `agents/adversarial-verifier.md`: a verification claim carrying no
denominator is itself a finding, reported like any other gap. This is the layer that catches a claim
phrased so smoothly that no marker appears in it.

### B1 — The closing cost of silence

`skills/final-check/SKILL.md` gains a closing block, and `guidelines/clarify-protocol.md` §Cost of
silence gains its second half: every decision the agent took without asking **since plan approval** —
what was decided · the alternative not taken · what changes if it was wrong. One line each, plain
language first. An empty list is stated as empty, which is itself a claim.

Two boundaries keep it from becoming ceremony:

- **Threshold** — an item earns its line only if the agent decided it alone **and** it changes
  observable behaviour, money, permissions, or a contract. Everything else is an implementation detail.
- **No duplication** — a decision already listed before the plan is not repeated; this block covers
  what happened after approval.

### B2 — The competence axis in the taxonomy

`guidelines/blind-spot-protocol.md` §Taxonomy gains category 8, **Unconfirmed assumptions about the
reader's own domain**: what this change assumes is known about the business domain, the provider's
rules, the financial or legal consequence, and what the client will do with the result — and which of
those assumptions the author has never confirmed in this project. `agents/blind-spot-mapper.md` carries
it in its prompt.

This is what "I did not realise" means in practice, and it is distinct from category 6: *Domain &
product* asks whether the change solves the right problem; category 8 asks what the change silently
requires the reader to already know.

### B3 — Level calibration for B1

- **L0/L1** — the closing block appears only if an item clears the threshold; otherwise nothing.
- **L2+** — the block is mandatory; "none" is a valid content.

### Deferred, deliberately

Cross-session accumulation of blind spots through subagent `memory: project` (research item E19) is
**not** in this wave. It rests on a capability this build has not been observed to honour for plugin
subagents, and a memory file is an unverified claim that the next session inherits as a premise —
the failure the Wave 11 checkpoint-accuracy rule exists to prevent. It needs its own spike.

## Acceptance criteria (EARS)

- [ ] **W14-AC1** WHEN any skill reports verification at L2+, THE report SHALL state a covered/total
      fraction against a named enumerable set, per claimed set. → check: guidelines/writing-standards.md ·
      guidelines/ai-sdd-process.md
- [ ] **W14-AC2** WHEN no set can be enumerated, THE report SHALL state that no verification was
      performed and SHALL NOT estimate a fraction. → check: guidelines/writing-standards.md
- [ ] **W14-AC3** THE claim rule SHALL be calibrated per level: nothing at L0, one sentence without a
      fraction at L1, fractions at L2+. → check: guidelines/ai-sdd-process.md §Definition of Done
- [ ] **W14-AC4** WHEN an item is enumerated as not covered, THE final report SHALL carry it as its own
      line, and an out-of-scope note SHALL state who put it out of scope. → check:
      guidelines/ai-sdd-process.md
- [ ] **W14-AC5** WHEN the final message contains a partiality marker and carries neither a fraction nor
      an uncovered list, THE Stop hook SHALL emit a notice naming what is missing, at most once per
      turn. → check: hooks/coverage-claim.sh + hook test
- [ ] **W14-AC6** WHEN `stop_hook_active` is true, THE hook SHALL return an empty object and emit
      nothing. → check: hook test
- [ ] **W14-AC7** THE hook SHALL NOT block in v0.24.0, and SHALL append one line per trigger to a log
      readable as a false-positive rate. → check: hooks/coverage-claim.sh + hook test
- [ ] **W14-AC8** WHEN `.groundwork.json` is absent OR `gates.coverage_claim` is false, THE hook SHALL
      be a silent no-op. → check: hook test
- [ ] **W14-AC9** THE conformance-reviewer and adversarial-verifier SHALL treat a denominator-free
      verification claim as a reportable finding. → check: agents/conformance-reviewer.md ·
      agents/adversarial-verifier.md
- [ ] **W14-AC10** WHEN implementation completes at L2+, THE closing report SHALL list every decision
      made without asking since plan approval, or state that there were none. → check:
      skills/final-check/SKILL.md · guidelines/clarify-protocol.md
- [ ] **W14-AC11** THE closing list SHALL exclude items that do not change observable behaviour, money,
      permissions, or a contract, and SHALL NOT repeat items already listed before the plan. → check:
      guidelines/clarify-protocol.md
- [ ] **W14-AC12** THE blind-spot taxonomy SHALL carry a category for unconfirmed assumptions about
      domain, provider rules, financial/legal consequence, and client use, and `blind-spot-mapper` SHALL
      receive it. → check: guidelines/blind-spot-protocol.md · agents/blind-spot-mapper.md
- [ ] **W14-AC13** THE README SHALL describe the denominator rule, the warn-only gate, and the closing
      cost-of-silence list. → check: README.md

## Risks / assumptions

- **A regex over natural language over-fires, and the surface is bilingual.** This is why the release
  warns instead of blocking, keeps the marker list in one editable place, and logs every trigger. If the
  log shows the markers firing mostly on honest sentences, the fix is the marker list, not the rule.
- **The gate cannot see a smooth claim.** "Verified the endpoint works" carries no marker and no
  denominator. The hook catches the crude form; A5 puts the general form where a reviewer reads it. The
  hook is the cheap layer, not the complete one.
- **Two new obligatory outputs at the end of every L2+ task** is the exact asymmetry Wave 12 unwound.
  Both carry level calibration in this spec rather than after the fact (A2, B3), and neither applies at
  L0.
- **The third form can become an excuse.** "No verification was performed" is honest when nothing was
  run and evasive when a set existed and was skipped. The rule allows it only for the former; the
  Definition of Done's live-run requirement is untouched and still applies at L1+.
- **`systemMessage` visibility is unproven in an interactive session** (spike, headless only). A4c
  names the fallback and the release must confirm which channel is used.
- **Human step:** reading `coverage-claims.log` after a handful of real sessions and deciding whether
  blocking turns on. That decision is the author's, not the agent's.

## Plan

Test-first for the hook, per Wave 11's precedent — the two blocking defects that wave introduced were
caught by its own tests.

1. `hooks/tests/coverage-claim.sh` — marker with no fraction, marker with a fraction, marker with a gap
   list, `stop_hook_active` true, missing `.groundwork.json`, toggle off, log append. Wire into
   `hooks/tests/all.sh`.
2. `hooks/coverage-claim.sh` + `hooks/hooks.json` registration, sourcing `hooks/lib.sh` fail-safe like
   the other four.
3. The prose: `writing-standards.md` (A1), `ai-sdd-process.md` (A2, A3), `clarify-protocol.md` (B1),
   `blind-spot-protocol.md` (B2, B3), `final-check/SKILL.md` (B1), the two review agents (A5).
4. `README.md`, version bump to v0.24.0, `templates/project/.groundwork.json` gains
   `gates.coverage_claim`.
5. Conformance pass against W14-AC1…AC13 before the commit.

Estimated agent build time: **2–2.5 hours**, the hook and its tests being roughly half. The human steps
— reading the log, deciding on blocking — are not included in that number.
