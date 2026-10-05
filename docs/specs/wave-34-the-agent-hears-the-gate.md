# Spec: Wave 34 — the agent hears the gate, and the gate leaves Laravel (groundwork v0.44.0 + new plugin `follow-through` v0.1.0)

- Type: plugin self-improvement across two layers — a new project-agnostic plugin in the `yasmax`
  marketplace, and a groundwork wave. New Stop and PreToolUse hooks, three existing hooks change from
  warning to blocking → **L3**.
- Author: Max Yastremskyi (YasMax91).
- Source: a sweep of every main-session transcript under `~/.claude/projects` on 2026-10-05 —
  **2472 of 2472** user messages from **493** sessions across **25** projects, read in 8 chunks, each
  chunk read to its last line (8 of 8). Not in the denominator: answers given through `AskUserQuestion`
  (stored as tool results, not messages), subagent transcripts, `/private/tmp` probe sessions.
  Duplicate sessions (one message sent to two sessions) are counted once.
- Decisions taken with the author on 2026-10-05: two layers · first-priority classes 1, 4+5, 9, 3+7 ·
  block from day one with a trial log · universal plugin lives in this repository · destructive
  commands go to the native permission prompt · outbound texts are marked by a fenced block · UI with
  no browser gets an honest status plus a local-only seeded login.
- Status: **implemented** (2026-10-05), approved by the author the same day. Hook behaviour proven by
  tests; a live headless run was not possible (CLI OAuth expired) — see **Verification**.

## What the sweep found

580 complaints. Counts are approximate where two readers split a class differently.

| # | Class | ≈ | Projects (of 25) |
|---|---|---|---|
| 1 | "Done", and the user finds the defect at first look — mostly UI checked by tests/compilation/exit code, one theme, one viewport, local instead of staging | 150 | 14 |
| 2 | Partial coverage — ТЗ items and subtasks dropped, adjacent surfaces missed (gateway repo, exports, show pages, mobile), scope cut silently | 70 | 13 |
| 3 | Text for a client/BA — long, bullet lists, «—», AI tone, field names, internal jargon | 70 | 8 |
| 4 | Stops mid-plan — «Беру X» and the turn ends, "No response requested", «продолжать?» under an approved plan (≈30 «Продолжай» in radevs-commerce-core alone) | 65 | 10 |
| 5 | Work handed back — «залогинься», «пришли скрин», «запусти на dev сам», asking what is in `.env`/compose/memory | 55 | 12 |
| 6 | Standing instructions lost — `AskUserQuestion`, Russian, sail, "update artifact X immediately" | 45 | 11 |
| 7 | Estimates — person-hours, process stages missing, inflation, sums not re-added | 35 | 7 |
| 8 | Claims without a source — «журнал 1С», «ювелирка», "Meta forbids wa.me", «выписать нельзя» | 30 | 7 |
| 9 | Destructive actions — `migrate:fresh` wiped the dev DB, tests overwrote the working `crm_wigs` DB, `git checkout <file>` destroyed edits, the agent disabled a gate in `.company-sdd.json`, `horizon:terminate` left down, `pkill` dropped the stand | 15 | 6 |
| 10 | Environment ignored — Docker in prod, no sudo, UTC timestamps, stale worker | 12 | 5 |

Commit attribution (7 complaints, May–June) is already closed: `~/.claude/settings.json` has
`attribution.commit: ""`. Not in scope.

## Why the existing plugin did not stop it

1. **The three gates that read what the agent says never reach the agent.** `coverage-claim.sh`,
   `estimate-claim.sh` and `plain-language.sh` answer with `systemMessage` only — shown to the user,
   not fed back to the model. Their logs prove they fired while the complaints continued:
   otaje `plain-language.log` 149 lines, `estimate-claims.log` 25, `coverage-claims.log` 2;
   next-lvl-backend `estimate-claims.log` 5.
2. **Every gate is inert outside a Laravel project with `.groundwork.json`.** Classes 1, 3, 4, 5, 9 hit
   budget-hub (mobile), tiles-survive, three Python bots, fam-sync, portfolio-site and tatzaot (no
   `.groundwork.json`) exactly as they hit the Laravel projects.
3. **Browser proof is prose.** `skills/final-check/SKILL.md:52` asks for a real browser on Admin/UI/CSS
   changes; nothing checks that a browser tool ran. September otaje sessions (v0.41+) still carry
   22 UI complaints.
4. **No gate looks at a turn that ends on an announcement**, a request to the user, or a prose question.
5. **`pre-tool-guard.sh` guards the runner and shipped migrations only** — none of the class-9 commands.

## Layer A — new plugin `follow-through` (any project, no init)

