# Spec: Wave 39 — each agent on the model its role needs, and the effort the task's level needs (groundwork v0.49.0)

- Type: agent definitions, skill and workflow instructions, and a mod → **L2**.
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-21: *«научить агентов использовать разные модели и уровни их усилий исходя из
  сложности, глубины и т.п.»*
- Decisions taken with the author on 2026-10-21: models by role, the code-mapping agent switched only after a
  measurement · the main session's effort follows the task level both ways, through a mod.
- Status: **implemented** (2026-10-21).

## What was measured (2026-10-06 12:17 UTC – 2026-10-21, all transcripts)

- Every subagent ran on `claude-opus-5-5`, inherited from the main session: 141 `Agent` calls from main
  sessions (impact-mapper 41, conformance-reviewer 37, general-purpose 21, blind-spot-mapper 19,
  adversarial-verifier 15, grounded-researcher 5, Explore 2), none passing `model` or `effort`.
  `agents/*.md` carry `effort` (high; impact-mapper medium) and no `model`.
- Token volume, weighted by API price ratios: main sessions 87.6 %, subagents 12.4 % (general-purpose 6.0,
  impact-mapper 3.2, conformance-reviewer 1.4, adversarial-verifier 0.9).
- The account is on Max: shared 5-hour and weekly limits, plus a separate weekly Fable limit (0 % used on
  2026-10-21). How much of the shared limit each model consumes is not published.

## Facts this rests on (Claude Code 2.1.304, the desktop app's build)

- Agent frontmatter `model` (`sonnet`, `opus`, `haiku`, `fable`, a full id, `inherit`) and `effort` (`low`
  … `max`) apply to plugin agents; precedence: the `Agent` call's `model`/`effort`, then frontmatter, then the
  session (code.claude.com/docs/en/sub-agents, «Choose a model», «Choose an effort level»). `agent(prompt,
  {model, effort})` in a workflow script.
- A session cannot change its own model or effort (the desktop app refuses `set_session_model` /
  `set_session_effort` on itself). A mod can: `turn.step` → `next({ ...e, effort })` per request, with
  `e.agentId` set for a subagent's request; `agent.spawn` → `next({ ...e, model })`
  (code.claude.com/docs/en/plugins/mods/reference, «Turns», «Agents»). A plugin becomes a mod by listing a
  module under `modules` in `hooks/hooks.json`.
- On Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1 with a subscription a change of effort keeps the prompt
  cache; a change of model does not (docs/en/prompt-caching). So the main session's model is never switched.
- API price per MTok in / out: Fable 5.1 $10 / $50, Opus 5.5 $4 / $20, Sonnet 5.5 $2 / $10, Haiku 5.5 $0.10
  / $0.50 up to 100K-token prompts (platform.claude.com/docs/en/about-claude/pricing, 2026-10-21).
- `max` «may show diminishing returns and is prone to overthinking» (docs/en/model-config, «Choose an effort
  level»), so `max` is kept for the critical level only.

## Changes

- **GW39-AC1 — models by role** (`agents/*.md`): `grounded-researcher` `model: sonnet`, `effort: medium`;
  `conformance-reviewer`, `adversarial-verifier`, `blind-spot-mapper` `model: opus`, `effort: high` (opus
  even when the main session runs something else); `impact-mapper` `model: sonnet`, `effort: medium` **only
  if AC2 passes**, otherwise it stays on the session's model.
- **GW39-AC2 — the mapping agent's measurement, before AC1 touches it**: six past otaje tasks whose cached
  impact maps name their seeds; `impact-mapper` run on today's code with the same seeds once on Opus and once
  on Sonnet at `medium`; the files each map names are compared. Sonnet passes when it names ≥ 95 % of the
  files the Opus map names over the six, and ≥ 90 % in each. Recorded in this spec with time and tokens per
  run.
