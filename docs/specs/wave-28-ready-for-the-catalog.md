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

## Open — the one step an agent cannot take

Both submission forms were opened and checked on 2026-08-27:

- **claude.ai** (`/admin-settings/directory/submissions/plugins/new`) answers "You don't have access to
  organization settings — available on Claude Team and Enterprise plans". Closed for an individual author.
- **Console** (`platform.claude.com/plugins/submit`) shows a sign-in screen. Authenticating is not
  something an agent does on someone's behalf, so the form is the author's step, by design and not by
  omission.

Everything the form asks for is settled, so submitting is copy-and-paste:

| Field | Value |
|---|---|
| Repository | `https://github.com/YasMax91/groundwork` |
| Commit at submission | `5c77619` on `main` (approved plugins are pinned to a SHA; CI bumps the pin on later pushes) |
| Manifest name | `groundwork` — the catalog entry goes in as **`groundwork-laravel`**, because an exact-name entry `groundwork` already exists (`github.com/etr/groundwork`), verified against the 2282-entry catalog file |
| Description | `Spec-driven workflow for Laravel backends: grounded discovery and specs before code, an anti-hallucination protocol for external integrations, and hooks that hold the runner, formatting, static analysis, tests and the OpenAPI document.` |
| Category | `development` |
| License / homepage | MIT / the repository |
| Local validation | `claude plugin validate .` → `✔ Validation passed`, `--strict` included |
| CI | `hooks` workflow green on `ubuntu-latest` and `macos-latest`, 313 cases each |

After approval: the catalog syncs nightly, so an entry does not appear in `/plugin > Discover`
immediately. UNKNOWN, unchanged: whether a plugin shipping 15 shell hooks with a `PreToolUse` deny
passes the automated safety screening. No precedent was found either way.
