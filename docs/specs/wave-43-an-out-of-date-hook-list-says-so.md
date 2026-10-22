# Spec: Wave 43 — a session running an out-of-date hook list says so (groundwork v0.52.0, follow-through v0.5.0)

- Type: hook behaviour change (UserPromptSubmit in both plugins, a token in both `hooks.json`) → **L2** (it decides
  whether the owner learns that a session's gates no longer run as released).
- Author: Max Yastremskyi (YasMax91).
- Source: project A, 2026-10-22 — a session opened on 2026-10-21 pushed to `development` and `staging` between 11:42
  and 12:00, after the 0.50.0 release (11:07), with the 0.49.1 hook list: since Claude Code 2.1.304 a `yasmax`
  plugin loads in place from the groundwork checkout, every hook script is read from disk at each call, and
  `hooks/hooks.json` only when a session starts or on `/reload-plugins`. After 0.50.0 (`session-repos.py` added, the
  Stop gates given `--each-repo` / `--first-repo`) every session opened before it ran the new scripts with the old
  list — no `session-repos.py`, Stop gates without their flags — and nothing said so; it came out only when another
  session went looking for which version runs where. The owner wants groundwork's gates to hold in every session.
- The task as given: remember the hash of `hooks.json` at SessionStart, compare it at a cheap point, warn once; find
  out whether `/reload-plugins` fires SessionStart, and if not, how to reset the remembered hash. The probes below
  answered no — and showed `/clear` and `/compact` firing SessionStart on the list already loaded — so nothing is
  remembered at SessionStart: the list names itself (see «Design»).
- Status: **implemented** (2026-10-22), not released.

## What the probes found (2026-10-22)

An isolated `CLAUDE_CONFIG_DIR` in a scratch folder, a `directory` marketplace with one relative-path plugin (loaded
in place, as `yasmax` is) whose hooks append the event, its `source` and the label of the `hooks.json` version
(A, then B) to a file, and the Messages API pointed at a local stub, so turns finish and nothing leaves the machine.

- **Stream-json, as the desktop app drives a session** (2.1.304, the desktop app's copy; 2.1.308 from Homebrew):
  «hello one» ran list A; `hooks.json` rewritten to B; «hello two» ran **A** again; `/reload-plugins`
  answered `Reloaded: 1 plugin · … · 5 hooks …` and `` `probe@probe-mkt` re-read from its folder ``, and **no hook
  fired** — no SessionStart, nothing; «hello three» and a Bash call ran B; SessionEnd ran B.
- **The terminal UI** (2.1.308, a pty): `/clear` fired SessionEnd and then SessionStart `source: "clear"` under a new
  session id — on list **A**; `/compact` fired SessionStart `source: "compact"` on A; the next prompts ran A;
  `/reload-plugins` fired nothing, and the prompt after it ran B.
- A UserPromptSubmit hook's `systemMessage` reaches the SDK stream as `{"type":"system","subtype":"informational",
  "content":"UserPromptSubmit says: …","level":"notice"}`, and its `additionalContext` reached the model's request.
- Documentation agrees: a relative-path plugin of a marketplace added from a local path «loads in place … Your edits
  to the source directory take effect at the next session start or `/reload-plugins`»
  (code.claude.com/docs/en/plugins/loading); a hooks module (`"modules"` in `hooks.json`, groundwork's `effort.ts`)
  is registered «once when the mod loads», and an updated one needs `/reload-plugins`
  (code.claude.com/docs/en/plugins/mods/overview).

So a hash remembered at SessionStart is wrong both ways: `/reload-plugins` loads the new list without any hook to
reset it — the session would be told to reload forever — and `/clear` and `/compact` start a SessionStart on the old
list, so a hash taken there would bless it. A session opened before the release has no hash at all.

## Design — the list names itself

One command in each `hooks.json` — the UserPromptSubmit one — carries `--registration <id>`: the first 12 hex digits
of sha256 over the file's content and the hooks modules it names. The command line a hook runs with is the list the
session loaded; the file on disk is the list now. Comparing the two needs nothing remembered and nothing reset:

- after `/reload-plugins` the command carries the id on disk — silent;
- `/clear`, `/compact`, `/resume` in the same process keep the command they had — still told, if out of date;
- a session opened before this release runs a command with no `--registration` at all — told at its next prompt,
  through the same scripts, since `in-cwd.sh` and `prompt_submit.py` are read from disk at each call.

### The id

`gw_registration.ident(hooks.json)`: sha256 over the file parsed as JSON, every `--registration <id>` in it blanked to
`--registration`, dumped with sorted keys and no whitespace; then, for each name under `"modules"`, the name and the
bytes of that file next to `hooks.json`. Whitespace and key order do not change the id; an event, a matcher, a
command, a flag, a status message, a hook added or removed, or a module's code do. `gw_registration.py stamp
<hooks.json>` writes the id into the file; a test fails while the declared id is not the content's, so a release
that changes the list cannot ship the old id.

### The check

- **groundwork** — `in-cwd.sh` takes `--registration <id>` before the hook's name. For `task-intent.sh` (its only
  UserPromptSubmit hook), in a hook process the harness started (`CLAUDE_PLUGIN_ROOT` set), it reads the id
  `hooks.json` on disk carries with bash alone (`$(<file)`, no program started) and compares it with its own.
  Equal (every prompt of a session that is current): the hook runs exactly as before. Different: if the session's marker
  `<sessions>/<session id>.registration` (`GW_SESSIONS_DIR`, default `~/.claude/groundwork/sessions`) already holds
  the id on disk, the hook runs as before; otherwise the hook's output goes through `gw_registration.py warn`, which
  writes the marker and merges the notice in.
- **follow-through** — `prompt_submit.py` takes the same argument and does the same in its own process, with its
  marker under `~/.claude/follow-through/registration/`. The check runs in every session, a folder outside git
  included, before the lane logic that returns early there; the lane's «what changed around you» block is kept.
- The marker holds the id on disk the session was told about: one notice per session and change. Another release
  while the session is still out of date tells it again; `/clear` starts a new session id, told again once. Markers a
  month old are dropped when a new one is written.

### The notice

- For the user, `systemMessage`: `groundwork's hooks changed after this session loaded them, so some of its checks
  may not run as released. Run /reload-plugins in this session, or reopen it.` (follow-through: the same, with its
  own name.)
- For the agent, `additionalContext`, before the hook's own context: the list is out of date — the ids loaded and on
  disk («none» for a list from before this release); what that means (the scripts run from disk with the old list: a
  hook added since does not run, a changed one runs with its old arguments — checks before a command runs and at the
  end of a turn among them); and to tell the user in one line, before anything else, to run `/reload-plugins` or
  reopen the session.
- The hook's own `hookSpecificOutput`, `systemMessage` and any decision are kept; a hook that exited non-zero is left
  alone (no notice, its exit code and output untouched).

### Fail-open

Nothing here blocks a prompt or changes a hook's exit code. No `CLAUDE_PLUGIN_ROOT` (a test or a hand run), no
`hooks.json` or no id in it, no session id, no `python3`, a broken payload, any error in `warn`: the hook's output
passes as it was. A marker folder that cannot be written still lets the notice through — on every prompt, since
nothing can remember it was given; groundwork's folder is the one its other session files live in. A hook list from
before `in-cwd.sh` (groundwork before 0.46.0) calls `task-intent.sh` directly and is not checked.

## Changes

- **`hooks/gw_registration.py`** (new): `ident`, `declared`, `stamp`, `loaded` (the id in an argv), `checked` (the
  hook's output with the notice merged in, when due) and the CLI `ident | check | stamp | warn`.
- **`hooks/in-cwd.sh`**: arguments parsed in a loop (`--registration <id>`, `--each-repo`, `--first-repo`); the check
  for `task-intent.sh`; `run_checked` around the single-directory runs.
- **`hooks/hooks.json`**: the UserPromptSubmit command `in-cwd.sh --registration <id> task-intent.sh`.
- **`follow-through/hooks/gw_registration.py`**: groundwork's module, byte for byte (a test compares them, as for
  `gw_repo.py`).
- **`follow-through/hooks/prompt_submit.py`**: the check, then the lane logic; one output.
- **`follow-through/hooks/hooks.json`**: `prompt_submit.py --registration <id>`.
- **Tests**: `hooks/tests/registration.sh` (in `all.sh`), `follow-through/hooks/tests/test_registration.py`.
- **Versions**: groundwork 0.52.0, follow-through 0.5.0. README of each: the paragraph on an out-of-date list.

## Acceptance criteria

- **GW43-AC1** A session whose command carries the id on disk gets exactly what it got before: `task-intent.sh`'s and
  `prompt_submit.py`'s output and exit code unchanged, no marker written.
- **GW43-AC2** When the id on disk differs from the command's — or the command carries none — the next prompt gets
  the notice: a `systemMessage` for the user and, before the hook's own context, a paragraph for the agent naming both
  ids and `/reload-plugins`; in a groundwork project and outside one, in a git repository and outside one.
- **GW43-AC3** Once per session and id on disk: the same session's next prompts are silent; another change on disk
  tells it again; a command carrying the new id (after `/reload-plugins`) is silent; another session id is told
  once.
- **GW43-AC4** The hook's own output survives the merge: `task-intent.sh`'s reminder and follow-through's «what
  changed around you» follow the notice in one `additionalContext`; a hook that fails keeps its exit code and output.
- **GW43-AC5** Fail-open: no `CLAUDE_PLUGIN_ROOT`, no `hooks.json`, no id on disk, no session id, a broken payload,
  no `python3` — the hook runs as before; an unwritable marker folder — the notice still comes; the prompt is never
  blocked.
- **GW43-AC6** The common path costs groundwork no program: a current session's prompt adds the bash read of
  `hooks.json` only (measured below); a session already told adds one marker read.
- **GW43-AC7** Each `hooks.json` declares the id of its content in exactly one command, its UserPromptSubmit one; a
  change to the file or to a module it names without a new id fails the suites; `stamp` writes it; whitespace and
  key order leave it as it is.
- **GW43-AC8** follow-through's `gw_registration.py` is groundwork's byte for byte.

## Verification

- `hooks/tests/registration.sh`: 70 of 70 — the id (whitespace, key order and its own value leave it, a flag, a
  matcher, a status message, an event, a hook, a module's bytes change it; `check` and `stamp`), a current list, an
  out-of-date one told once per session and change, the hook's own answer kept, fail-open, and the programs a prompt
  starts (a shim counts `python3`, `jq` and the hashing tools: a current list, a list already told and another hook
  on an old list start none more than no check; the first notice starts `python3` once).
- `follow-through/hooks/tests/test_registration.py`: 12 of 12 — the copy byte for byte, the declared id, the check
  in a folder outside git and in a lane with news from a sibling (the notice first, the news kept).
- All suites green (`bash hooks/tests/all.sh`): every groundwork suite, follow-through 132 of 132.
- 27 mutations, each applied to both copies of the module where it touches it, so the byte-for-byte test is not
  what catches it: never or always out of date, the bash marker shortcut dropped or reading the wrong file, the
  marker ignored or not keyed by the id on disk, either `CLAUDE_PLUGIN_ROOT` gate dropped, the hook's context dropped
  or put after the notice, a failed hook merged, the modules or the blanking left out of the id, raw bytes hashed,
  `check` taking the first id only, follow-through checking only in a lane or dropping the lane's news, the argv id
  ignored, `--registration`'s value not consumed, every hook checked, a marker written for a current list, the
  cleanup dropping other sessions' markers or keeping month-old ones, any event or any session id accepted, no
  fallback to the hook's own output, a list with no id taken for current — each fails at least one test. The first
  run left two alive: «every hook checked» (python's event check hid it; the cost test now runs another hook) and
  «any session id» (a marker an earlier mutation had written outside the test's folder hid it; the case now writes
  inside it and checks nothing was written).
- Linux, in an Ubuntu 24.04 image with the CI's tools (bash 5.2, GNU sed, jq 1.7, Python 3.12): `registration.sh`
  70 of 70, `in-cwd.sh` and `task-intent.sh` green, follow-through's `test_registration.py` and `test_lanes.py` green.
- An adversarial review on a copy of the tree, on macOS (`/bin/bash` 3.2, Python 3.9) and in the Linux image: every
  suite green; no silent miss — a plugin path with spaces, `"session_id" : "…"` spacing and line breaks in the
  payload, a prompt with Cyrillic, emoji and an escaped `\"session_id\":\"fake\"` before the real id (the marker took
  the real one), `hooks.json` with CRLF, no `jq`, an upper-case session id, no `cwd`, the command run through
  `sh -c`, the list from before (no id); no false alarm or repeat — a current id with CRLF, the same session's next
  prompts, after a reload; nothing broken — `--each-repo` / `--first-repo` as before (their several-directory runs
  still call `run`), a failing hook's code and output kept, `prompt_submit.py` answering as before on equal input, no
  `decision` or `continue` added, the line the agent is asked to say passing follow-through's hand-back pattern and
  `plain-language.sh`; no program added on the current path; a module, a `timeout` or a matcher changed without a
  new id, the copies one byte apart, the id moved to another command — each fails a suite. Its two remarks are under
  «Not changed» (the local barrier) and «Fail-open» (an unwritable marker folder).
