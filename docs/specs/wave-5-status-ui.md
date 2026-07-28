# Spec: Wave 5 — status / UI surfacing (plugin v0.9.0)

- Type: plugin self-improvement (status line + hook display fields + init wiring + docs)
- Source: user request ("улучшить UI и отображение статусов и текущих действий"); capability basis below
- Status: approved → implemented (2026-06-26); statusline tests 7/7 + guard 15/15 (no regression); conformance CONFORMS (W5-AC1–AC7)
- Target version: v0.9.0

## Goal

Surface the workflow's **live state** and **current action** in the Claude Code UI, plugin-shipped and
fail-safe. Three layers: a persistent status line (where am I), in-action spinner messages (what's
running now), and a session banner/title (what task).

## Capability basis (grounded; confidence honest)

From a docs sweep (code.claude.com). Several fields are documented; a few are **UNKNOWN** and get a
defensive design + an in-project `claude --debug` confirmation (the Wave-0 discipline — never encode a
guess):

| Surface | Plugin-shippable | Confidence | Note |
|---|---|---|---|
| `statusMessage` on a hook command | yes (hooks.json) | medium | spinner text while a hook runs — "current action" |
| `sessionTitle` (SessionStart output) | yes | high (documented) | dynamic session/tab title |
| `systemMessage` (hook output) | yes | medium | user-visible line; **exit 0 only** (exit 2 ignores stdout) |
| persistent `statusLine` (settings.json) | **no** — user-level; `init` wires a shipped script | UNKNOWN schema | the rich bottom bar |
| `subagentStatusLine` (plugin settings.json) | yes | low — schema undocumented | deferred to a later spike |

**Residual unknowns (confirm in-project via `claude --debug`, like Wave 2):** exact `statusLine`
settings wiring + the stdin JSON it receives; whether `statusMessage`/`systemMessage` render in the
user's CC version. Everything degrades to a no-op if unsupported.

## Scope (Wave 5)

(1) `statusline.sh` + `init` wiring; (2) `statusMessage` on the existing hooks; (3) `sessionTitle` +
`systemMessage` on SessionStart. **Out:** `subagentStatusLine` (undocumented schema — its own spike
later); the proven `pre-tool-guard.sh` exit-2 deny mechanism is **unchanged** (no destabilizing Wave 2).

## Design — file by file

### `hooks/statusline.sh` (new) — the persistent bar

One line: `Groundwork · <branch>[*<dirty>] · <engine> · <mode> L<level> · spec:<name>`. Reads
`.groundwork.json` (engine/runner), `.claude/groundwork/task-state.md` (mode/level/spec), git
(branch/dirty). Reads stdin JSON defensively (CC passes session info) but does **not** depend on it.
Fail-safe: outside a Groundwork project (no `.groundwork.json`) → print nothing, exit 0. Honors a
`ui.statusline` toggle.

### `init` wiring (skills/init/SKILL.md)

`init` **offers** to add to the project `.claude/settings.json` (the user's file — the plugin cannot
ship `statusLine` directly):
```json
"statusLine": { "type": "command", "command": "<abs path to the plugin>/hooks/statusline.sh" }
```
Because plugin-root resolution inside user settings.json is one of the UNKNOWNs, `init` writes the path
it resolves at init time and notes the `claude --debug` confirmation step. Off unless the user accepts.

### `statusMessage` on the existing hooks (hooks/hooks.json)

Add a `statusMessage` to each hook command so the user sees the current action while it runs:
- PreToolUse `pre-tool-guard.sh` → "Groundwork: checking command…"
- PostToolUse format → "Groundwork: formatting…"
- Stop `done-gate.sh` → "Groundwork: static analysis…"
- Stop `test-gate.sh` → "Groundwork: running tests…"
- SessionStart → "Groundwork: loading project state…"
Pure config; if the field is unsupported it is ignored (no-op).

### `sessionTitle` + `systemMessage` on SessionStart (hooks/session-start.sh)

The hook already emits `additionalContext`. Extend its JSON output (exit 0) with:
- `sessionTitle`: `Groundwork: <task title or branch> [<mode> L<level>]` (from task-state, else branch).
- `systemMessage`: a one-line banner — `Groundwork · <branch> · <engine> · <mode> · spec:<name>` — so the
  user sees the state without reading context. Honors `ui.status_messages` (default on).

### Config + docs

- `templates/project/.groundwork.json` — new `ui` block: `statusline` (default false — opt-in, needs
  settings.json wiring), `status_messages` (default true).
- `README.md` — a "Status / UI" section: what shows, the toggles, the `init` wiring, the `claude
  --debug` confirmation.
- `.claude-plugin/plugin.json` → `0.9.0`.

## Acceptance criteria (EARS — dogfooding E4)

- [ ] **W5-AC1** WHEN `statusline.sh` runs in a Groundwork project THE SYSTEM SHALL print one line with
      branch · engine · mode · level · spec. → test: hooks/tests/statusline.sh cases
- [ ] **W5-AC2** WHEN `statusline.sh` runs outside a Groundwork project (no `.groundwork.json`) OR
      `ui.statusline` is false THE SYSTEM SHALL print nothing and exit 0. → test: statusline cases
- [ ] **W5-AC3** WHEN `.claude/groundwork/task-state.md` is absent THE statusline SHALL still render
      (mode/level/spec shown as "—"), never error. → test: statusline cases
- [ ] **W5-AC4** THE `hooks.json` SHALL carry a `statusMessage` on each hook command describing the
      action. → check: hooks/hooks.json
- [ ] **W5-AC5** THE SessionStart hook SHALL output `sessionTitle` and (when `ui.status_messages`)
      `systemMessage`, AND SHALL remain valid JSON / exit 0 / degrade to additionalContext-only if those
      fields are unsupported. → test: session-start.sh output is valid JSON with the fields
- [ ] **W5-AC6** THE `init` skill SHALL offer (not force) the `statusLine` settings.json wiring and note
      the `claude --debug` confirmation. → check: skills/init/SKILL.md
- [ ] **W5-AC7** IF any display field is unsupported in the user's CC version THEN the plugin SHALL
      degrade to a no-op (never break a session or a gate). → design invariant; verified by fail-safe.

## Risks / assumptions

- **Undocumented render fields** — `statusLine` wiring, `statusMessage`, `systemMessage` may not render.
  Mitigation: defensive design (every field optional, ignored if unsupported) + the `claude --debug`
  confirmation step. The Wave 2 gate is untouched.
- **Noise** — too many status messages annoy. Mitigation: terse text, `ui.status_messages` toggle,
  statusline opt-in.
- **settings.json path resolution** for the shipped statusline script — `init` writes a resolved path
  and flags confirmation.

## Rollout

- Version **v0.9.0**. Additive; no behavior change to gates. Release note: status/UI surfacing is
  opt-in for the bar, on for messages, all fail-safe.
- Commit (single line, no AI attribution): `feat: v0.9.0 — status line + in-action hook messages + session banner`.

## Verification plan

Local executable proof for `statusline.sh` (a `hooks/tests/statusline.sh` harness, case per W5-AC1–AC3);
validate `session-start.sh` still emits valid JSON with the new fields; `conformance-reviewer` dogfood
on the diff. Then the residual `claude --debug` in-project confirmation of which fields actually render.
