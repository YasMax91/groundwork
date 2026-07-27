# Spec: Wave 12 — calibration & conflict resolution (plugin v0.17.0)

- Type: plugin self-improvement — **subtractive**: level-calibration and conflict removal across the
  rules Waves 8–11 added, plus one small gate-cache. Cross-cutting change to when rules apply → **L3**.
- Author: Max Yastremskyi (YasMax91). Owner: RaDevs.
- Source: an adversarial audit of the *combined* rule set after Waves 8–11 (2026-07-27), run before the
  author started using v0.16.0. It returned **REFUTED** with 16 findings — 4 high — every one of which was
  independently re-verified against the source before this spec was written.
- Status: **implemented & verified** (2026-07-27) — 109 hook tests, all suites green. The first pass was
  re-audited and **REFUTED**: it had shipped a green-run cache that could report green over a red suite,
  and a comment-only detector bypassable three ways. Both were fixed (the cache withdrawn outright), each
  bypass reproduced as a failing test first. Honest note: two of this wave's own tests were initially
  **false-green** — they rewrote whole files, so the diff contained a removed code line and never
  exercised the append-only case the audit used.
- Target version: v0.17.0

## Goal

Waves 8–11 closed the complaint "you said it was done and it wasn't". They opened a new one: **every rule
they added was written without a level.** Everything the plugin had *before* them scales across L0–L4 —
fan-out, TDD, the interview, blind spots, conformance review. Everything added *by* them — live
verification, consumer coverage, class-audit, domain-drift, the runnable request package, sub-request
re-mapping, the plain-language opening — applies unconditionally.

The measured result: changing the text of one 422 message now demands **~32 obligatory actions** and four
new artifacts. That is the friction the author complained about in the first place, re-created from the
other direction.

Wave 12 adds no new capability. It **calibrates what Waves 8–11 added and removes the contradictions they
introduced**, so the cheap path exists again and no rule tells the agent to do two opposite things.

## Problem (diagnosis)

Each finding re-verified directly, not taken on the auditor's word:

1. **The Definition of Done has no levels.** `grep` for `L0|L1|L2|L3|L4` inside
   `guidelines/ai-sdd-process.md`'s Definition of Done section returns **0**. It lists live verification,
   consumer coverage, domain-contract currency, and the frontend handoff as unconditional — for a typo fix
   as much as for a payment flow.
2. **The self-review checklist contradicts itself, two lines apart.**
   `guidelines/ai-sdd-process.md:132` asks "only related files changed?"; `:139` asks "a user-reported
   defect audited as a class, not point-patched?" — while `skills/implement-approved/SKILL.md:18` says
   "keep changes scoped to the task" and `ai-sdd-process.md:97` requires human approval for a broad
   refactor. A user-reported defect makes all four fire at once, and they cannot all be satisfied.
3. **`final-check` breaks the OpenAPI gate's only escape hatch, in the same turn.**
   `skills/final-check/SKILL.md` closes by allowing the checkpoint to be **deleted**, while
   `hooks/openapi-gate.sh:84-88` reads `OpenAPI: n/a — <reason>` *from that file* at Stop, against the
   still-uncommitted working tree. An internal refactor that legitimately declared `n/a` deletes its own
   exemption and is then blocked by the gate.
4. **`frontend-handoff` demands evidence `final-check` may legitimately not have.**
   `skills/frontend-handoff/SKILL.md` requires captured real success/error responses and forbids
   documenting a value the live run could not produce — but `skills/final-check/SKILL.md` explicitly
   allows the live run to be skipped when the app or browser is unreachable, and the handoff doc is
   "always create one". No degraded mode is described.
5. **`spec` orders an impossible action.** `skills/spec/SKILL.md:50` says "**run** `grill`", but
   `skills/grill/SKILL.md:3` is `disable-model-invocation: true` — the model cannot invoke it — and both
   `clarify-protocol.md` and `start-task` say "offer it; never start it unasked".
6. **Documentation contradicts the code on a default.** `README.md:103`, `README.md:163`, and
   `guidelines/working-memory.md:109` all state `test_lock_wait_seconds` defaults to **300**;
   `hooks/test-gate.sh:59` and the project template say **45**. Following the docs (300) would exceed a
   conservative harness hook timeout and kill the very message the wait exists to print.