- `claude plugin validate .` and `./follow-through`: passed (the missing-icon warning predates this).
- Cost, measured on the author's Mac (median of 40 prompts through `in-cwd.sh task-intent.sh` outside a project):
  65.5 ms with no check, 66.2 ms for a current list, 66.5 ms for a list already told; the first notice 93.6 ms (one
  `python3`).
- In the sandbox, with both real plugins loaded in place from a copy of this tree (2.1.304, the desktop app's copy;
  2.1.308 from Homebrew; stream-json):
  - **a release under an open session** — the session starts on 0.51.0's tree, the files are then replaced by this
    one: the next prompt shows both notices (groundwork's and follow-through's) and the model's request carries each
    once; the prompt after it shows none and the request still carries each once (the history); `/reload-plugins`
    (`Reloaded: 2 plugins · 18 skills · 10 agents · 31 hooks …`) and the prompt after it: none;
  - **a later change** — the session starts on this tree, groundwork's `hooks.json` then changes and is stamped: one
    notice, groundwork's only; then none; after `/reload-plugins` none.
  - The terminal UI (2.1.308, a pty), both scenarios: the notice is drawn under the prompt it came with —
    `UserPromptSubmit says: groundwork's hooks changed after this session loaded them, so some of its checks may not
    run as released. Run /reload-plugins in this session, or reopen it.` — and the session's transcript records each
    notice once, under that prompt; the model's request carries it once; nothing more after the next prompt,
    `/reload-plugins` or the prompt after it.