Lives at `./follow-through` in this repository, third entry in `.claude-plugin/marketplace.json`,
pulled in by `groundwork-pack`. Reuses `hooks/lib.sh` conventions and the hook test runner.
Fail-safe contract identical to groundwork: any parse error, missing tool or uncertainty → allow.
Every block is one re-entry: `stop_hook_active: true` → exit 0.

**FT-AC1 — announce-and-stop.** Stop hook. Block when the last assistant message's final paragraph
matches an intent pattern (`Беру|Перехожу|Начинаю|Приступаю|Продолжаю с|Сейчас (сделаю|запущу)|Next,? I'?ll|I'?ll now|Moving on to`)
and no tool call follows it in the turn. Reason fed back: do the announced step now.

**FT-AC2 — empty reply.** Stop hook. Block when the last assistant message is empty or equals
"No response requested." and the last user message is longer than 20 characters.

**FT-AC3 — prose question.** Stop hook. Block when the last message ends with a question to the user
(last sentence ends in `?`, or contains `скажи(те)?,? (какой|что|как)|выбери|жду (твоего|вашего) (решения|ответа)|продолжать\?|продолжить\?`)
and no `AskUserQuestion` call happened in the turn. Reason: ask through `AskUserQuestion`.
Exempt: text inside an outbound block (FT-AC6).

**FT-AC4 — handing work back.** Stop hook. Block when the message asks the user to perform an action
(`залогинься|войди (в|на)|пришли (скрин|скриншот|вывод)|скажи,? как (выглядит|отображается)|запусти (сам|у себя)|выполни на сервере|run (it|this) yourself|send me a screenshot`)
and does not carry a stated blocker on the same message (`нет доступа|не могу, потому что|requires your password|только ты можешь`).

**FT-AC5 — language.** Stop hook. When `~/.claude/CLAUDE.md` or the project `CLAUDE.md` names Russian
or Ukrainian as the chat language: block when Cyrillic letters are under 50 % of letters in the prose
of the last message (code fences, inline code, URLs, paths and outbound blocks excluded) and prose has
≥ 120 letters.

**FT-AC6 — outbound block.** Any text the user will forward is written as
```` ```outbound <addressee> ```` … ```` ``` ````. Stop hook checks only the inside of such blocks and
blocks on: `—`; a line starting with `- `, `* `, `• ` or `\d+\.` (unless the addressee line says
`lists`); a `snake_case` identifier, a `Model::` / table name, a file path or an AC/OQ/PB id (unless
`ids-ok`); any of `AI|ИИ|Claude|LLM|GPT|нейросет` (unless `ai-ok`) — «агент» was dropped from the draft
list because it is a domain term in next-lvl-backend (Field Agent); more than 900 characters (override `max=<n>` on the fence line); a
negative claim about an external service (`нельзя|невозможно|не поддерживает|cannot|not supported`)
with no URL and no `проверено запросом` in the same block. The rule text ships in the plugin's
`CLAUDE.md`-loaded guideline so the agent knows the format before the gate fires.

**FT-AC7 — UI proof.** Stop hook. Reads `transcript_path`. When the turn edited a UI file
(`*.blade.php, *.vue, *.tsx, *.jsx, *.svelte, *.css, *.scss, resources/js/**, *.dart, app/**/*.xml (Android layouts)`)
and the last message claims completion (`готово|сделано|работает|исправ(ил|лено)|починил|done|fixed|works now`):
pass only if, after the last such edit, a browser or simulator tool ran
(`mcp__Claude_Browser__*`, `mcp__plugin_playwright_*`, `mcp__claude-in-chrome__*`,
`mcp__Claude_Code_iOS_Simulator__*`) **and** produced a screenshot — or the message contains a line
`UI не проверен: <screens>`. Otherwise block.

**FT-AC8 — destructive commands → native prompt.** PreToolUse(Bash|Edit|Write) returns
`permissionDecision: "ask"` with a one-line reason for:
`migrate:fresh|migrate:reset|db:wipe|migrate:refresh` unless the same command sets a testing DB
(`--env=testing`, `DB_DATABASE=*test*`); `DROP (DATABASE|TABLE)|TRUNCATE` in a mysql/psql call;
`git checkout -- <path>`, `git checkout <ref> -- <path>`, `git restore`, `git reset --hard`,
`git clean -f*`, `git stash drop|clear` while `git status --porcelain` is non-empty;
`docker compose down -v`, `docker volume rm`; `horizon:terminate`, `pkill`, `killall`, `kill -9`;
Edit/Write on `.groundwork.json`, `.company-sdd.json`, `.claude/settings*.json`,
`.claude/follow-through.json`, `.claude/hooks/**`, `.git/hooks/**`, `.husky/**`, and a shell write
(`sed -i`, `>`, `tee`, `mv`, `rm`, `cp`) to the config files. Narrowed from the draft's `**/hooks/**`,
which would prompt on every edit to a plugin's own hooks.
A `deny`/`ask` rule the user set still wins; this never widens anything.

