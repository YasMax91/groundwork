# Skill hygiene — the author's checklist for this plugin

Development-time discipline for whoever edits this plugin. It never ships into a project's context —
unlike everything under `guidelines/`, this file exists for the person writing the skills.

A skill buys **predictability**: the agent taking the same *process* every run. Every rule below serves
that, and every line that does not is costing tokens for nothing.

## The two budgets

- **Context load** — a model-invoked skill's `description` sits in the window every turn, in every
  session, forever. That is the expensive real estate; prune it hardest.
- **Cognitive load** — a user-invoked skill (`disable-model-invocation: true`) costs zero context, but
  *you* become the index that must remember it exists.

Make a skill model-invoked only when the agent, or another skill, must reach it unprompted. `grill` is
user-invoked because it only ever fires by hand; `start-task` is model-invoked because the workflow
depends on it firing on its own.

Guidelines under `guidelines/` are cheaper than either: they load only when a skill points at them. When
material grows past a paragraph, it belongs in a guideline with a pointer, not inline in a skill.

## Where a piece of text belongs

1. **A step in `SKILL.md`** — an ordered action, ending on a **checkable completion criterion**. "Every
   modified model accounted for" is checkable; "produce a change list" invites stopping early.
2. **Reference in `SKILL.md`** — a rule or definition consulted on demand. A flat peer-set of rules is
   a legitimate shape, not a smell.
3. **A separate file behind a pointer** — reference only some runs need. The pointer's *wording*, not
   its target, decides whether the agent actually follows it.

Keep a concept's definition, rules, and caveats under one heading. Scattering them means a later edit
updates one copy and leaves the others lying.

## Single source of truth

One meaning, one authoritative place, so changing the behaviour is a one-place edit. When two files
must both mention something, one owns it and the other points — the skill owns its steps, the guideline
owns its protocol.

## Failure modes to hunt

- **Duplication** — the same meaning in two places. Costs maintenance, tokens, and inflates the
  meaning's apparent rank. The one that drifts is always the copy nobody remembered.
- **Sediment** — stale layers that settle because adding feels safe and removing feels risky. The
  default fate of any file without a pruning pass.
- **Sprawl** — too long even when every line is live. Cure with pointers and splits, not with courage.
- **No-op** — a line the model already obeys by default. The test: *does this change behaviour versus
  the default?* Run it on each sentence in isolation; when one fails, delete the whole sentence rather
  than trimming words from it.
- **Prohibition instead of target** — "don't guess" names guessing; "read the schema, then answer"
  names the behaviour you want. Keep a bare prohibition only as a hard guardrail, and pair it with what
  to do instead.
- **Premature completion** — a step ends before it is genuinely done. Sharpen the completion criterion
  first; only split the sequence if the rush survives a sharp criterion.

## Name a capability, not a tool you did not verify

Text that prescribes a tool the executor does not have is worse than silence: the agent spends a turn
discovering the gap. Three verified traps in this plugin's own history — a subagent's `tools`
allowlist drops every MCP server it does not name (so `impact-mapper` needs `mcp__laravel-boost`
spelled out); the `LSP` tool exists only in the main session, never in a background subagent; and
`Grep`/`Glob` are absent in some builds, where search is `rg`/`find` through `Bash`. Write the
capability with its fallback — "whichever search you have" — and check the executor's real tool list
before making a single tool the instruction.

## Before committing a change to this plugin

- Does every new sentence survive the no-op test?
- Does every tool it names exist for whoever executes that line?
- Is each new meaning in exactly one file?
- Did a skill grow past ~6 KB, or a description past two lines?
- Does a new prohibition have a positive form?
- Does the version in `.claude-plugin/plugin.json` match what the README and the roadmap describe?