## Rollout

This release changes both lists (each gains its id), so every session open when `main` moves gets both notices at
its next prompt — rightly: its commands carry no id. One `/reload-plugins` per session (typed into the session's own
prompt box; sent over Remote Control it «reloads nothing» — code.claude.com/docs/en/plugins/cli-reference,
«Sessions without an interactive terminal» — so reopen such a session instead) and the notices stop. From then on a
release that changes `hooks/hooks.json`, `effort.ts` or `follow-through/hooks/hooks.json` re-stamps the file it
changed (`python3 hooks/gw_registration.py stamp <hooks.json>`), and only the plugin whose list changed speaks.

## Not changed

- Skills and agents are also read at a session's start and on `/reload-plugins`; a session keeps their old text. The
  id covers the hook list and its modules only — the part that enforces.
- The check runs on a prompt. A session that works for hours on one prompt (or on messages that do not go through
  UserPromptSubmit) is told at its next prompt, not before.
- A copied plugin (a git-hosted marketplace) carries its `hooks.json` and its scripts in one versioned folder: the
  ids always match there, and an update the session did not reload is not this check's to report.
- The check trusts the id `hooks.json` declares. A change committed without `stamp` fails the suites, but nothing
  runs them before a commit lands on `main` — the local git hooks run the names guard only, CI runs after the push —
  and `main` is the live plugin: until the id is fixed, sessions opened before such a change are not told, and those
  opened after it are told once when it is. A local pre-commit check would close it; the git hooks are the author's
  own, outside this repository.
