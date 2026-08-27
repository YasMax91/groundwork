# Spec: Wave 29 — the repository agrees with itself again (v0.39.0)

- Type: plugin self-improvement → **L1** (two agent frontmatters, README, one guideline).
- Author: Max Yastremskyi (YasMax91).
- Source: a cross-reference audit of the repository after waves 19–28, run mechanically rather than by
  reading: hook registration, test wiring, `${CLAUDE_SKILL_DIR}` paths, backticked file references,
  `.groundwork.json` keys, catalog manifests, workflow names, and the claims in the README.
- Status: **implemented** (2026-08-27).
- Target version: **v0.39.0**.

## What the audit found

**A real defect — two agents were asking for a tool name that resolves to nothing.**
`agents/grounded-researcher.md` and `agents/adversarial-verifier.md` list `mcp__context7`. The subagent
docs confirm the form is right (`mcp__<server>` grants every tool of that server), and
`mcp__laravel-boost` does resolve — the projects define an MCP server named exactly `laravel-boost`.
But Context7 arrives through the companion **plugin**, and a plugin-provided server is namespaced: its
tools are `mcp__plugin_context7_context7__*`. So the entry silently dropped, and the two agents that
`groundwork-pack` bundles Context7 *for* never had it — they fell back to `WebFetch`/`WebSearch`, which
is slower and less precise. Both agents now list `mcp__context7` **and**
`mcp__plugin_context7_context7`; an entry that resolves to nothing is dropped as long as something else
resolves, so naming both is safe.

**Four stale claims in the README**, each now false since waves 24–27:

- the OpenAPI bullet said the gate no-ops "unless the project has `l5-swagger` or `swagger-php`" —
  wave 26 added the inference-driven branch, `openapi.generator`, `openapi.spec_path`, and the
  consumability check;
- the estimates bullet implied the ledger row is written by the flow rather than by a `Stop` hook on
  `Mode: Done`;
- the receipt, the committed contract snapshot and the mock command were absent entirely;
- the standards bullet still described the old "enforced by tool-gates" framing, and said nothing about
  the framework baseline or the support-window notice.

**A gap between two documents**: `final-check` writes the receipt at L2+, and the Definition of Done in
`ai-sdd-process.md` did not mention it. The DoD now names it, so the requirement lives where the level
scaling is defined rather than only in the skill that happens to produce it.

## What the audit checked and found clean

| Check | Result |
|---|---|
| Every hook in `hooks.json` exists and is executable | 13 registrations across 7 events, all resolve |
| Hook files with no registration | only `estimate-ledger.sh` (called by `ledger-record.sh`) and `statusline.sh` (wired into a project by `init`) — both by design |
| `all.sh` suite list ↔ files in `hooks/tests/` | 15 ↔ 15, no orphans either way |
| `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}` paths in skills, agents, guidelines | 0 broken |
| Backticked `guidelines/…`, `templates/…`, `hooks/…` references | 0 pointing at a file that does not exist |
| `.groundwork.json` keys read by hooks vs the project template | every missing key is optional by design (`commands.*`, `gates.analyse_skip_reason`, `openapi.enabled/generator/surface`) |
| Workflow skill names ↔ `workflows/*.js` `meta.name` | three, matching |
| Manifest descriptions identical; `claude plugin validate .` | passes, plain and `--strict` |
| Test-count claim in the README | corrected to the measured 313 cases / 15 suites |

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | The two research agents can reach Context7 however it is installed | met — both server forms listed |
| AC2 | The README describes the gate that actually ships | met — both toolchains, both config keys, the usability check |
| AC3 | The receipt, the snapshot and the mock appear in the README | met — two new bullets |
| AC4 | The Definition of Done names the receipt at L2+ | met |
| AC5 | The suite stays green | met — 313 cases, 15 suites |
