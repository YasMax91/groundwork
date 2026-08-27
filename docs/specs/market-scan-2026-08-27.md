# Groundwork — market scan and roadmap (2026-08-27)

Status: **E26–E34 implemented**, waves 19–28 (v0.29.0–v0.38.0, 2026-08-27). Waves
[19](wave-19-the-guard-reads-its-input.md) · [20](wave-20-standards-stop-overpromising.md) ·
[21](wave-21-two-production-defects.md) · [22](wave-22-hook-tests-run-themselves.md) ·
[23](wave-23-conformance-output-contract.md) · [24](wave-24-the-receipt.md) ·
[25](wave-25-the-frontend-gets-the-contract.md) · [26](wave-26-the-gate-sees-scramble.md) ·
[27](wave-27-the-standards-know-their-version.md) · [28](wave-28-ready-for-the-catalog.md).
Wave 27 also closed the framework-baseline gap this document listed as falling outside the plan.
The first hosted CI run is green on both images (run 33100357521, 313 cases each), and the README badge
went in after it. **Open:** the catalog submission, and everything under *Rejected at the shortlist* —
which stays rejected until a measurement changes.
Author: Max Yastremskyi (YasMax91).
Continues [modernization-research-2026-08.md](modernization-research-2026-08.md) (E10–E25, of which E10,
E11, E13, E14 shipped in waves 15–18). Item numbering continues that series: **E26–E34**.
Scope decision taken before the scan: the plugin stays a Laravel-backend product and additionally owns the
**frontend contract boundary** — it does not become stack-agnostic and does not write frontend code.

## How this was produced, and what is actually verified

Fourteen agents: seven scouts (Claude Code platform, SDD competitors, Laravel ecosystem, corporate/client
demands, frontend contract, distribution, repository self-audit) → 140 raw findings → one deduplication pass
against what already ships → five candidates → **one skeptic per candidate, briefed to refute, not to agree**
→ sequencing. Every candidate came back `условно` (conditional): not one survived in its proposed form, and
the sections below carry the reduced scope, not the original pitch.

Author-side re-verification of the load-bearing claims, run against the repository while writing this
document — **13 checks, 13 confirmed**:

| # | Claim | Result |
|---|---|---|
| 1 | `hooks/pre-tool-guard.sh:30` parses `tool_name` with `jq` and has no `command -v jq` guard | confirmed; seven other hooks do guard (`agent-contract.sh:20`, `coverage-claim.sh:40`, `estimate-claim.sh:42`, `task-intent.sh:25`, `estimate-ledger.sh:31,294`, `lib.sh:20`) |
| 2 | Without `jq`, `$tool` is empty and the catch-all `*)` at `pre-tool-guard.sh:139` exits 0 | confirmed by reading the branch |
| 3 | No skill, agent, hook, workflow or template references `guidelines/laravel-standards.md` | confirmed — `grep -rn 'laravel-standards' skills/ agents/ hooks/ workflows/ templates/` → 0 |
| 4 | `laravel-standards.md:3-4` claims the standards are "enforced by tool-gates (Pint / Larastan / PHPUnit)" | confirmed verbatim |
| 5 | That file names no Laravel or PHP version | confirmed — 0 matches for `Laravel 1[0-9]`; `PHPUnit` ×2; `queue` ×1 (in a Sail command list) |
| 6 | `skills/frontend-handoff/SKILL.md` never mentions OpenAPI or Swagger | confirmed — 0 matches |
| 7 | `hooks/openapi-gate.sh:45` detects only `darkaonline/l5-swagger` and `zircote/swagger-php`; `:181` defaults to `artisan l5-swagger:generate` | confirmed |
| 8 | `openapi-gate.sh:40` reads `.openapi.enabled`, but `templates/project/.groundwork.json` ships no `openapi` block (only `gates.openapi_on_stop`) | confirmed |
| 9 | `hooks/hooks.json:36` SubagentStop matcher is `^groundwork:(grounded-researcher\|adversarial-verifier)$` — `conformance-reviewer` is outside it | confirmed |
| 10 | `estimate-ledger.sh` is registered in no hook; the only caller of `--record` is prose in `skills/final-check/SKILL.md:109` | confirmed — 0 occurrences in `hooks/hooks.json`; `estimate-claim.sh:65` calls `--report` only |
| 11 | `guidelines/working-memory.md:23,30` document `Mode: Done`; `hooks/lib.sh:15` canon is `Discovery Spec Plan Implementation Review` | confirmed — the documented mode is not in the canon |
| 12 | `hooks/tests/` holds 13 suites plus `all.sh`; no suite covers `trim-output.sh` or `pre-compact.sh` | confirmed — 0 files reference either |
| 13 | The repository has no `.github/` directory; `disable-model-invocation` appears only in `skills/grill/SKILL.md` | confirmed |

