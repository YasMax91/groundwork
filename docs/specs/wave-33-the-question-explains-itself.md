# Spec: Wave 33 — the question explains itself (v0.42.0)

- Type: plugin self-improvement — one new guideline, one warn-only hook, edits to six skills and three
  guidelines. It changes every text the reader sees → **L3**.
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-09-17: *«Я хочу, чтобы плагин объяснял более человеческим языком перед тем,
  как спросить, а то агент какие-то слова и структуры понавыдумает, что я не понимаю, что от меня
  требуется и что нужно сделать»*. Second attempt at the complaint [Wave 9](wave-9-audience-and-language.md)
  answered — see **Why wave 9 did not close this** below.
- Status: **implemented** (2026-09-17).
- Target version: **v0.42.0**

## Why wave 9 did not close this

Wave 9 put the plain-language rule **inside the question**: the `AskUserQuestion` text, its option
labels, its descriptions, the blind-spot block, the client document. That is where the rule still lives
(`guidelines/clarify-protocol.md:36`), and it works — an option now reads as an outcome instead of a
field name.

The complaint that came back is about everything **around** the question. A reader who cannot follow
the fifteen sections that arrive before the interview, and who is never told what he is expected to do
with them, does not benefit from four well-written options at the bottom. Wave 9 fixed the sentence;
wave 33 fixes the page.

## What leaks today

Measured against v0.41.0 on 2026-09-17, each number from a grep over `skills/` and `guidelines/`.

1. **The rule binds to four surfaces, and none of them is the text that precedes a question.**
   "plain language" appears 14 times across the plugin and is defined once, at
   `clarify-protocol.md:36`. Its `Where it binds` list names the question text, the option labels and
   descriptions, the first-response report, the blind-spot block, and the client document. Nothing
   requires the agent to say **why it is asking** or **what the answer changes**.

2. **The first response is fifteen sections, and their names are the plugin's internals.** 
   `skills/start-task/SKILL.md:53-62` prescribes: current understanding · classification · files/docs to
   inspect · connections / blast radius · business/CRD areas affected · draft spec · acceptance criteria ·
   approaches · clarifications · blind spots · test plan (red list) · implementation plan · cost of
   silence · risks & assumptions · stop point. One of the fifteen — "current understanding" — names
   something the reader already has a word for. The plain-language opener sits **above** this list, so
   the two or three human sentences are followed immediately by fourteen engineering headings.

3. **The internal vocabulary has no chat spelling, so every agent invents its own.** Occurrences in the
   instruction files the agent reads before writing to chat: `slice` 45 · `checkpoint` 28 · `frontier`
   22 · `blind spot` 21 · `EARS` 12 · `AC<n>` 11 · `impact map` 10 · `Definition of Done` 10 ·
   `cost of silence` 8 · `blast radius` 6 · `red list` 6. Nothing marks any of them as internal, so they
   reach the reader translated ad hoc — «фронтир», «радиус поражения», «красный список», «цена
   молчания» — and differently on each run.

4. **"What the reader must now do" is prescribed exactly once, and not for chat.** The only two hits for
   the obligation are in `skills/client-doc/SKILL.md:2,28` — the document written *for a client*. No
   skill that writes to chat ends by saying whether the reader is expected to answer, to approve, or to
   do nothing.

5. **No hook has ever looked at the wording the reader receives.** Of the nine Stop and PreToolUse
   gates, `coverage-claim.sh` and `estimate-claim.sh` read the agent's text — both for a claim's
   honesty, neither for whether it can be understood.

## Design

### C1 — `guidelines/plain-language.md`, the one place the rule lives

The layered rule moves out of `clarify-protocol.md` into a guideline of its own, because its scope is no
longer the interview: it now governs every text the user reads in chat. `clarify-protocol.md` keeps a
pointer and its interview-specific anti-patterns — the fact lives in one file, per
`writing-standards.md`.

The new file carries the wave-9 rule unchanged (meaning first, identifier after, never delete the
technical layer) plus the three obligations below.

