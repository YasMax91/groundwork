# Wave 0 — platform capability confirmation (verification spike)

Done 2026-06-26. Primary-source-cited confirmation of the platform facts Waves 2–3 depend on, per the
roadmap's grounding note. Researched live against `code.claude.com/docs`. This is the gate before any
enforcement code is written — we resolve the two research agents' earlier disagreement by checking the
docs, not by trusting either. Confidence: `verified` (quoted from primary docs) | `UNKNOWN`.

## Capability matrix

| Capability | Status | Evidence (primary) |
|---|---|---|
| PreToolUse deny via JSON | `verified` | hooks doc: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`; `permissionDecision` ∈ allow/deny/ask/defer; JSON processed only on exit 0. |
| PreToolUse deny via exit 2 | `verified` | hooks doc: "Exit 2 means a blocking error… stderr text is fed back to Claude"; PreToolUse exit-2 = "Blocks the tool call". |
| Hook stdin input | `verified` | hooks doc input: `{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"…"}}`; file tools "include `file_path`". |
| Matcher `Bash` / `Edit\|Write` | `verified` | hooks doc: "`Edit\|Write`… match either tool exactly"; optional `if` field narrows within a matcher. |
| Plan mode = user-toggled interactive mode + built-in approve gate | `verified` | permission-modes doc: enter via `Shift+Tab` / `/plan` / `--permission-mode plan` / `defaultMode` / agent `permissionMode: plan`; "When the plan is ready, Claude presents it and asks how to proceed." |
| **Skill-driven** programmatic `EnterPlanMode`/`ExitPlanMode` gate | **UNKNOWN** | Appears in docs only as tools **denied to subagents**; no documented API for a skill to present-plan-then-await-approval. Do not infer one. |
| `Workflow` (Dynamic workflows) exists + opt-in gated | `verified` | workflows doc: opt-in via `ultracode` / natural language; per-run approval prompt; `disableWorkflows`. Not a Bash-style tool you call directly. |
| Agent frontmatter `model` / `effort` / `tools` | `verified` | sub-agents frontmatter table. |
| Skill frontmatter `allowed-tools` (pre-approves; does not restrict — use `disallowed-tools`) | `verified` | skills frontmatter table. |

## Go / No-go

### E1 — PreToolUse hook (deny host `php/composer/artisan/phpunit/pest`; deny edits to git-tracked migrations) → **GO**

- **Mechanism:** `exit 2` + a stderr reason (the documented blocking path; the official examples use
  exactly this for a Bash-command validator). stderr is fed to the model, so it self-corrects (e.g.
  "use `./vendor/bin/sail …`"). JSON `permissionDecision:"deny"` is the equivalent alternative; reserve
  the JSON form for when we want `ask` (escalate) instead of a hard block.
- **Plugin packaging:** ship via the plugin's `hooks/hooks.json` (same mechanism already used for the
  PostToolUse/Stop gates). The Wave 0 caveat about "plugin subagents ignore `hooks` frontmatter"
  concerns **agent frontmatter** hooks, not top-level plugin `hooks.json` — our path is unaffected.

### E2 — skill-driven native Plan Mode approval gate → **NO-GO as specified; reframed**

Programmatic plan-mode entry/exit by a skill is **undocumented (UNKNOWN)** — not buildable from
documented primitives. Resolution (no new undocumented dependency):
1. **Keep the existing conversational gate.** `start-task` already emits the plan and stops;
   `implement-approved` is gated on explicit in-conversation approval. That two-skill split *is* the
   approval checkpoint — no native plan mode required.
2. **Offer a deterministic hard gate as the opt-in E1.c toggle** (`gates.lock_edits_in_discovery`,
   default **off**): a PreToolUse deny on app-code `Edit`/`Write` while `task-state.md` mode is
   Discovery/Plan. This is the documented "enforce with a hook" path.
3. **Document** Claude Code's built-in plan mode (`defaultMode: "plan"` / `Shift+Tab`) as a
   user-level recommendation for those who want the native read-only planning UX.

Net: **E2 is dropped as a plugin-driven feature**; its value is delivered by E1.c (opt-in) + docs.

## Residual unknowns — confirm cheaply AT implementation (in-project, `claude --debug`)

- **Exact Edit/Write input key** — docs name `tool_input.command` for Bash and say file tools "include
  `file_path`" but did not quote the Edit input block verbatim. Mitigation: read `.tool_input.file_path`
  with a fallback, and confirm once via `claude --debug`.
- **Exit-2 deny under `auto` permission mode** — docs imply hooks still apply; confirm a host-command
  deny still blocks while the session is in `auto` mode before relying on it.

## Sources

code.claude.com/docs/en/{hooks, sub-agents, skills, permission-modes, interactive-mode, workflows};
llms.txt index. Full quotes in the Wave 0 research transcript.
