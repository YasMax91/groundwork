# Spec: Wave 28 — ready for the public catalog (v0.38.0)

- Type: plugin self-improvement → **L1** (README repair, one manifest field). The submission itself is
  a human step and is not performed here.
- Author: Max Yastremskyi (YasMax91).
- Source: item E34 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27), except the submission. Every claim below was measured against
  the community catalog file rather than taken from the market scan.
- Target version: **v0.38.0**.

## What the catalog actually carries — measured, not assumed

`raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json`,
downloaded and parsed on 2026-08-27: **2282 entries**.

| Question | Measurement |
|---|---|
| Is the slug `groundwork` free? | **No.** Taken by `github.com/etr/groundwork` — an exact `name` match |
| Do entries carry `keywords`? | **0 of 2282.** Search has `name` and `description` and nothing else |
| `icon` / `screenshots`? | **0 of 2282.** Not carried; not added here |
| `category`? | 157 entries have one; `development` is the most common (104), then `productivity` (18), `database` (11) |
| Laravel-facing competition | 7 entries mention Laravel in name or description; none builds spec-before-code with an OpenAPI gate |

## Design

- `category: "development"` on the `groundwork` entry — the one showcase field the catalog carries.
- `README.md:171-174` repaired: four code spans had been lost, leaving "the impact cache under  are
  auto-approved by the plugin's  hook" and "Your own / rules still win over it" — a paragraph about the
  plugin's most surprising behaviour that no longer said anything. Restored from `hooks/pre-tool-guard.sh`'s
  own comments: `.claude/groundwork/`, `PreToolUse`, `Write(path)`, `Write` vs `Edit`, `deny` / `ask`.
- The submission goes under the entry name **`groundwork-laravel`**, since `groundwork` is taken. No
  rename in this repository: `plugin.json` and the author's own marketplace keep `groundwork`, so no
  existing installation breaks.

`claude plugin validate .` passes, **including `--strict`** — checked today. Wave 22's decision to run
CI without `--strict` stands as a deliberate margin: a future showcase field should be a warning in the
log, not a red build.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | No line in the README is left with a collapsed code span | met — `grep -nE "[a-z]  [a-z]"` finds nothing in that section; the paragraph reads |
| AC2 | The marketplace entry carries a category the catalog actually uses | met — `development`, the value on 104 entries |
| AC3 | The manifests validate, plain and strict | met — `✔ Validation passed` both ways |
| AC4 | The naming decision rests on a measurement, not a report | met — exact-name collision confirmed by parsing the catalog file |
| AC5 | Submission completed | **open — human step.** The form is filled in by a person; nothing here submits |

## Open — human steps

1. Submit under `groundwork-laravel` (the form is at the platform's plugin-submission page).
2. Wait for review and the catalog's sync before expecting the entry to appear in `/plugin > Discover`.
3. UNKNOWN, unchanged: whether a plugin shipping 15 shell hooks with a `PreToolUse` deny passes the
   catalog's safety screening. No precedent was found either way.