7. **Review-agent calibration is stated three incompatible ways.** `ai-sdd-process.md` fan-out gives L2 a
   single `impact-mapper` and reserves the verifiers for L3/L4; `final-check` requires the
   conformance-reviewer at **L2+**; Review mode and `grounding-protocol.md` describe the
   adversarial-verifier as unconditional — yet **no skill spawns it**.
8. **A blind spot can be trapped with nowhere to go.** `blind-spot-protocol.md` says an item needing a
   product call "does not stay a bullet" and must become an interview question, while
   `clarify-protocol.md` forbids non-blocking questions at L0/L1 and limits L2 to blocking decisions only.
9. **Sub-request re-mapping defaults to the most expensive fan-out.**
   `skills/implement-approved/SKILL.md` re-spawns `impact-mapper` whenever new seeds appear and says a
   borderline case counts as a scope change — while `working-memory.md` calls that agent "the most
   expensive fan-out in discovery".
10. **The Stop gates re-run on every turn.** `hooks/test-gate.sh` / `done-gate.sh` fire whenever any
    uncommitted `.php` exists — and every `AskUserQuestion` round ends a turn. An L3 interview can pay for
    three full suite runs before a line of code is written, then again on "commit?", then again on every
    later turn until the work is committed.
11. **The OpenAPI gate blocks L0.** It fires on any changed `.php` under the contract surface — including
    a comment typo — but its exemption lives in a checkpoint that an L0 task, by process, never creates.
12. **Smaller:** who asks about committing for a purely internal change is ambiguous across three files ·
    "no file is edited before approval" is stated absolutely while `start-task` must write the checkpoint ·
    the AI-hours format is imposed on any chat estimate · the bilingual mirror rule reaches BA question
    lists the user never asked to send · `tinker` is offered as the live-run vehicle with no non-interactive
    form (`--execute`), so it would hang.

## Design — per item

### C1 — Level-calibrate the Definition of Done (the core fix)

`guidelines/ai-sdd-process.md` gains an explicit **per-level DoD** so the cheap path exists again:

- **L0** (typo, comment, docs) — the gates that fire on their own, and nothing else. No live run, no
  consumer sweep, no domain-drift check, no frontend handoff, no approach block, no interview.
- **L1** (small bug fix) — the gates, a fail-first regression test, and a live exercise **of the one thing
  fixed** (not a consumer sweep). Domain-drift, the runnable package, and the full handoff apply only if
  the change actually touched the frontend-facing contract.
- **L2+** — the full Definition of Done as it stands today.

Every unconditional rule Waves 8–11 introduced is tagged with the level it starts at, in the file that
owns it (`final-check`, `frontend-handoff`, `implement-approved`), so a reader cannot meet the rule
without meeting its calibration.

### C2 — Class-audit becomes "surface the class, fix what is approved"

The rule keeps its value (one reported defect means the class was never verified) but stops colliding with
scope discipline and the approval gate. Reworded in `skills/final-check/SKILL.md` and
`guidelines/ai-sdd-process.md`: **enumerate every sibling site and report it**; fix the reported instance
plus siblings that fall inside the approved scope; anything wider is offered as a **named follow-up slice
with its own approval**, not folded in silently. The self-review line changes from "audited as a class" to
"class enumerated, and each sibling fixed or offered as a slice".

### C3 — The checkpoint outlives the gate that reads it

`skills/final-check/SKILL.md`: the checkpoint may be marked done, but **not deleted while the working tree
still holds an uncommitted contract-surface change** — the `openapi` gate reads its `OpenAPI:` line at
Stop, before the commit exists. Deletion is legal once committed, or when the task never touched the
contract. `guidelines/working-memory.md` records the dependency so the coupling is visible from both ends.

### C4 — A stated degraded mode for the handoff

`skills/frontend-handoff/SKILL.md`: when the live run did not happen (app unreachable — the case
`final-check` explicitly permits), the handoff is still produced, with every example marked
**`UNVERIFIED — derived from the FormRequest / JsonResource, not observed`**, and the reachability rule
degrades from a prohibition to a flagged assumption. Silence about it is the only forbidden option.

### C5 — Consistency repairs

- `skills/spec/SKILL.md` — "run `grill`" → **offer** `/grill`, matching the two files that already say so.
- `README.md` ×2 and `guidelines/working-memory.md` — `test_lock_wait_seconds` default **300 → 45**.
- Review-agent calibration is stated **once** in `ai-sdd-process.md`'s fan-out table (conformance-reviewer
  at L2+, adversarial-verifier for "it works" claims at L3/L4 and whenever an external capability claim is
  made); `final-check`, Review mode, and `grounding-protocol.md` point at it instead of restating it.