Not verified, carried forward as UNKNOWN: whether the community catalog slug `groundwork` is really taken by
`github.com/etr/groundwork` (scout claim, not re-checked); whether a plugin shipping 15 shell hooks with a
PreToolUse deny passes the catalog's safety screening (no precedent found); whether the submission form lets
the author choose the catalog entry name; whether the `claude` CLI is available on GitHub-hosted runners;
Prism proxy's exact contract-violation report format; primary AICPA/TSC text on AI-generated-change
attestation (only vendor blogs were found).

## What the scan actually says

**1. The plugin's central promise is violated inside the plugin.** It sells "a rule the engine enforces
instead of a sentence asking the model", and `guidelines/ai-sdd-process.md:218` states "a gate that did not
run has verified nothing". Five of its own rules are prose: the access hook turns itself off on a machine
without `jq` (checks 1–2); the measured-estimate mechanism from wave 18 depends on the model remembering to
run `--record` (check 10); the checkpoint canon rejects a mode its own template documents (check 11); the
standards file claims enforcement it does not have (checks 3–5); two hooks have no tests (check 12).

**2. Everything outside one developer's interactive session is missing.** No CI, no PR body, no artifact left
in the repository after a task. Three independent axes named the same gap — competitors, corporate demand,
and the self-audit. The skeptics cut most of the proposed answer: only the plugin's **own** test CI survives,
plus a receipt file that separates measured facts from agent claims.

**3. Evidence features degenerate into ceremony when the agent fills the fields.** Exactly five fields of the
proposed receipt are machine-derivable: commit SHA, `composer analyse` exit code (`hooks/done-gate.sh:74`),
the suite's aggregate exit code (`hooks/test-gate.sh` — which test closed which criterion does not follow from
it), OpenAPI generation status, and ledger minutes. AC→test mapping and the conformance verdict are written
by an LLM. A receipt that hides this line is worse than no receipt.

**4. The standards lag the stack they claim.** No framework or PHP version anywhere in the file, `PHPUnit`
named as the runner in a world where Boost installs a Pest skill, one mention of queues, nothing on
idempotency — while Laravel 12 left its bugfix window on 2026-08-13.

**5. The contract line is built for one generator.** `dedoc/scramble` projects get silence from the gate; the
handoff hands the frontend Russian prose and a Postman collection, and never the document itself.

**6. Distribution is not blocked on quality.** The plugin is in no public catalog, has no CI and no changelog,
and the platform gives the author no install or activation count at all — the catalog card is the only counter
that exists.

## Positioning: three corrections

1. **"Laravel standards enforced by tool-gates" stops being said.** Roughly half of the file's 23 rules — thin
   controllers, logic in `app/Services`, transactions, guarded transitions, ULID at the edge, money not float —
   are checked by nothing. New split: the engine holds format, static analysis, tests, OpenAPI, shipped
   migrations and the runner lock; the architectural rules are instructions to the agent, **labelled
   unenforced**. This is not a retreat from the claim, it is the claim applied to the plugin itself.
2. **The frontend boundary becomes an artifact.** After E32 the sentence is "the frontend gets the contract
   document and a mock before deploy", not "the frontend gets instructions".
3. **The receipt is "measured + claimed", never an audit trail.** What vendor sources attribute to an auditor
   is reviewer identity, review timestamp and attestation — a human signature. Selling an LLM's own verdict as
   an audit answer is selling an AI attesting to itself.

**What the plugin does not become: a team/CI product.** Of four "beyond one session" proposals, only CI on the
plugin's own hook tests survives. `claude -p` in CI was cut — it duplicates the local Stop gates and pays
tokens and Actions minutes for an answer already obtained. Git trailers were cut — they reverse the deliberate
decision at `skills/frontend-handoff/SKILL.md:86` (one-line commit, no attribution) and break corporate
commit-lint.

