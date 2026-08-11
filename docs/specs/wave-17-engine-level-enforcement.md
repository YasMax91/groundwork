# Spec: Wave 17 — two rules stop being sentences in a prompt (v0.27.0)

- Type: plugin self-improvement → **L2** (two hooks, two test suites, three prose files).
- Author: Max Yastremskyi (YasMax91).
- Source: research items E13 and E14 in
  [modernization-research-2026-08.md](modernization-research-2026-08.md).
- Status: **implemented** (2026-08-11). Both mechanisms verified against a live session before design;
  hook behaviour proven by 39 new tests (211 across 11 suites, all green).
- Target version: **v0.27.0**.

## Goal

Two rules the plugin already owned were enforced only by asking an agent to follow them. Move both to
the engine, each in the narrowest form that does the job.

## Problem (diagnosis)

### A. The protocol engages at session start, tasks arrive all session long

v0.23.0 added one line to the `SessionStart` context: a task described in chat enters through
`start-task` with no command from the user. It fixed the right problem — the author writes tasks as
prose, so the protocol could not depend on him invoking a skill — in the wrong place. `SessionStart`
fires once. The sessions where this matters are the long ones, 450–1350 messages, where the tenth task
is stated tens of thousands of tokens after that line.

### B. "Never guess" was a prompt, not a gate

`grounding-protocol` rule 1 requires every claim to carry a source or be marked `UNKNOWN`, and
`adversarial-verifier` is required to end on a verdict. Both live in the agents' own system prompts, so
compliance is a matter of the model following instructions in a long context — the exact class of
failure Wave 2 moved out of prose for the runner and migration rules.

## Spike — run before the design, binding on it

Claude Code 2.1.212, isolated project, `SubagentStop` hook dumping stdin, driven by `claude -p`.

| Question | Result |
|---|---|
| Does `SubagentStop` fire and carry the agent's answer? | **Yes.** Payload has `agent_type`, `agent_id`, `last_assistant_message` in full, `agent_transcript_path`, and `stop_hook_active` |
| Does a `matcher` on the agent type work? | **Yes** — `^Explore$` matched and fired only for that agent |
| Does `decision: "block"` actually send the subagent back? | **Yes.** Given "your report cites no source", the Explore agent reran and returned a rewritten answer with `SOURCE:` on each claim |
| Is there a loop guard? | **Yes** — the re-entry arrived with `stop_hook_active: true`, so no per-agent marker file is needed |

The last row changed the design: the first draft carried an `agent_id` marker file that is now
unnecessary.

## Design

### A1 — `hooks/task-intent.sh` (`UserPromptSubmit`)

Fires when a prompt states work to be done **and** the checkpoint has no mode. Adds
`additionalContext` naming the flow the task should enter; **never blocks**.

Silence in every other case, each one a deliberate carve-out:

- a mode is set → the protocol is already engaged, and the marker resets so the *next* task gets the
  reminder;
- the prompt opens with a question word in either language → a question about the code is not an
  instruction to change it;
- fewer than five words → counted in words, not characters, because `${#var}` counts bytes and a
  three-word Russian thank-you would clear any byte threshold;
- the prompt starts with `/` → the user is driving the protocol himself;
- it already fired this session while the mode is still unset → a reminder that repeats every prompt
  trains the reader to skip it.

### A2 — `hooks/agent-contract.sh` (`SubagentStop`)

Matched to `^groundwork:(grounded-researcher|adversarial-verifier)$`. A researcher's answer must carry a
URL, a repository document, a `file:line`, or `UNKNOWN`; a verifier's must carry `CONFIRMED`, `REFUTED`
or `UNCERTAIN`. Otherwise `decision: "block"` with a reason that says what to add.

It checks that a claim **carries evidence**, not that the evidence is good — a string match cannot judge
a source, and pretending otherwise would be the same overreach the plugin warns about elsewhere. Blocks
at most once per run (`stop_hook_active`), touches no other agent, silent without `.groundwork.json`.

### A3 — Prose

`grounding-protocol.md` states that rule 1 is now gated for those two agents, and the limit of what the
gate checks. `README.md` documents both toggles. `templates/project/.groundwork.json` gains
`gates.task_intent` and `gates.agent_contract`, both default on.

## Acceptance criteria (EARS)

- [x] **W17-AC1** WHEN a prompt states work to be done AND no mode is set, THE hook SHALL add context
      naming the start-task flow, and SHALL NOT block. → check: hooks/tests/task-intent.sh
- [x] **W17-AC2** WHEN a mode is set, THE hook SHALL stay silent and SHALL reset so a later task fires
      again. → check: hooks/tests/task-intent.sh
- [x] **W17-AC3** THE hook SHALL fire at most once per session while the mode is unset. → check:
      hooks/tests/task-intent.sh
- [x] **W17-AC4** THE hook SHALL stay silent on questions, on prompts under five words, and on explicit
      slash commands. → check: hooks/tests/task-intent.sh
- [x] **W17-AC5** WHEN `grounded-researcher` returns with no source and no `UNKNOWN`, THE hook SHALL
      block once with a reason naming what to add. → check: hooks/tests/agent-contract.sh
- [x] **W17-AC6** WHEN `adversarial-verifier` returns without a verdict, THE hook SHALL block once.
      → check: hooks/tests/agent-contract.sh
- [x] **W17-AC7** WHEN `stop_hook_active` is true, THE hook SHALL allow the return. → check:
      hooks/tests/agent-contract.sh
- [x] **W17-AC8** THE hook SHALL leave every other agent type untouched. → check:
      hooks/tests/agent-contract.sh
- [x] **W17-AC9** BOTH hooks SHALL be silent no-ops without `.groundwork.json` or with their toggle
      off, and SHALL exit 0 on malformed input. → check: both suites + hooks/tests/failsafe.sh

## Risks / assumptions

- **The intent detector is a word list, not a classifier.** It will miss a task phrased without one of
  its verbs and fire on a sentence that merely contains one. Both failures are cheap: a missed reminder
  is the status quo before this wave, and a false one is a line of context that never blocks. The lists
  sit at the top of the script for exactly this reason.
- **The evidence check cannot judge evidence.** A researcher can satisfy it with an irrelevant URL. It
  raises the floor from "no source at all" to "a source is named"; the adversarial panel and the reader
  remain the real check.
- **One more prompt-time hook on every message.** `UserPromptSubmit` has a 30-second budget and this
  script does a `jq` parse, a file read and three greps — but it runs on every prompt in every
  Groundwork project, so it exits at the first cheap check that fails.
- **Blocking a subagent costs a re-run.** The spike showed the agent reworking its whole answer. That is
  the intended trade for a report that cites nothing, and it is capped at one block per run.
- **Neither hook has run in a real task yet.** The spike exercised the platform mechanics on a built-in
  agent; the plugin's own path — a real `grounded-researcher` returning a real sweep — is unproven.
