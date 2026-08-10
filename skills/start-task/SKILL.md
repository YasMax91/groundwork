---
description: Start a backend task through the Groundwork AI-SDD discovery/plan workflow. Use at the beginning of any non-trivial feature, bug fix, or API/schema/permission/workflow/integration change, before writing code.
---

# Start task (discovery & plan)

Stay in **Discovery mode**: inspect and plan only, do not edit files until the plan is approved.

## Steps

1. **Read the project `AGENTS.md`** for domain facts, invariants, permission rules, and runtime
   commands.
2. **Classify the task** (L0 tiny → L4 critical). State the level and what it implies. The level also
   decides **what you read**: at L0/L1 stay inside this skill — the per-level scale-downs below already
   state the whole contour (one question at most, a fail-first regression test, a live exercise of the
   one thing fixed), so opening the fan-out, clarify and blind-spot guidelines spends thousands of
   tokens to arrive back here. Open them from **L2** up, and only the ones that step actually needs.
3. **Inspect the directly-involved code.** Prefer Boost MCP tools — `application-info`,
   `database-schema`, `search-docs` — over recalling from memory. Read the actual routes, requests,
   controllers, services, models, resources, migrations, and tests the task names.
   - **Symbols: the `LSP` tool before grep**, when a PHP language server is active (`php-lsp`) — it
     follows imports, aliases and inheritance a name match misses. Grep still owns what it cannot see:
     string class names, `event('…')`, container bindings, config- and Blade-driven wiring. The
     `impact-mapper` subagent has no `LSP` tool, so resolve a symbol its map left open yourself.
   - **A production bug starts at the incident.** When the report comes from production and the project
     reports to Sentry (the `sentry` plugin), read the actual issue — stack trace, release, frequency —
     before forming a hypothesis, instead of reconstructing a repro from the user's wording.
4. **Map the connections — do not stop at the involved files.** Discovery is wide; only the change is
   narrow. Trace outward in *both* directions from every touched symbol: who calls it, and what it
   pulls in. Chase the Laravel edges grep alone misses — events/listeners, observers, jobs, scheduled
   commands, policies/Gates/permission checks, `FormRequest`s reused across endpoints, the
   `JsonResource` shape and its API consumers, FK/cascade relationships, other modules on the same
   tables, and the tests covering any of it.
   - **L2+** (normal feature and up): base the plan on the **`impact-mapper`** connection map, but
     **reuse the cache first** — check `.claude/groundwork/impact/<slug>.md` and re-spawn the agent only
     if the seeds changed since it was written; otherwise overwrite the cache with the fresh map.
     This avoids re-running the most expensive fan-out on iterative work. Reuse requires **all three**
     staleness conditions — including that the cached `SEEDS` still cover the seeds of the work at hand,
     which is what a new sub-request breaks. Rules:
     `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`.
   - **L0/L1**: a quick outward trace yourself (a few targeted greps) is enough — no agent needed.
   - **Fan-out scales with level** — see "Fan-out by level" in
     `${CLAUDE_SKILL_DIR}/../../guidelines/ai-sdd-process.md`. Only Discovery and Verification fan out.
     For L3/L4 with many seeds, escalate to the `deep-discovery` skill (multi-agent Workflow).
   - **Surface blind spots** — after mapping couplings, walk the blind-spot taxonomy
     (`${CLAUDE_SKILL_DIR}/../../guidelines/blind-spot-protocol.md`): the dimensions the request omits —
     unintended consequences, missing requirements, domain/product angles the user is not the expert in.
     For **L3/L4** spawn the `blind-spot-mapper` agent in a fresh context (optional at L2). Report a
     **blind spots** block, separate from clarifications — material items only, ranked, or "none".
5. **Consult the CRD** for business intent when the task touches domain/API/schema/permissions/
   financial behavior/notifications/reports/integrations/deployment.
6. **If the task touches an external API**, run the `ground-integration` skill before designing.
7. **Produce the first response in this structure** (no code yet). **Open in plain language** — two or
   three sentences on what this means for the client and for the business — *before* any technical
   section; identifiers come after the meaning, never instead of it (the layered rule in
   `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`). Then:
   current understanding · classification · files/docs to inspect · connections / blast radius ·
   business/CRD areas affected · draft spec · acceptance criteria · **approaches** (2–3 candidate ways to
   solve the task, the recommended one first with its reason and what it forecloses — see step 7a) ·
   clarifications (ambiguities,
   conflicts, gaps surfaced as explicit questions to resolve before planning) · blind spots (dimensions
   you did not ask about — consequences / missing requirements / domain-product angles, per the
   blind-spot protocol; material only, or "none") · test plan (red list —
   fail-first tests for L2+/bug fixes) · implementation plan · **cost of silence** (what you decided for
   the user, and what each costs if wrong — step 8a) · risks & assumptions · stop point.