### C2 — the brief before the question

Before any `AskUserQuestion` call, and before the approaches block, the agent writes **three things in
plain sentences**:

- **what it established by itself** — so the reader sees the question is not laziness;
- **why this specific decision is his** — money, what a client sees, an access rule, a trade-off he
  lives with;
- **what changes in the working product** for each way it could go.

The brief is not a preamble in the `writing-standards.md` sense (see **The contradiction** below): every
sentence in it carries a fact the reader did not have. Two to five sentences. At L0/L1, where at most
one question is asked, one sentence is the whole brief.

### C3 — the ask line

Every message the agent ends a turn with closes on one line naming what the reader is expected to do:
answer the questions, approve the plan, run something on his machine, or nothing at all. The line is
last, it is one line, and "nothing — I continue" is a valid and frequent value. A turn that ends
mid-work without a question still carries it; that is the case where the reader most often cannot tell
whether he is being waited on.

### C4 — the term table

The guideline carries a two-column table: the plugin's internal term, and what it is called when the
reader is on the other end. The left column never appears in chat; the right column is not a
translation to be improvised per run.

| Internal | In chat |
|---|---|
| L0–L4 | how big the change is, in words — a typo, an ordinary feature, a risky one |
| blast radius / impact map | what else this touches |
| blind spots | what you did not ask about and would want to know |
| frontier / round | the questions that can be answered now |
| clarifications | what I need you to decide |
| cost of silence | what I decided for you |
| red list / red tests | the tests that must fail first |
| slice | a step of the work |
| AC / acceptance criteria | how we will know it is finished |
| Definition of Done | what counts as finished |
| checkpoint / task-state | my notes on this task |
| receipt | the report file for this task |
| conformance review | a check that what was built matches what we agreed |
| grounding | checked against the provider's own documentation |
| handoff | what the frontend developer gets |
| denominator / fraction | «5 of 7», spelled out |
| discovery | reading the code before planning |
| EARS | (never in chat — write the criterion as a sentence) |

A project's own vocabulary — a field name, an error code, an endpoint, a domain term from `AGENTS.md` —
is **not** on this table. Those stay, after the meaning, per the layered rule.

### C5 — `hooks/plain-language.sh`, warn-only, two events

The gate that reads the wording, on the `coverage-claim.sh` contract: inert without `.groundwork.json`
or `jq`, opt-out via `gates.plain_language: false`, every trigger logged to
`.claude/groundwork/plain-language.log`, and it never refuses anything.

- **PostToolUse on `AskUserQuestion`** — reads `tool_input`, joins every question, header, label and
  description, and matches the internal-term list. On a hit it returns `hookSpecificOutput.additionalContext`
  naming the terms found and the chat spelling for them. PostToolUse is the event where added context
  costs nothing: the tool has already run, so nothing is blocked and no turn is forced to continue.
  (`additionalContext` on **Stop** was rejected in wave 14 for exactly that reason and is not revisited.)
- **Stop** — reads `last_assistant_message` for two faults: an internal term with no chat spelling
  beside it, and a missing ask line. Emits `systemMessage` only, the loop guard (`stop_hook_active`)
  reused verbatim.

The asymmetry is deliberate. The interview round is where a correction still changes the reader's
experience — the next round, the plan, the closing report — so that one reaches the model. The Stop
notice reaches the user, and the log is what decides whether a later wave makes it blocking.

### C7 — the rule rides in the session context

A guideline is read when a skill points at it. The ask line is due on **every** turn, including the ones
no skill is driving, so one sentence joins `session-start.sh`'s injected context: chat is read by the
owner · the plugin's vocabulary never reaches it · every turn ends on the ask line · a question carries
its brief. It costs about sixty tokens a session, against a message the reader has to ask about.

### C6 — where it binds

Chat surfaces, all of them: the `start-task` first response and its approaches block · every
`AskUserQuestion` round · the blind-spot block · the cost-of-silence list, before the plan and at the
end · the `risk-review` findings · any estimate · the `final-check` handoff summary.

