# Spec: Wave 2 — enforcement engine (plugin v0.6.0)

- Type: plugin self-improvement (PreToolUse hook + config + docs + shell tests)
- Source: [plugin-enhancement-roadmap.md](plugin-enhancement-roadmap.md) E1; E2 resolved per
  [wave-0-capability-confirmation.md](wave-0-capability-confirmation.md)
- Status: approved → implemented (2026-06-26); hook tests 15/15 green; conformance review CONFORMS (AC1–AC7)
- Target version: v0.6.0
- Depends on: Wave 0 (E1 = **GO**; E2 = dropped/reframed)

## Goal

Turn the advisory rules — "all Laravel/PHP through the runner", "never edit a shipped migration",
"no code while planning" — into engine-level `PreToolUse` denials. Fail-safe, opt-out aware, never
breaks a non-RaDevs repo.

## Scope (Wave 2)

E1 only: (a) runner enforcement **on**, (b) shipped-migration lock **on**, (c) discovery edit-lock
**off by default** (the reframed remainder of E2). **E2's native plan-mode gate is dropped** — Wave 0
proved it undocumented; the conversational `start-task`→`implement-approved` gate plus the optional
(c) toggle plus a docs recommendation cover the need. No Plan Mode, no Workflow here.

## Out of scope / future

Deep workflows (Wave 3); E5/E8/E9 (Wave 4). The (c) toggle ships **off**; turning it on is a project
decision.

## Design — file by file

### New `hooks/pre-tool-guard.sh` (PreToolUse)

Contract (all verified in Wave 0): read the stdin JSON (`tool_name`, `tool_input`, …); **exit 0 to
allow** (silent), **exit 2 + a stderr reason to deny** (the documented blocking path; stderr is fed
back so the model self-corrects). Fail-safe everywhere: any missing field, parse error, or absent
config → exit 0 (allow). Only acts in a RaDevs project (`.groundwork.json` present).

- **(a) Runner enforcement** — toggle `gates.enforce_runner` (default `true`); tool `Bash`,
  `cmd = .tool_input.command`:
  - The runner prefix comes from `.groundwork.json` `.runner` (default `sail` → `./vendor/bin/sail`).
  - Deny when `cmd`'s first real verb (after optional leading `VAR=val ` assignments) is one of
    `php` / `composer` / `artisan` / `phpunit` / `pest` **and** the command is not already routed
    through the runner (`./vendor/bin/sail`, `sail`, or `vendor/bin/sail`).
  - Deny reason quotes the corrected command (`use ./vendor/bin/sail <cmd>`).
  - **Bootstrap fail-open:** if `./vendor/bin/sail` is absent or not executable (fresh clone before
    `composer install`), allow — do not block host `composer`/`php`.
- **(b) Shipped-migration lock** — toggle `gates.lock_shipped_migrations` (default `true`); tools
  `Edit`/`Write`, `path = .tool_input.file_path` (read defensively; Wave 0 residual unknown):
  - Deny when `path` is under `database/migrations/` **and** git-tracks it
    (`git ls-files --error-unmatch "$path"` succeeds). Reason: "shipped migration — add a new migration
    instead of editing a committed one." New (untracked) migration files are allowed.
- **(c) Discovery edit-lock** — toggle `gates.lock_edits_in_discovery` (default **`false`**); tools
  `Edit`/`Write`:
  - When the toggle is on **and** `.claude/groundwork/task-state.md` mode is `Discovery` or `Plan`, deny
    edits to **app code** (exclude `.claude/groundwork/**`, `docs/**`, the spec/checkpoint files — those
    are planning artifacts). Reason: "in <mode> — approve the plan before implementing."
  - Off by default (locked roadmap decision): when off, allow.

### `hooks/hooks.json`

Add a `PreToolUse` block, matcher `"Bash|Edit|Write"` → `${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-guard.sh`.

### `templates/project/.groundwork.json`

Add under `gates`: `enforce_runner` (true), `lock_shipped_migrations` (true),
`lock_edits_in_discovery` (false).

### `hooks/tests/` (new — executable proof for a denying hook)