- **GW39-AC3 — effort by the task's level for the agents** (one table, `guidelines/ai-sdd-process.md` §Fan-out
  by level, read by `start-task`, `final-check`, `ground-integration`, `spec`):

  | Level | mapping, research | checkers |
  |---|---|---|
  | L2 normal | medium | high |
  | L3 high-risk | high | xhigh |
  | L4 critical | high | max |

  The skills pass the level's `effort` on each `Agent` call; the three workflows take `args.level` and pass
  `{ model, effort }` per phase (find/map: the mapping row; verify/conform: the checkers' row).
- **GW39-AC4 — the main session's effort by the task's level** (`hooks/effort.mjs`, a mod): on each main
  request (`turn.step` without `e.agentId`) in a groundwork project, the level the checkpoint states sets the
  effort — L0 docs/typo `medium`, L1 and L2 `high`, L3 `xhigh`, L4 `max`. No level, or the task closed → the
  request goes unchanged, at the effort chosen in the menu. The same table also sets the effort of a
  groundwork agent's requests (`e.agentId` mapped to its type at `agent.spawn`), so AC3 holds even when the
  skill text is not followed.
- **GW39-AC5 — visible**: when the mod changed the effort, the turn ends with one dim line — the level and
  the reason in plain words (`усилие: высокое — задача с кодом`).
- **GW39-AC6 — off switch**: `.groundwork.json` `effort.by_level: false` turns the mod off;
  `effort.table` overrides levels. Outside a groundwork project the mod does nothing.

## Verification

- AC2: six pairs of maps, the per-task and total coverage, recorded here before AC1's impact-mapper line.
- The mod: a test harness feeding `turn.step` / `agent.spawn` events (no level, each level, closed task,
  `effort.by_level: false`, a non-groundwork cwd, a groundwork subagent and a foreign one).
- Live: one session per level in a scratch groundwork project, `/effort status` and the dim line read after a
  turn; one `impact-mapper` and one `conformance-reviewer` spawn, their model and effort read in `/tasks`.
- `claude plugin validate` clean; all groundwork suites green.

## Result (2026-10-21)

- **AC2, the mapping agent's measurement** — `impact-mapper` with the same seeds on otaje origin/development
  (91f03bb7), once with `model: opus`, once with `model: sonnet` (both at the file's `medium`); files each map
  named in its `FILES:` list:

  | Task | Opus files, time, tool calls | Sonnet files, time, tool calls | Sonnet named of Opus's |
  |---|---|---|---|
  | collections «All» tab | 135, 264 s, 26 | 151, 208 s, 22 | 87.4 % |
  | variant base price reads | 135, 516 s, 57 | 115, 156 s, 17 | 67.4 % |
  | 1C failure text | 128, 337 s, 34 | 131, 147 s, 13 | 82.8 % |
  | admin session resume | 197, 470 s, 49 | 104, 144 s, 11 | 46.7 % |
  | blog article page editor | 199, 470 s, 67 | 143, 179 s, 17 | 64.3 % |
  | gift certificates | 366, 841 s, 87 | 469, 739 s, 67 | 80.1 % |
  | **total** | 1160 | | **71.4 %** (828 of 1160) |

  Below the 95 % / 90 % bar: `impact-mapper` stays on the session's model. Opus named only 62-90 % of
  Sonnet's files in turn, so one run is no ground truth either way; the gap is on the deep tasks, where Opus made
  3-4× the tool calls. Both runs noticed that the blog task's block-builder seeds were deleted on 2026-10-13 (Opus counted six, Sonnet seven).
- AC1, AC3, AC6 as specified. AC4/AC5: `hooks/effort.ts` registered under `modules` in `hooks/hooks.json`;
  `claude plugin validate` (2.1.304 and 2.1.236) lists its hooks `turn.step`, `turn.complete` and calls
  `$.agent.list`, `$.fs.exists`, `$.fs.read`; `hooks/tests/effort.sh` 24 of 24 on its decisions. Live, a
  headless 2.1.304 session in a scratch project with an L3 checkpoint printed «усилие: очень высокое —
  рискованная задача» under the answer; its model request did not go out (the headless CLI had no login), so
  that the model received `xhigh` rests on the mods API, not on an observed request.
- All groundwork suites green.

## Not in this wave

- Explore and general-purpose agents keep the session's model (21 general-purpose calls in the period:
  audits, translations, answer collection) — a candidate once AC2 shows what Sonnet holds.
- Fable for checks: not chosen on 2026-10-21; the separate weekly limit stays unused.