## Boundaries

Files written for developers do not change: `docs/ai/specs/*`, the receipt, OpenAPI annotations,
`docs/ai/frontend/*` (already Russian, already written for a person who reads code), ADRs, commit
messages, PR bodies. The rule is about the reader on the other end of the chat, not about lowering the
precision of an engineering document.

## The contradiction this spec resolves

`writing-standards.md` cuts "preambles and wrap-ups". C2 and C3 add text before the question and after
the report. The two are compatible on the standard's own test — **every sentence carries a fact the
reader does not already have** — and the guideline says so explicitly, because an agent that reads the
cut without the qualification will drop the brief to obey it:

- A preamble restates what the reader is about to see ("this document describes…", "below I will ask a
  few questions"). Still cut.
- A brief states what was found, why the decision is the reader's, and what each answer changes. Three
  facts he did not have.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | `guidelines/plain-language.md` exists and is the only definition of the layered rule; `clarify-protocol.md` points at it and no longer restates it | met |
| AC2 | The brief before the question is prescribed in the guideline and in `start-task` steps 7a and 8 | met |
| AC3 | The ask line is prescribed for every turn-ending message, with "nothing — I continue" valid | met |
| AC4 | The term table exists, covers the 11 measured terms, and excludes project vocabulary | met |
| AC5 | The preamble/brief contradiction is named and resolved in the guideline text | met |
| AC6 | `hooks/plain-language.sh` returns `additionalContext` on a PostToolUse `AskUserQuestion` whose text carries an internal term | met — 5 cases |
| AC7 | The same hook, on Stop, warns on an internal term and on a missing ask line, and stays silent when both are satisfied | met — 6 cases |
| AC8 | The hook is inert without `.groundwork.json`, under `gates.plain_language: false`, on a re-entrant Stop, on an empty payload, with no last message, and after any other tool | met — 6 cases |
| AC9 | The hook never refuses: exit 0 on every path, no `decision: block`, no `permissionDecision` | met — 3 cases |
| AC10 | Project vocabulary (`hide_financial`, an endpoint path, an error code) does not trigger the hook | met — 2 cases |
| AC11 | Every chat surface in C6 names the guideline | met |
| AC12 | The whole hook suite stays green, and the gate survives a missing `lib.sh` | met — 433 cases, 19 suites, the failsafe row included |
| AC13 | The ask line and the vocabulary rule reach every session through `session-start.sh` | met — 15 cases in that suite stay green |

## Files

- new: `guidelines/plain-language.md`, `hooks/plain-language.sh`, `hooks/tests/plain-language.sh`
- changed: `hooks/hooks.json` (PostToolUse `AskUserQuestion`, Stop), `hooks/tests/all.sh`,
  `hooks/tests/failsafe.sh`, `hooks/session-start.sh` (one line of session context),
  `templates/project/.groundwork.json` (`gates.plain_language`)
- changed: `guidelines/clarify-protocol.md` (rule moves out, pointer stays),
  `guidelines/blind-spot-protocol.md`, `guidelines/writing-standards.md` (the brief is not a preamble)
- changed: `skills/start-task`, `skills/final-check`, `skills/risk-review`, `skills/estimate`,
  `skills/spec`, `skills/implement-approved`
- changed: `README.md`, `.claude-plugin/plugin.json` → `0.42.0`

## Deliberately not done

- **Shortening the first response.** The fifteen sections stay; the author chose the brief and the
  vocabulary over a shorter report. A reader who understands the sections can use them, and cutting them
  would move the information into a file nobody opens.
- **Blocking on the wording.** A regex over natural language misfires, and a gate that refuses a
  question would leave the agent rewriting it in a loop. Warn-only, with the log as the evidence for a
  later decision — the path `coverage-claim.sh` has been on since wave 14.
- **A PreToolUse gate on the question itself.** It is the event that could stop a bad question before
  the reader sees it, and the only way to reach the model there is `permissionDecision: deny` — a block
  by another name.
