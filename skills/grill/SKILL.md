---
description: A relentless interview that stress-tests a plan, decision, or idea until nothing is left silently assumed.
disable-model-invocation: true
---

# Grill

Interview the user until the thinking holds. This is the clarify protocol run on its own — outside the
task pipeline, with no classification, no impact map, and no spec. Use it on a plan, an architecture
call, a product idea, or an intent that has not become a task yet, including work that never becomes
code.

Run the rounds per `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`: find every fact yourself,
put every genuine decision to the user, ask the frontier in one `AskUserQuestion` call per round, lead
each question with your recommendation and its consequence, and let each answer push the frontier
outward.

This skill is the **manual entry point** — for grilling something that is not a task yet. Inside a task,
the agent offers the same loop in its first interview round from L2 up and, once you accept, runs it
directly (see "Unbounded mode" in `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`); you never
have to type the command to get it.

Two things differ from the in-pipeline loop:

- **No round cap.** The user asked to be grilled and ends it by saying so. Keep going while the frontier
  refills.
- **Explore for real.** With no discovery phase behind you, the facts are unmapped — read the code, the
  CRD, and the docs as questions demand them, and spawn subagents for anything wide. A fact you skipped
  becomes a question you should not have asked.

## Close with the decision summary

When the frontier empties, report:

1. **Settled** — each decision and the option chosen.
2. **Still assumed** — what was never decided, and what it would cost to be wrong.
3. **What it changes** — the consequence of the session for the original plan: what survived, what
   moved, what should be dropped.

Then offer the handoff: `start-task` when it is now a backend task, `spec` when the decisions are ready
to be written down, or nothing when the thinking was the deliverable.