7a. **Take a position before you ask — the approaches block.** Present your **2–3 candidate approaches**
   to the task, recommended one first, each with its reason and what choosing it forecloses. This is plan
   altitude — *how we solve this* — not the per-question options of the interview, and it comes **before**
   the questions so the user picks between shapes of a solution instead of ratifying the one you already
   chose. Plain language (the layered rule in
   `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`).
   - **When one path is plainly right, say exactly that in one line** — "one sensible approach, here it
     is, because X". A fabricated alternative is noise, not diligence.
   - **L0/L1** skip · **L2** one line per approach · **L3/L4** the block, and it **feeds the ADR** when
     the decision is cross-cutting and durable (the `spec` skill's ≥2 options are these same two,
     considered before the plan rather than reconstructed after it).

7b. **Offer the unbounded interview — recommend it when the signals below fire.** From **L2 up** the
   depth choice is one of the questions in the first interview round every time (proceed at the level's
   calibration · run the unbounded interview now), so the user chooses the depth rather than finding out
   later that he was never asked. Never start it unasked. **If he accepts, run the loop yourself** — no
   round cap, closing with the decision summary, per "Unbounded mode" in
   `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`; do not send him off to type `/grill`, which
   is the entry point for something that is not a task yet.
   **Recommend it** — the option comes first, marked as recommended, with the reason in the same line —
   when any one of these holds:
   - the request names a **problem, not a change** ("orders get lost", "clients complain about payments");
   - **two or more incompatible readings** survive this discovery pass;
   - it is an **architecture or product call** (what should exist), not a code change (how to build it);
   - **nobody can state what "done" looks like** yet — no acceptance shape can be written;
   - it is **L3/L4** and the goal itself, not just the mechanism, is still open;
   - the task touches a **mandatory subject** — money, permissions/access, what the client sees, or an
     external integration — and more of those decisions are open than the level's cap can hold (see
     "When the interrogation is mandatory" in
     `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`).

8. **Interview for the decisions that are the user's.** Run the clarify rounds per
   `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`: ask the frontier in one
   `AskUserQuestion` call (≤4 questions, each led by your recommendation and its consequence, each in
  plain language — no term the owner must translate first), let each
   answer push the frontier outward, and stop when it is empty. Scaled by level — **L0/L1** at most one
   question, **L2** up to **2** rounds (blocking decisions and any product fork that would ship
   differently), **L3/L4** up to **4** rounds. Money, permissions/access, what the client sees, and
   external-integration behaviour carry a round of their own from L2 up, however settled the request
   sounds. A blind spot that needs a product call enters here as a question when the level's
   calibration admits one; when it does not, it is recorded as an explicit assumption instead — never
   silently dropped (see the blind-spot protocol). Look up every fact yourself; never spend a question on one.

8a. **State the cost of silence before the plan.** List every decision you took on the user's behalf —
   what was assumed · why you chose it · what it costs if it is wrong · the one line that changes it — in
   the plain-language form the clarify protocol specifies. If the list is empty, say so; that is a claim
   that the frontier really was empty, not a formality to skip. Then continue to the plan.
9. **Write the task checkpoint** to `.claude/groundwork/task-state.md` — mode, level, spec path, the
   slice/red list, the decisions just settled, assumptions, open approvals — so the work survives a
   restart or compaction (the `SessionStart` hook re-injects it automatically, no re-reading). This
   bookkeeping file under `.claude/groundwork/` is workflow memory, not a code edit, so it is allowed in
   Discovery. Format: `${CLAUDE_SKILL_DIR}/../../guidelines/working-memory.md`.
10. **Stop and wait for explicit approval** before implementing.

## Rules

- **Clarify before you plan.** Facts are yours to find, decisions are the user's to make — see
  `${CLAUDE_SKILL_DIR}/../../guidelines/clarify-protocol.md`.
- Do not invent business rules — derive them from CRD, code, or an explicit user decision.
- Label every claim as `verified` (with evidence) or `assumed`. Never use unqualified "done".
- **Plan tests first.** Turn the acceptance criteria into the red list before any code — see
  `${CLAUDE_SKILL_DIR}/../../guidelines/tdd-protocol.md`.
- For a normal feature or risky change, write a spec with the `spec` skill before implementing.
