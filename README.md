# groundwork

Claude Code plugin for Laravel backends — created and maintained by **Max Yastremskyi** (YasMax91).
One central, versioned source for how the RaDevs team works, so projects stay thin and consistent
instead of copy-pasting `AGENTS.md` / `CLAUDE.md` / skills between repositories.

## What's inside

- **Process (AI-SDD)** — skills: `start-task`, `spec`, `implement-approved`, `risk-review`,
  `final-check`, `init`. Discovery fans out via the `impact-mapper` agent (scaled by task level
  L0–L4) — the full blast radius before planning, so changes stay scoped without missing a consumer.
  Two review gates: `adversarial-verifier` (is the "it works" claim true?) and `conformance-reviewer`
  (does the diff satisfy the spec's acceptance criteria?). A converge re-check and ADR capture
  (`docs/adr/`) close out cross-cutting L3/L4 work.
- **Interview loop** — `clarify-protocol` + `AskUserQuestion` rounds before the plan: facts are the
  agent's to find, decisions are yours to make. Each question leads with the agent's recommendation, so
  you can click through and still land somewhere defensible; scaled by level (L0/L1 barely ask, L3/L4 up
  to three rounds), and every answer is recorded so a compaction never re-asks it. The `grill` skill
  runs the same interview standalone — to stress-test a plan, a decision, or an idea that never becomes
  code.
- **Plain language first** — every text where *you* decide (the discovery report, each interview
  question and option, the blind-spot block) opens with the lived consequence in everyday words and keeps
  the code, field name, or status number after it: "клиент нажимает «Оплатить» и видит ошибку, деньги не
  списываются (внутренний код 2406)". A layer, not a simplification — nothing technical is deleted, it
  just stops being the opening. Defined once in `clarify-protocol`; engineering summaries stay
  engineering prose.
- **Client document** — the `client-doc` skill writes for a client who does not know what a test or an
  endpoint is: the problem, what he will be able to do, what is in and out of scope, what is needed from
  him. Deliberately without tests, acceptance criteria, endpoints, schema, or architecture — if those are
  wanted, the artifact is a `spec`, and the skill says so instead of producing a hybrid. Estimates are
  **real AI-hours to write the functionality** — never man-days, since a human reviews this code rather
  than writing it — as ranges per block plus a total, with the reviewer's time on its own line. Ships as
  an English canonical file (what you send) plus a full Russian mirror (what you read), regenerated from
  the English so the two cannot drift.
- **Blind-spot surfacing** — the agent proactively raises what you did not think to ask: unintended
  consequences, missing requirements, and domain/product angles you are not the expert in — each with
  its consequence and a recommended default, in plain language. A `blind spots` block in the first
  response (distinct from clarify), the `blind-spot-mapper` agent in a fresh context for L3/L4, and
  touchpoints across spec, implementation, review, and frontend handoff. Calibrated against noise —
  material items only, "none" is honest. See `guidelines/blind-spot-protocol.md`. A blind spot that
  needs a product call is not left as a bullet — it becomes a question in the interview above.
- **Living domain contract** — the project's `AGENTS.md` (domain entities, invariants, permissions,
  integrations, and a domain-language glossary) is no longer written once by `init` and left to rot:
  `final-check` updates it in the same change whenever the work adds, renames, or removes one of those,
  so every later task reads a contract that still matches the code.
- **Live verification** — green gates are necessary, **not sufficient**: before "done", `final-check`
  exercises the change against the **running** app — a real HTTP run for an endpoint (the wire, the
  middleware, the real DB — not just the test kernel), and a real browser drive for admin/UI/CSS
  (the asset actually loads · the edited style is the *effective* computed one · no persisted
  `localStorage` state masking it). Coverage follows the impact map — every consumer of a touched shape
  (List *and* Show, export, API resource, notifications) with denormalized values checked on real data —
  and a defect **you** report is audited as a whole class, never point-patched. Fail-safe: when the app
  or the browser tool is unreachable it says exactly what stayed unverified, with repro steps; green
  tests are never reported as "works live", and a visual check the agent can drive is never handed back
  to you.
- **Frontend handoff** — after the final implementation and green gates, the `frontend-handoff` skill
  writes documentation for the frontend developer under `ai/frontend/` (a living reference doc per
  area + a dated handoff delta) — what to build, when, how, why, where, and the API contract, in
  Russian, no frontend code — plus a **runnable request package** (a Postman collection or a `.http`/curl
  file) with the auth header, bodies derived from the `FormRequest` rules, and real example responses
  captured in the live run, so the frontend runs the contract instead of retyping it. Then asks whether
  to commit (single line, no AI attribution).
- **OpenAPI as contract** — `openapi-protocol` + a blocking `openapi` Stop gate: an endpoint change
  that ships without its annotations is not "done". Every operation is complete to the last detail —
  every reachable status code (success + 401/403/404/409/422), the request body derived from the
  FormRequest rules, the response schema derived from the JsonResource, enums from the real PHP enums —
  and generation must be clean. The gate is fail-safe (silent without OpenAPI tooling) with a visible
  escape hatch (`OpenAPI: n/a — <reason>` in the checkpoint). The `openapi-audit` skill repairs
  pre-existing spec debt across a whole project.
- **TDD** — `tdd-protocol`: test-first (red→green→refactor) for L2+ features and bug fixes; the test
  suite is a Stop gate. The layered split matches the standards — feature tests for the contract,
  unit tests for services/calculations/state transitions. Acceptance criteria are EARS statements with
  stable IDs, each linked to its fail-first test.
