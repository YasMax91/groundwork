# follow-through

Project-agnostic Claude Code hooks on how an agent ends its turn. Works in any repository, with no init
step. Part of the [`yasmax`](../README.md) marketplace; specification:
[wave 34](../docs/specs/wave-34-the-agent-hears-the-gate.md).

```
/plugin install follow-through@yasmax
```

## What it checks

| Check (config key) | Event | Verdict |
| --- | --- | --- |
| `announce_stop` — the final paragraph announces a step («Беру…», "Next I'll…") and the turn ends | Stop | block |
| `empty_reply` — empty or "No response requested" after a real user message | Stop | block |
| `prose_question` — the last sentence asks the user, no `AskUserQuestion` in the turn | Stop | block |
| `hand_back` — «залогинься», «пришли скрин», «запусти сам» with no stated reason | Stop | block |
| `language` — `CLAUDE.md` says "only in Russian/Ukrainian" and < 50 % of prose letters are Cyrillic | Stop | block |
| `outbound` — inside ```` ```outbound <addressee> ````: «—», lists, identifiers, AI mentions, length, an unsourced "cannot" | Stop | block |
| `ui_proof` — a UI file was edited, completion is claimed, no browser/simulator screenshot after the last edit and no «UI не проверен: …» line | Stop | block |
| `destructive` — `lane.py down --purge`, `migrate:fresh` off the testing DB, discarding uncommitted git changes, Docker volume removal, `pkill`/`horizon:terminate`, editing a gate or permission config | PreToolUse | ask |

All Stop findings go back to the model in one `decision: block`; on the re-entry
(`stop_hook_active`) the gate is silent, so a turn costs at most one extra round. The PreToolUse check
returns `permissionDecision: "ask"` only — your own `deny`/`ask` rules still win. Any parse error, a
missing transcript or a missing tool means allow.

## Parallel sessions (v0.2.0)

Every session registers itself in `<git-common-dir>/follow-through/sessions/` — shared by all worktrees
of the repository, never committed — with its branch, task, the files it edited and, for groundwork
lanes, its containers.

| What | When | Effect |
| --- | --- | --- |
| awareness | session start; your message, when something changed | the other live sessions (branch, task, files, `doing` rows of their status file), how far the base moved and whether it touched your files, what is deployed where |
| fresh base | first start of a worktree with no commits of its own | moved to `base_branch`, else `origin/development`, else `origin/HEAD` — the app branches worktrees from `origin/HEAD`, and `worktree.baseRef` cannot name a branch |
| one tree, one session (`lanes`) | first edit in a tree another live session uses | denied once: enter your own lane |
| overlap (`lanes`) | first edit of a file a live sibling edited | denied once with the sibling's name: message it (ListAgents → SendMessage), then retry |
| a sibling's process (`lanes`) | `docker stop`/`kill`/`compose down` naming a sibling's container or port | permission prompt |
| freshness (`freshness`) | "done" while the base moved under files you changed | Stop blocks once: rebase and re-run |
| status (`status`) | a commit, merge, push or deploy with `docs/ai/status.md` untouched; the file changed and its `mirror:` artifact not republished | Stop blocks once; escape «статус не меняется: <почему>» |
| memory | session start | memory facts naming repo paths that no longer exist |

`docs/ai/status.md` is created by the `follow-through:status` skill — from an existing «Ревизия»
artifact if there is one. Its front-matter can name `environments:` (`branch`, `version_url`,
`deploy_cmd`); deploys matched by `deploy_cmd` are recorded in `deploys.json` beside the registry.

## Outbound fence options

```` ```outbound BA lists max=1500 ids-ok ai-ok ```` — `lists` allows bullets, `max=` changes the 900
character limit, `ids-ok` allows identifiers, `ai-ok` allows mentioning AI.

## Configuration

`~/.claude/follow-through.json`, overridden by `<project>/.claude/follow-through.json`:

```json
{ "gates": { "prose_question": false }, "outbound_max": 1200, "chat_language": "off" }
```

`chat_language`: omitted → detected from `CLAUDE.md`; `"ru"`/`"uk"` → always on; `"off"` → never.

## Trial log

Every trigger appends `time · project · session · check · excerpt` to
`~/.claude/follow-through/triggers.log`. Thresholds are tuned from it.

## Tests

```
python3 -m unittest discover -s follow-through/hooks/tests
```

Also run by `hooks/tests/all.sh` and CI. Requires `python3` (3.9+) and `git`.