**FT-AC9 — trial log.** Every trigger of FT-AC1…8 appends one line to
`~/.claude/follow-through/triggers.log`: UTC time · project · session · gate · first 160 chars.
The log is the input for threshold tuning after two weeks.

**FT-AC10 — tests.** Each hook gets a suite under `follow-through/hooks/tests/` covering: a blocking
case, a passing case, the `stop_hook_active` re-entry, malformed input → allow. Suites run in the
existing CI matrix (Linux + macOS).

## Layer B — groundwork v0.44.0

**GW34-AC1 — the claim gates reach the model.** `coverage-claim.sh`, `estimate-claim.sh`,
`plain-language.sh` (Stop path) return `{"decision":"block","reason":…}` instead of `systemMessage`,
keep their logs, keep the `stop_hook_active` guard. Opt-out per gate stays in `.groundwork.json`.

**GW34-AC2 — estimates in documents.** `estimate-claim.sh` also scans files under `docs/**` changed in
the turn and outbound blocks: block on `человеко|person-?(day|hour)|man-?hour|\d+[,.]?\d*\s*(дн(я|ей)|days?)`
next to an estimate, and on an hours total that does not equal the sum of its rows in the same table.

**GW34-AC3 — requirement trace.** `skills/spec` template gains `## Source requirements`: every item of
the ТЗ / user request, subtasks and notes included, quoted verbatim with an id `R<n>` and its source
(message time or file:line). `slice-gate.sh` blocks "done" while any `R<n>` has no proof cell
(test name, HTTP run, screenshot, or `out of scope: <reason agreed with user>`).

**GW34-AC4 — local login for the agent.** `skills/init` adds, when an admin panel exists: a seeder that
creates a local-only admin (guarded by `app()->environment('local','testing')`), credentials written to
`.env.example` / the seeder, and `dev_login` recorded in `.groundwork.json`. `final-check` uses it
instead of asking the user to log in.

**GW34-AC5 — UI matrix.** `skills/final-check` UI step names the set: every changed screen plus every
screen that includes a changed shared CSS/JS file; both themes when the project has two; 375 and 1440
widths. The receipt records `screens checked n/m`. FT-AC7 enforces that the run happened; this AC
defines what the run covers.

**GW34-AC6 — sourced client documents.** `skills/client-doc`: each scope or behaviour statement carries
a source (spec §, file:line, client message) or the label «предложение»; FT-AC6 rules apply to the
document body.

## Out of scope (named, not dropped)

- Class 10 (environment facts) and class 6 beyond FT-AC3/AC5 — next wave: a per-project
  `environment` block written once and read before any server command.
- "A correction becomes a check" — the strongest lever found (abusive replies land on the 2nd–3rd
  repeat of an already named error, not the first), but it needs its own design. Next wave.
- Class 2 beyond GW34-AC3 in non-Laravel projects.

## Verification

Result, 2026-10-05:

- groundwork suites: 21 of 21 green (`bash hooks/tests/all.sh`), including the new `estimate-docs`
  (11 cases) and 3 new `slice-gate` cases; the three claim-gate suites assert a block instead of a warning.
- follow-through: 44 of 44 tests green (python 3.9).
- `claude plugin validate`: marketplace and `follow-through` both pass.
- Replay over the 2064 historical agent turns that a user message followed (all main sessions):

  | check | triggers | next user message was a nudge («продолжай», «да», «делай») or a complaint |
  |---|---|---|
  | announce_stop | 29 | 23 |
  | empty_reply | 32 | 15 |
  | prose_question | 204 | 90 |
  | ui_proof | 56 | 18 |
  | hand_back | 28 | 5 |
  | language | 67 | 6 |

  The column is a keyword heuristic, not a manual label. Sampled by hand: announce 8 of 8 justified;
  prose_question's remainder are real questions asked in prose, which the author's CLAUDE.md requires
  through `AskUserQuestion`; language's remainder are mostly English client texts written outside an
  outbound fence; hand_back's remainder are mostly «пришли вывод» from a prod server the agent could not
  reach — the gate now requires saying so. Not replayed: `outbound` (the fence did not exist) and
  `destructive` (PreToolUse).
- Not run: a live session with the plugin loaded. To do once: enable the plugin, end a turn on
  «Беру…» and check `~/.claude/follow-through/triggers.log`.

Planned:

- Hook behaviour: test suites (FT-AC10, plus updated suites for the three changed groundwork hooks),
  green on CI — stated as cases passed / cases total.
- Replay: each new Stop gate is run against the `last_assistant_message` of the complaint-preceding
  agent turns in the 2026-10-05 corpus; the report states caught / total per gate and every
  false positive found in a 100-message sample of non-complaint turns.
- Trial: two weeks of `triggers.log`, then thresholds tuned in a follow-up commit.