- **Grounding** — `grounding-protocol` + the `ground-integration` skill + the `grounded-researcher`
  and `adversarial-verifier` agents. Read reality, never guess: executable proof covers internal feature
  endpoints as well as external sandboxes, and a claim resting on official docs or an internal project
  doc (`AGENTS.md` / CRD) is cited — source + quote — **in the answer itself**, or marked `UNKNOWN`.
- **Deep skills (L3/L4, opt-in)** — `deep-grounding` · `deep-discovery` · `deep-review`: Workflow-driven
  multi-agent escalations of grounding / discovery / review, each finding adversarially verified.
  ~15× tokens, gated to explicit invocation; graceful fallback to the single-agent skill when the
  `Workflow` tool is unavailable.
- **Standards + gates** — `laravel-standards` + hooks: Pint on edit, static analysis and the test
  suite as done-gates, and a `PreToolUse` enforcement guard that denies host Laravel/PHP commands
  (use the runner) and edits to shipped migrations — opt-out per project.
- **Working memory** — `working-memory` guideline + a `SessionStart` hook that cheaply re-injects
  project state (runner, DB engine, branch, uncommitted files, active spec, the task checkpoint) so
  the agent does not re-read the same files, and a `PreCompact` hook that marks the checkpoint as the
  source of truth before the transcript is thinned. The workflow skills keep a terse task checkpoint
  and a cached `impact-mapper` blast-radius map under `.claude/groundwork/` — context stays light, but
  nothing is forgotten across stops, restarts, or compaction.
- **Status / UI** — a persistent status line (`branch · engine · mode · level · spec`, opt-in via
  `init` + `ui.statusline`), in-action hook messages (`RaDevs: running tests…`), and a session banner +
  title. All fail-safe — unsupported display fields degrade to a no-op.
- **Templates** — thin project `AGENTS.md` / `CLAUDE.md` / `.groundwork.json` and six spec templates.

## Grounding split

- **Boost → the framework**: version-aware Laravel docs, DB schema, models, logs (a per-project
  `laravel/boost` composer dependency).
- **This plugin's protocol → external APIs** (payments, booking, messaging): capability matrix +
  cited source + sandbox proof. This is the part Boost does not cover.

## Install (in a project)

```
/plugin marketplace add <git-url-of-this-repo>
/plugin install groundwork@yasmax
/groundwork:init
```

`init` generates thin, domain-only contracts by grounded discovery (deriving facts from the code,
Boost, and docs, labelling anything assumed), installs Boost, and drops `.groundwork.json`.

## Update everywhere

```
/plugin marketplace update
```

Versioned with semver in `.claude-plugin/plugin.json` — projects update when you bump it.

## Develop locally

```
claude --plugin-dir /path/to/groundwork
```

Then `/reload-plugins` after changes. Test skills with `/groundwork:<skill>`, check the
agents in `/agents`, and confirm the hooks fire on edits.

## Per-project configuration — `.groundwork.json`

Declares the runner and the **database engine** (`database.default` — `mysql`/`pgsql`, the target for
code and tests; never SQLite), and overrides the gate commands (`format`, `analyse`, `test`) and
toggles (`format_on_edit`, `analyse_on_stop`, `test_on_stop`, `openapi_on_stop`, plus the `PreToolUse` enforcement
toggles `enforce_runner` and `lock_shipped_migrations` — default **on** — and `lock_edits_in_discovery`
— default **off**). A `memory` block toggles the working-memory layer (`session_context`,
`checkpoint`, `impact_cache` — all default on). Defaults to Sail + MySQL.

The plan-approval gate is the `start-task` → approval → `implement-approved` split; enable
`lock_edits_in_discovery` (or Claude Code's native `defaultMode: "plan"`) for a hard
read-only-while-planning gate.

`gates.openapi_on_stop` (default **on**) blocks "done" when the API contract surface changed but the
OpenAPI spec did not, then regenerates the document and blocks again if generation errors or warns.
It no-ops silently unless the project has `darkaonline/l5-swagger` or `zircote/swagger-php`; override
the generate command with `commands.openapi_generate`, the watched paths with `openapi.surface[]`
(defaults to `routes/`, `app/Http/Controllers/`, `app/Http/Requests/`, `app/Http/Resources/`), and
force it on for a project with a hand-maintained document via `openapi.enabled: true`.

`gates.trim_tool_output` (default **off**) enables a fail-safe `PostToolUse` trimmer that collapses
passing-test / clean-analysis spam from noisy commands to save context. It never trims when any
failure indicator is present and does nothing if it cannot positively locate the tool output, so a
wrong guess degrades to a no-op. The PostToolUse output field is not fully documented — confirm it
once with `claude --debug` in your project before enabling.

## Layout

```
.claude-plugin/   plugin.json · marketplace.json
skills/           start-task · spec · implement-approved · risk-review · final-check · ground-integration · frontend-handoff · client-doc · openapi-audit · grill · init · deep-grounding · deep-discovery · deep-review
agents/           impact-mapper · blind-spot-mapper · grounded-researcher · adversarial-verifier · conformance-reviewer
hooks/            hooks.json · session-start.sh · pre-compact.sh · format-on-edit.sh · done-gate.sh · test-gate.sh · openapi-gate.sh · trim-output.sh · pre-tool-guard.sh · statusline.sh
guidelines/       ai-sdd-process · grounding-protocol · blind-spot-protocol · clarify-protocol · openapi-protocol · laravel-standards · tdd-protocol · working-memory
docs/             skill-hygiene (author-facing) · specs/
templates/        project/ · specs/ · frontend/ (feature · handoff — both pointing at the runnable request package) · client-doc.md · adr.md
```
