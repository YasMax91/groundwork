# Spec: Wave 20 — the standards stop claiming a gate they do not have (v0.30.0)

- Type: plugin self-improvement → **L2** (three prose files, two manifests, no new mechanism).
- Author: Max Yastremskyi (YasMax91).
- Source: item E27 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). Structural: every criterion below is a grep or a validator run.
- Target version: **v0.30.0**.

## Goal

`guidelines/laravel-standards.md` is what the agent reads instead of the framework documentation. It
opened by claiming that "the standards are enforced by tool-gates (Pint / Larastan / PHPUnit)" — and no
skill, agent, hook, workflow or template linked to it, so the agent rarely opened it at all. Make the
file honest about what runs, and reachable from the two skills that need it.

## Problem (diagnosis)

- Roughly half of the file's rules — thin controllers, logic in `app/Services`, transactions, guarded
  transitions, ULIDs at the edge, money not `float` — are checked by nothing. Pint checks formatting,
  Larastan checks types, the suite checks the tests that exist. A false claim of enforcement is the
  exact defect `guidelines/ai-sdd-process.md:218` names: a gate that did not run has verified nothing.
- `grep -rn 'laravel-standards' skills/ agents/ hooks/ workflows/ templates/` returned **0**. The file
  had no address; `implement-approved` said "see the Laravel standards" with no path.
- The file named `PHPUnit` as the test runner while Laravel Boost installs a Pest skill, so the agent
  was being pointed at the wrong runner on a Pest project. The gates themselves are runner-agnostic
  already (`hooks/done-gate.sh:81`, `hooks/test-gate.sh:136`, `hooks/trim-output.sh:30`).

## Design

**Two lists instead of one claim.** The file now opens with a table of the six rules a hook actually
holds — each row naming the hook file and its `.groundwork.json` opt-out — followed by an explicit
statement that everything else on the page is an instruction to the agent that nothing checks
automatically, caught if at all by `agents/conformance-reviewer.md` and `skills/risk-review`.

**The unenforced half gets a reviewer.** `skills/risk-review/SKILL.md` gains an "Architecture
boundaries" checklist item that names those rules and says plainly that static analysis and the test
gate do not see them. This is the only place they can be caught, so it is where they are now listed.

**The runner is resolved, not assumed.** The tests bullet reads Pest when `pestphp/pest` is in
`composer.json`, PHPUnit otherwise, both through `artisan test`.

**The description stops overpromising in public.** `plugin.json` and the marketplace entry now say
"hooks that hold the runner, formatting, static analysis, tests and the OpenAPI document" — character
identical in both files, since `name` + `description` is the entire search surface of the catalog.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | No claim of blanket tool-gate enforcement remains | met — `grep -c 'enforced by tool-gates' guidelines/laravel-standards.md` → 0 |
| AC2 | Every "held by the engine" row names a real hook file and its opt-out | met — six rows, each pointing at `hooks/*.sh` and a `gates.*` key that exists in `templates/project/.groundwork.json` |
| AC3 | The file is reachable from the skills that need it | met — `grep -rn 'laravel-standards' skills/` → 2 (`implement-approved:19`, `risk-review:22`), was 0 |
| AC4 | The unenforced rules are named where they can actually be caught | met — new "Architecture boundaries" item in `skills/risk-review` |
| AC5 | PHPUnit is no longer named as the only runner | met — both branches stated |
| AC6 | Both manifests carry the same description and the plugin validates | met — compared character by character; `claude plugin validate .` → Validation passed |

## Deliberately not done

- **A framework/PHP version baseline in the standards file** (it still names no Laravel or PHP
  version) and an end-of-life warning at session start. Both are real gaps from the market scan; they
  did not make the E26–E29 cut and stay open.
- **Turning the architectural rules into executable tests** — that is E15 in
  [modernization-research-2026-08.md](modernization-research-2026-08.md). Until it lands, the honest
  label is the fix; a label is not a substitute for the test, and this spec does not pretend otherwise.