A denying hook can break the user's workflow, so it earns tests (the grounding protocol's "executable
proof"). A tiny POSIX harness (`run.sh`) feeds crafted JSON to `pre-tool-guard.sh` on stdin and asserts
the exit code (+ stderr substring). One case per acceptance criterion below. No framework — plain bash.

### Docs

- `guidelines/laravel-standards.md` — note the runner rule and the shipped-migration rule are now
  **hook-enforced** (not just advisory).
- `README.md` — gates section gains the three toggles; "What's inside" mentions PreToolUse enforcement;
  add a short note that the plan-approval gate is the `start-task`→`implement-approved` split (+ the
  optional `lock_edits_in_discovery` toggle, + native plan mode via `defaultMode: "plan"` for those who
  want it).
- `.claude-plugin/plugin.json` → `0.6.0`.

## Acceptance criteria (EARS — each maps to a hooks/tests case)

- [ ] **AC1** WHEN a `Bash` command runs `php`/`composer`/`artisan`/`phpunit`/`pest` not via the runner
      AND `./vendor/bin/sail` is executable AND `enforce_runner` is true THE SYSTEM SHALL exit 2 and
      print the runner-prefixed command on stderr. → test: hooks/tests/run.sh::runner_deny
- [ ] **AC2** WHEN an `Edit`/`Write` targets a git-tracked file under `database/migrations/` AND
      `lock_shipped_migrations` is true THE SYSTEM SHALL exit 2. → test: hooks/tests/run.sh::migration_lock
- [ ] **AC3** IF `.groundwork.json` is absent OR the relevant toggle is false THEN THE SYSTEM SHALL
      exit 0 (no-op). → test: hooks/tests/run.sh::no_op
- [ ] **AC4** WHEN the command is already routed through the runner (`./vendor/bin/sail …`) THE SYSTEM
      SHALL exit 0. → test: hooks/tests/run.sh::runner_allow
- [ ] **AC5** WHEN `./vendor/bin/sail` is absent or not executable THE SYSTEM SHALL exit 0 for host
      `composer`/`php` (bootstrap fail-open). → test: hooks/tests/run.sh::bootstrap
- [ ] **AC6** WHILE `lock_edits_in_discovery` is true AND `task-state.md` mode is `Discovery`/`Plan`,
      WHEN an `Edit`/`Write` targets app code THE SYSTEM SHALL exit 2; WHILE the toggle is false THE
      SYSTEM SHALL exit 0. → test: hooks/tests/run.sh::discovery_lock
- [ ] **AC7** IF the stdin JSON is malformed OR a needed field is missing THEN THE SYSTEM SHALL exit 0
      (fail-open, never break a tool call on a hook bug). → test: hooks/tests/run.sh::fail_open

## Risks / assumptions

- **Over-blocking (false deny)** — the worst failure for a gate. Mitigations: narrow verb matcher,
  fail-open on every uncertainty, all toggles, corrected-command in the reason, and the
  per-AC shell tests above. (a) only matches the bare host verb not already routed through the runner.
- **`auto` permission mode** (Wave 0 residual unknown) — confirm an exit-2 deny still blocks while the
  session is in `auto` mode during implementation; if not, document the limitation.
- **Edit input key** (Wave 0 residual unknown) — read `.tool_input.file_path` with a fallback and
  confirm once via `claude --debug`.
- **Assumption** — the existing fail-safe hook style (opt-out aware, Sail-availability check) is the
  right model; this hook copies it.

## Rollout

- Version **v0.6.0**. **BEHAVIOR CHANGE** — a host `php/composer/artisan` command that used to run can
  now be denied. The release note must flag this and the opt-out toggles (`gates.enforce_runner`,
  `gates.lock_shipped_migrations`, `gates.lock_edits_in_discovery`).
- Commit (single line, no AI attribution): `feat: v0.6.0 — PreToolUse enforcement (runner-only, shipped-migration lock)`.

## Verification plan

Run `hooks/tests/run.sh` (all AC cases green) — the executable proof for a shell gate. Then dogfood:
spawn the `conformance-reviewer` on the diff vs AC1–AC7. Confirm the residual unknowns via
`claude --debug` in a real project before declaring done.
