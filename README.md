# groundwork

RaDevs' Claude Code plugin for Laravel backends. One central, versioned source for how we work, so
projects stay thin and consistent instead of copy-pasting `AGENTS.md` / `CLAUDE.md` / skills between
repositories.

## What's inside

- **Process (AI-SDD)** — skills: `start-task`, `spec`, `implement-approved`, `risk-review`,
  `final-check`, `init`.
- **Grounding** — `grounding-protocol` + the `ground-integration` skill + the `grounded-researcher`
  and `adversarial-verifier` agents. Read reality, never guess.
- **Standards + gates** — `laravel-standards` + hooks: Pint on edit, static analysis as a done-gate.
- **Templates** — thin project `AGENTS.md` / `CLAUDE.md` / `.groundwork.json` and six spec templates.

## Grounding split

- **Boost → the framework**: version-aware Laravel docs, DB schema, models, logs (a per-project
  `laravel/boost` composer dependency).
- **This plugin's protocol → external APIs** (payments, booking, messaging): capability matrix +
  cited source + sandbox proof. This is the part Boost does not cover.

## Install (in a project)

```
/plugin marketplace add <git-url-of-this-repo>
/plugin install groundwork@yasmax
/groundwork:init
```

`init` generates thin, domain-only contracts by grounded discovery (deriving facts from the code,
Boost, and docs, labelling anything assumed), installs Boost, and drops `.groundwork.json`.

## Update everywhere

```
/plugin marketplace update
```

Versioned with semver in `.claude-plugin/plugin.json` — projects update when you bump it.

## Develop locally

```
claude --plugin-dir /path/to/groundwork
```

Then `/reload-plugins` after changes. Test skills with `/groundwork:<skill>`, check the
agents in `/agents`, and confirm the hooks fire on edits.

## Per-project configuration — `.groundwork.json`

Overrides the gate commands (`format`, `analyse`, `test`) and toggles (`format_on_edit`,
`analyse_on_stop`). Defaults to Sail.

## Layout

```
.claude-plugin/   plugin.json · marketplace.json
skills/           start-task · spec · implement-approved · risk-review · final-check · ground-integration · init
agents/           grounded-researcher · adversarial-verifier
hooks/            hooks.json · format-on-edit.sh · done-gate.sh
guidelines/       ai-sdd-process · grounding-protocol · laravel-standards
templates/        project/ · specs/
```