## Backlog

### E26 — The access hook stops disabling itself
**What.** Fallback parsing of `tool_name` / `tool_input.command` / `tool_input.file_path` via `python3` in
`hooks/pre-tool-guard.sh` (already a dependency of `hooks/estimate-ledger.sh`, so no new one appears); an
explicit "neither `jq` nor `python3`" branch that exits 0 **and prints to stderr** instead of going quiet; test
cases with `jq` off `PATH`; new suites for `trim-output.sh` and `pre-compact.sh`.
**Why.** Today, on a machine without `jq`, both rules this hook exists for are off: a migration runs on the
host `.env` instead of the container, and an already-shipped migration can be edited silently.
**Acceptance.** With `jq` off `PATH`, `{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}`
under `runner=sail, enforce_runner=true` exits 2 (today: 0). Editing a shipped migration exits 2. With neither
parser: exit 0 and non-empty stderr, pinned by its own case. `bash hooks/tests/all.sh` prints 15 suites.
`failsafe.sh` covers 14 hooks including the two new ones.
**Cost.** 60–90 agent minutes. **Human step:** decide the no-parser fork — allow with a stderr line
(proposed) or deny.

### E27 — The standards stop claiming a gate they do not have, and get an address
**What.** Replace `laravel-standards.md:3-4` with two lists — held by the engine (naming the hook file for
each) and not held by anything; `PHPUnit` → the project's runner resolved from `composer.json`; explicit
`${CLAUDE_SKILL_DIR}/../../guidelines/laravel-standards.md` paths in `skills/implement-approved/SKILL.md:19`
and `skills/risk-review/SKILL.md`; the same split, one sentence, in both manifest descriptions.
**Why.** The file the agent reads instead of documentation is currently unreachable from any skill (check 3)
and misstates what is verified (check 4).
**Acceptance.** `grep -c 'enforced by tool-gates' guidelines/laravel-standards.md` → 0; `grep -rn
'laravel-standards' skills/` → ≥2; both branches (Pest / PHPUnit) named; `plugin.json` and the marketplace
entry carry a character-identical description; `claude plugin validate .` → exit 0.
**Cost.** 45–70 agent minutes. **Human step:** approve the description wording — `name` + `description` is
the entire search surface of the public catalog.