- `guidelines/blind-spot-protocol.md` — a third path: an item that does not clear the interview
  calibration is **recorded as an explicit assumption** in the first response and the spec, never dropped
  and never forced into a question the level forbids.
- `skills/implement-approved/SKILL.md` — a new sub-request re-spawns `impact-mapper` only when its seeds
  include a **model, table, or service**; a Resource/Request/string-level addition gets a self-trace.
- `guidelines/ai-sdd-process.md` — the "no file edited before approval" rule names its one standing
  exception (the checkpoint under `.claude/groundwork/`), which `pre-tool-guard.sh` already implements.
- `guidelines/ai-sdd-process.md` — the AI-hours **format** binds documents and explicit estimate requests,
  not every passing remark about time.
- `skills/client-doc/SKILL.md` — the bilingual mirror binds text **the user will send onward**, not
  internal question lists.
- `skills/final-check/SKILL.md` + `guidelines/grounding-protocol.md` — give the non-interactive form of the
  live run (`artisan tinker --execute="…"`), since a bare `tinker` hangs in a non-interactive shell.

### C6 — WITHDRAWN: the green-run cache (added, then removed the same day)

A digest-based cache was built so a repeated Stop would not re-run an identical suite. The re-audit
**refuted both its premise and its safety**, and it was removed entirely rather than repaired:

- **The premise was wrong.** The original finding claimed an interview paid for three suite runs.
  Measured: a turn with no changed `.php` exits before running anything — an interview round cost
  **zero** runs, before and after. Real saving: ~1 repeat per task.
- **It could lie.** The digest covered only uncommitted `.php`, so a changed fixture, `phpunit.xml`,
  `.env.testing`, `composer.lock`, or freshly pulled commits produced "already green" over a **red**
  suite (reproduced). In a monorepo whose git root sits above the app, it degraded to hashing paths and
  went permanently false-green (reproduced).

A mechanism that can report green over red is the exact failure Waves 8–11 existed to remove, and it was
buying one skipped run. Removed: `gates.reuse_green_run`, the digest helper, and both README claims.

### C7 — The OpenAPI gate ignores comment-only changes

`hooks/openapi-gate.sh`: when every changed contract-surface hunk consists solely of comment or blank
lines, the contract cannot have changed — treat it as untouched instead of demanding an annotation update
and a checkpoint an L0 task never creates.

## Acceptance criteria (EARS)

- [x] **W12-AC1** THE Definition of Done SHALL state, per level, which checks apply — L0 gates only, L1
      gates + regression test + a live exercise of the fixed behaviour, L2+ the full list — AND every rule
      Waves 8–11 added SHALL carry the level it starts at in its owning file.
      → check: guidelines/ai-sdd-process.md + skills/final-check/SKILL.md + skills/frontend-handoff/SKILL.md
- [x] **W12-AC2** THE class-audit rule SHALL require enumerating and reporting the sibling class, fixing
      what is in approved scope, and offering the rest as a named follow-up slice — AND the self-review
      SHALL NOT ask for both "only related files changed" and an unbounded class fix.
      → check: skills/final-check/SKILL.md + guidelines/ai-sdd-process.md
- [x] **W12-AC3** THE checkpoint SHALL NOT be deleted while an uncommitted contract-surface change is in
      the working tree, and the dependency on the `openapi` gate SHALL be stated where the checkpoint is
      defined. → check: skills/final-check/SKILL.md + guidelines/working-memory.md
- [x] **W12-AC4** WHEN the live run did not happen, THE frontend handoff SHALL still be produced with
      examples marked `UNVERIFIED` and the reachability rule degraded to a flagged assumption.
      → check: skills/frontend-handoff/SKILL.md
- [x] **W12-AC5** THE `spec` skill SHALL offer `/grill` rather than instruct the agent to run it.
      → check: skills/spec/SKILL.md
- [x] **W12-AC6** THE documented default for `test_lock_wait_seconds` SHALL be 45 everywhere, matching the
      code and the template. → check: README.md + guidelines/working-memory.md + hooks/test-gate.sh
- [x] **W12-AC7** THE review-agent calibration SHALL exist in exactly one place, with the other files
      pointing at it. → check: guidelines/ai-sdd-process.md + skills/final-check/SKILL.md + guidelines/grounding-protocol.md