### E28 — Two production defect classes get a rule where the agent will see it
**What.** `dispatch`/`event` inside `DB::transaction` only via `->afterCommit()` (or `after_commit` on the
queue connection) — added at `skills/implement-approved/SKILL.md:23`, next to the existing requirement to wrap
multi-step writes in a transaction, and as a review item in `skills/risk-review/SKILL.md:38`. Webhook
**redelivery** as an acceptance criterion in `templates/specs/integration-change.md` next to the existing AC3
(unique key `(provider, event_id)`, repeat is a no-op, with a `→ test:` pointer). Three mandatory capability
matrix rows in `skills/ground-integration/SKILL.md:22`: does the provider accept an idempotency key, is
webhook delivery at-least-once or at-most-once, does the event carry a stable id.
**Why.** The plugin requires transactions and says nothing about what that requirement breaks — a job that
runs before the commit lands. `grep -rniI 'aftercommit|after_commit'` over the repository is 0 today.
**Acceptance.** ≥2 matches for `afterCommit`, both under `skills/`. The new AC carries a `→ test:` pointer, so
`agents/conformance-reviewer.md:28` already enforces it ("a criterion with a `→ test:` pointer is met only if
the diff contains that test"). An integration spec without it does not pass conformance as CONFORMS.
**Cost.** 50–80 agent minutes. **Human step:** decide whether the AC is mandatory for every integration or
only for providers with webhooks.

### E29 — The hook tests stop depending on the author remembering to run them
**What.** `.github/workflows/ci.yml` (no `.github` exists today): `bash hooks/tests/all.sh` and
`claude plugin validate .` on `ubuntu-latest` and `macos-latest`. README badge only after the first green run.
**Why.** After E26–E28 the shell carries new branches; nothing runs them but the author's memory.
**Acceptance.** A push runs both jobs; a deliberate regression (restoring the `jq` behaviour of E26) turns the
suite red. `validate` runs **without** `--strict` — during verification `--strict` turned an unknown-field
warning (`icon`, `screenshots`) into exit 1.
**Cost.** 40–60 agent minutes. **Human step:** confirm the first green run before adding the badge.

### E30 — The conformance reviewer's output becomes a structure the engine checks
**What.** Add `conformance-reviewer` to the SubagentStop matcher at `hooks/hooks.json:36` and a branch in
`hooks/agent-contract.sh` requiring a verdict from `CONFORMS|GAPS|INSUFFICIENT`
(`agents/conformance-reviewer.md:43-46`) and at least one `AC<N>` row with met/partial/unmet. Blocking uses
`decision:"block"`, the mechanism the two existing branches already use; `gates.agent_contract:false` disables
it like the others.
**Why.** The table is required by prose and produced as free text. Any machine reading of its fields — the
receipt in E31 — would be guessing until this lands.
**Acceptance.** Prose without AC rows is blocked once and re-asked; the second entry (`stop_hook_active:true`)
passes; a "looks fine" verdict without a dictionary word is blocked; three new cases green.
**Cost.** 60–90 agent minutes. **Human step:** run one real conformance review and check the hook does not
block legitimate output — a false block costs more here than a miss.

### E31 — The receipt: measured facts separated from agent claims
**What.** `docs/specs/<slug>.receipt.md`, written by `skills/final-check`, in two explicitly titled blocks.
**Measured:** commit SHA, `composer analyse` exit code, suite exit code, OpenAPI generation status, ledger
active minutes. **Claimed by the agent:** AC→test mapping, the conformance verdict, what stayed uncovered.
Plus the AC coverage table in the PR body (`skills/final-check/SKILL.md:170-174`, where the body is already
defined as this summary). Not in `.claude/groundwork/` — `skills/init/SKILL.md:55` and
`guidelines/working-memory.md:11` require that directory to be gitignored, where neither git, nor the PR, nor
the client would ever see the file.
**Why.** The facts exist and die in the transcript. This is the only item that answers "can this be adopted by
a team", and it answers it honestly or not at all.
**Acceptance.** The file appears in `git status` and is not ignored; no field in the measured block contains
text absent from a command's output; the claimed block's heading cannot be read as proof — a missing heading
is an acceptance defect; the PR body carries one row per AC ID; **the receipt blocks nothing** — no sixth Stop
hook is added.
**Cost.** 120–180 agent minutes. **Human step:** decide whether the receipt is committed to the client's
repository, and whether a human signature line is added — without one the artifact remains an LLM attesting to
itself.

### E32 — The frontend gets a machine-readable contract and a mock
**What.** An `openapi` block with `spec_path` in `templates/project/.groundwork.json` (check 8 — the gate reads
`openapi.enabled` and the template never teaches the key); a bundled spec snapshot at
`ai/frontend/openapi/<YYYY-MM-DD>-<slug>.yaml` written by `skills/frontend-handoff`; the snapshot path and
`npx @stoplight/prism-cli mock <spec>` next to the existing Postman line in `templates/frontend/handoff.md:6`.
**Why.** The frontend boundary is core product and the frontend never receives the contract document
(check 6).
**Acceptance.** The snapshot exists with date and slug and is linked from the handoff header; `npx -y
@stoplight/prism-cli mock <snapshot>` serves one endpoint from the handoff; without node the document carries
an explicit note rather than a missing line; a project without `openapi.spec_path` behaves exactly as today.
**Cost.** 90–140 agent minutes. **Human step:** decide whether the snapshot is committed — deferred `oasdiff`
against a merge-base only works on a committed snapshot.

### E33 — The OpenAPI gate stops being blind to Scramble, and checks the document is usable
**What.** Detect `dedoc/scramble` at `openapi-gate.sh:45`; resolve `artisan scramble:export --path=<spec_path>`
for the inference branch instead of the unconditional `l5-swagger:generate` at `:181`; for that branch the
"spec was touched" test becomes a change to `openapi.spec_path`, since annotations do not exist (`:124,133,143`
search `@?OA\[A-Z]` only); split the block message at `:167`, which today tells a Scramble project to update
annotations it does not have; two branches in `guidelines/openapi-protocol.md`; a Scramble fixture in
`hooks/tests/openapi-gate.sh`; `npx -y openapi-typescript <spec>` in `final-check` only — a cold `npx` took
~3.0 s during verification, too slow for a Stop hook.
**Why.** Two silent failure modes on real projects: no gate at all, or a gate whose instruction is wrong.
**Acceptance.** A Scramble fixture blocks with a message that does not mention annotations; the same fixture
with the exported document changed passes; existing l5-swagger cases stay green unchanged; a structurally
broken document (unresolvable `$ref`) fails in `final-check` (reproduced: `openapi-typescript` 7.13.0 exits 1);
without node, `final-check` prints a skip line instead of silence.
**Cost.** 150–220 agent minutes. **Human step:** confirm `openapi.spec_version` stays untouched — the premise
behind it was refuted (see below).

### E34 — Submission to the public catalog
**What.** Fix the four broken code spans at `README.md:171-174`; add `category: "development"` to the
marketplace entry — the only one of five proposed showcase fields the catalog actually carries; submit under
the entry name `groundwork-laravel` **without** renaming in the own marketplace or in `plugin.json`.
**Why.** The plugin is installable only by someone who already found the repository. The platform gives the
author no install or activation metric (open request `anthropics/claude-code#46163`); the catalog card is the
only counter that exists.
**Acceptance.** `claude plugin validate .` → exit 0 without `--strict`; `icon`/`screenshots` are not added
(the validator calls them unknown fields); CI green on both operating systems at submission time; after
approval the plugin is discoverable by the word "laravel".
**Cost.** 40–60 agent minutes of technical work. **Human step:** fill in the submission form by hand and wait
for review; the agent does not submit.

## Sequencing

| Wave | Item | Agent minutes | Depends on |
|---|---|---|---|
| 19 | E26 access hook | 60–90 | — |
| 20 | E27 honest standards + address | 45–70 | — |
| 21 | E28 transactions + webhook redelivery | 50–80 | E27 (the rules need to be reachable) |
| 22 | E29 CI on the hook tests | 40–60 | E26–E28 (something to protect) |
| 23 | E30 conformance output contract | 60–90 | — |
| 24 | E31 receipt + PR table | 120–180 | E30, E29 |
| 25 | E32 spec snapshot + mock | 90–140 | — (ships `spec_path` for E33) |
| 26 | E33 Scramble + document usability | 150–220 | E32 |
| 27 | E34 catalog submission | 40–60 | E27 (description), E29 (green CI) |

Total 655–990 agent minutes. **The cut line is after wave 22.** Waves 19–22 cost 195–300 minutes and change
every task in every project; waves 24–26 cost 360–540 and change tasks in some projects (those with a spec, a
PR, or Scramble). If time runs out mid-plan, stop after wave 22, not after wave 24.

## Refuted during verification — do not resurrect

- **`exit 1` in Stop gates when git is missing.** Only exit 2 blocks; any other code produces a transcript
  notice and the action proceeds. Stop fires on every turn, so a git-less project would collect three notices
  per turn with no opt-out. Both variants lose.
- **`command -v jq || exit 0` as the fix for the access hook.** Still exit 0, i.e. still allow, and stderr on a
  zero exit goes to the debug log, not to the user. Only real parsing or an explicit deny changes anything —
  hence E26.
- **Recording the ledger from a `Mode: Done` checkpoint.** `hooks/lib.sh:15` does not contain `Done`, so the
  trigger would be dead code. The discrepancy between `working-memory.md:30` and the resolver is a real bug and
  is filed separately, not used as a foundation.
- **`openapi.spec_version`.** The premise — that 3.1 tooling silently ignores `nullable: true` — was refuted by
  running it: `openapi-typescript` 7.13.0 emits `string | null` for both 3.0.0 and 3.1.0, and
  `artisan l5-swagger:generate` takes no `--version` flag.
- **Catalog `keywords`.** Not stored in catalog entries (0 of 2282); `name` + `description` is the whole search
  surface. `icon` and `screenshots` are unknown fields to the validator.
- **Git trailers, `claude -p` in CI, `oasdiff` now, a generated CHANGELOG, removing the three `*-run`
  workflows from the model index.** Reasons, in order: they reverse a deliberate decision and break commit-lint;
  they pay twice for an answer the local Stop gates already produced; there is no committed baseline to diff
  against until the E32 human decision; nine one-line releases are not a changelog; no such mechanism exists in
  the workflows documentation.
- **Deduplicating `gw_changed_paths` / `ran_marker` / `env_phrase` into `lib.sh`.** It breaks the guarantee
  `hooks/tests/failsafe.sh` proves by deleting `lib.sh` and requiring every hook to still run.

## Rejected at the shortlist (with the reason, so they are not re-proposed)

Subagent `memory: project` (E19, nothing new); `displayName`/`$schema` (E21, absorbed); path-scoped rules
(refines E23); the `skill-creator` eval harness (refines E12 — worth it only after the plugin stops changing
weekly); the Pest 5 lane (E17/E15 — conditional: Pest 5 needs PHP 8.4); **an `laravel/ai` skill, `ai-feature`
template and LLM-security protocol** — the largest market expansion and the largest dilution risk, deferred as
a separate product decision, not smuggled into a wave; EU AI Act Art. 50 gate (dates sourced from a consulting
blog, not EUR-Lex); SBOM/CycloneDX and PCI DSS 6.4.3 (applicability to a custom Laravel backend unconfirmed);
an evals gate for AI features (costs the client real money, non-deterministic); cross-model adversarial review
via another vendor's CLI (a second subscription and a new failure path); an autonomous loop without a human
(contradicts the interrogation and the approval gate); property-based tests from EARS (PHP library maturity
unconfirmed); a post-merge spec-drift skill (expensive full-repo pass, noisy); one-way task projection to
GitHub Issues/Jira/Linear; a four-outcome gate with WAIVED (a waiver without an expiry is an off switch); a
realtime channel catalog (the hole is real — `broadcast` appears in one file — but the catalog is maintained by
hand); Schemathesis/Arazzo/Bruno/Pact/Dredd (formats instead of executing the checklist already written);
Spectral/vacuum rulesets (hundreds of errors on a legacy spec, then disabled wholesale); design-first entry for
brownfield (a legal way to skip discovery); platform tweaks — model selection, background subagents, worktree
isolation, plugin dependencies, `userConfig`; a prompt-based Stop hook for the changelog; a SlopCodeBench
degradation metric; a gate-run cache keyed by tree hash (performance bought with the risk of a false green);
observability in the Definition of Done (requires choosing a paid SaaS); OWASP Top 10:2025 relabelling of
`risk-review` (labels without enforcement create false assurance); a Laravel 12→13 upgrade skill as a lead
magnet (E27's EOL warning already creates the opening); porting the skills to other harnesses (half the value
is in hooks that do not exist outside Claude Code); skill-entry-registered hooks (they would miss the user who
edits code before invoking anything); internal hygiene items (duplicate self-review checklist, warehouse domain
in `risk-review`, five owners of the estimate rule, SKILL.md sizes); the MCP tool-name mismatch in `agents/*.md`
versus the real `mcp__plugin_context7_context7__*` (looks like a genuine bug — one check, not a wave); a
`composer audit` gate and dependency approval via PreToolUse (strong pair, but needs network inside a gate).

## Decisions the author has to make

1. E26: no `jq` and no `python3` → allow with a stderr line, or deny?
2. E27: the exact description wording (it becomes the catalog's entire search surface).
3. E28: the webhook AC — mandatory for every integration, or only for payment/booking/messaging providers?
4. E31: is the receipt committed to the client's repository, and does a human sign it?
5. E32: is the spec snapshot committed to git?
6. E34: submit as `groundwork-laravel`, and who runs the form.

## Separate bugs found while verifying (not waves)

- `guidelines/working-memory.md:23,30` documents `Mode: Done`; `hooks/lib.sh:15` does not accept it.
- `skills/final-check/SKILL.md:109` is the only caller of `estimate-ledger.sh --record` — wave 18's measurement
  rests on the model remembering a command.
- `hooks/tests/` covers 13 of 15 hooks; `trim-output.sh` and `pre-compact.sh` have no suite (folded into E26).
- The three deep skills carry no `disable-model-invocation` although their descriptions say "by explicit
  invocation only".