- [x] **W12-AC8** THE blind-spot protocol SHALL provide an explicit third path (recorded assumption) for an
      item that the interview calibration will not admit as a question.
      → check: guidelines/blind-spot-protocol.md
- [x] **W12-AC9** THE sub-request re-map SHALL re-spawn `impact-mapper` only for model/table/service seeds,
      with a self-trace otherwise. → check: skills/implement-approved/SKILL.md
- [x] **W12-AC10** *(withdrawn — see C6)* THE green-run cache SHALL NOT ship: it was measured to save
      ~1 run while able to report green over a red suite. Verified absent.
      → check: hooks/ (no `reuse_green_run`, no digest helper) + README.md
- [x] **W12-AC11** WHEN a contract-surface file changed only in comments or blank lines, THE openapi gate
      SHALL treat the contract as untouched — AND SHALL NOT be fooled by (a) a PHP 8 `#[Attribute]`, which
      opens with `#` but is code, (b) a line opening with `/*` that carries code after it, or (c) an `OA\`
      token anywhere in the diff; AND it SHALL waive only the "annotations must change" demand, never the
      broken-generation check. → check: hooks/openapi-gate.sh + hooks/tests/openapi-gate.sh (AC16–AC22)
- [x] **W12-AC12** THE remaining consistency repairs SHALL land: the approval rule names the checkpoint
      exception, the AI-hours format binds documents and explicit estimate requests, the bilingual mirror
      binds outbound text, and the live-run instruction gives a non-interactive `tinker --execute` form.
      → check: guidelines/ai-sdd-process.md + skills/client-doc/SKILL.md + skills/final-check/SKILL.md + guidelines/grounding-protocol.md
- [x] **W12-AC14** THE partial findings from the re-audit SHALL be closed: the `final-check` self-review
      carries the same level tags as the section above it; the L0 calibration does not switch off the
      honesty rules; a blind spot the interview cannot admit is a recorded assumption in `start-task` and
      `clarify-protocol` too; the Implementation-mode re-map wording matches the seed-type calibration; and
      a purely internal change still gets asked about committing.
      → check: skills/final-check/SKILL.md + skills/start-task/SKILL.md + guidelines/clarify-protocol.md + guidelines/ai-sdd-process.md
- [x] **W12-AC13** `.claude-plugin/plugin.json` SHALL be `0.17.0`; README and the roadmap SHALL record the
      calibration; AND all hook suites SHALL stay green.
      → check: .claude-plugin/plugin.json + README.md + plugin-enhancement-roadmap.md + hooks/tests/all.sh

## Risks / assumptions

- **Calibrating could re-open the original complaint (primary).** Waves 8–11 exist because "done" was
  claimed without proof; loosening L0/L1 must not restore that. Mitigation: what L1 drops is *breadth*
  (consumer sweep, domain-drift, handoff package), never *proof* — a fixed bug still needs its regression
  test and a live exercise of the thing fixed, and the honesty rules ("state what stayed unverified",
  "never report green tests as works-live") remain unconditional at every level.
- **The green-run cache could mask a regression.** Mitigated by digesting file *contents*, not timestamps:
  any edit invalidates it. It also never suppresses a *failing* result — only a repeat of an identical
  green one.
- **Comment-only detection could be fooled** by an annotation inside a comment block — which is exactly how
  PHP attributes/annotations are written. Mitigation: treat a hunk as comment-only only when it contains no
  `OA\` token and no non-comment code line; when in doubt, fall through to the existing behaviour (demand
  the annotation), because a false block is recoverable and a false pass is not.
- **Assumption.** The auditor's count of ~32 obligatory L1 actions is directionally right rather than
  exact; the calibration is justified by the asymmetry (every pre-Wave-8 rule scaled, every new one did
  not), which is verifiable, not by the precise number.

## Rollout

- Version **v0.17.0**. Mostly subtractive prose; two small hook changes (green-run cache, comment-only
  detection), both opt-out and fail-open, both test-first.
- Commit: `fix: v0.17.0 — calibrate waves 8-11 by task level, resolve rule conflicts, harden comment-only detection`.

## Verification plan

Re-run the full hook suite plus the new cases. Re-run the integrity and end-to-end scripts. Then re-run the
**same adversarial audit prompt** that produced these 16 findings and confirm the high ones are gone —
the audit that found the problem is the audit that must clear it.
