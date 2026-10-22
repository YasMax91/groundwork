# Spec: Wave 40 — the gates judge where the work is, not the folder the session was opened in (groundwork v0.50.0)

- Type: gate behaviour change (every hook's directory, the push gate, the Stop gates, the estimate ledger) →
  **L3** (it decides whether anything checks code that reaches a shared branch).
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-21 — the gates are enforcement, not prose, and a gate that skips in silence looks
  the same as one that passed. Found by the otaje session «Проверить две находки в сессии админки otaje».
- Decisions taken with the author on 2026-10-21: the Stop gates remember the repositories a session changed
  from outside its folder and check them (not a warning only); a push whose directory the line does not name
  is refused when it may reach a shared branch, from any session folder, a Groundwork project included.
- Status: **implemented** (2026-10-21).

## What happened (otaje, 2026-10-21)

A session opened in `/Users/kalbasus/Development/Projects/ra-devs-laravel-back` — an empty folder, not a git
repository — worked in the otaje lane `admin-session-findings` and ran
`cd <lane> && git push origin HEAD:development 2>&1 | tail -8`. The change (E8) touched `bootstrap/app.php`,
a shared file that needs the whole suite. `push-gate.py` read the payload's `cwd`, found no repository there
and returned: the push went to `development` with nothing checked. The whole suite (6088 tests) was run by
hand afterwards (`test-run.py --for-push HEAD`, green), before the deploy.

The same session's Stop gates never saw the lane, and `estimate-ledger.sh --record` run in the lane answered
«no transcript events in the task window — nothing recorded»: the transcript is filed under
`~/.claude/projects/-Users-kalbasus-Development-Projects-ra-devs-laravel-back/`, and the ledger looked under
otaje's key only.

## Where the hooks found their project (groundwork 0.49.0)

The root: `hooks/in-cwd.sh:20-29` ran every hook in the payload's `cwd`, the session's folder (wave 36).

- Tool hooks, which have a command or a path: `push-gate.py:64-67` (and `:42`, `HEAD` of the session's
  folder), `lane-guard.py:52-55, 62-63`, `pre-tool-guard.sh:115` (runner lock `:127-160`, shipped-migration
  lock `:171-180`, discovery lock `:184`), `suite-record.py:79`, `format-on-edit.sh:23-36`,
  `stdin-guard.sh:32-34`, `trim-output.sh:19-20`.
- Stop gates, which have neither: `done-gate.sh:16, 43-44`, `test-gate.sh:16, 42-43` (`test-select.py:56`,
  the test-database lock `:157-165`), `openapi-gate.sh:36, 73-79`, `slice-gate.sh:27-30, 44`,
  `handoff-gate.sh:14-15, 60`, `defect-scan.sh:17, 23, 35`; the reply gates `coverage-claim.sh:39`,
  `estimate-claim.sh:41`, `plain-language.sh:71`, `estimate-docs.py:154-160`; the ledger
  `ledger-record.sh:13` → `estimate-ledger.sh:320, 328-331, 129, 160`.
- Other events: `session-start.sh:17`, `pre-compact.sh:9`, `task-intent.sh:24`, `agent-contract.sh:25`,
  `lane-idle.py:60-61`, `statusline.sh:18`, the mod `effort.ts:98-101`.

Two of them were worse than silent. From the main checkout, `cd <lane> && git push origin HEAD:development`
was judged on the main checkout's `HEAD`: a verified tree, so the lane's unverified code passed. And
`cd <lane> && ./vendor/bin/sail artisan test` from the main checkout recorded the main checkout's tree as green.

The incident's transcript (`d875a1e3`, 240 tool calls): every edit in the lane was an Edit / Write by absolute
path (`bootstrap/app.php` four times), every command a `cd <lane> && …`, one a `cd <main> && W=… && git -C $W`.

## Changes

- **`hooks/gw_repo.py`** (new): reads a Bash line into simple commands, each with the directory it runs in —
  `cd` / `pushd` / `popd`, `git -C`, `--git-dir` / `--work-tree` (checked against the repository they sit in),
  `NAME=value` then `$NAME`, `export` (an exported `GIT_DIR` included), subshells, pipelines and `&` (whose `cd`
  moves nothing after them), `bash -c` / `bash -lc` / `bash <<EOF`, `eval`, and the commands inside `$(…)` and
  backticks (`out=$(git push … 2>&1)` pushes). A git that another command runs — `sudo`, `gtimeout`, `stdbuf`,
  `caffeinate`, `script`, `xargs`, `env -C <dir>` — is a git call; `ssh`, `docker`, `kubectl` run theirs
  elsewhere. Read-only substitutions the hook can compute itself are computed: `$(pwd)`, `$(git rev-parse
  --show-toplevel)`, `$(git branch --show-current)`.
  Never a guess: a directory the line does not name (a variable it does not set, any other `$(…)`) is
  unknown. A `cd` that may not happen — after `&&` or `||`, inside an `if`, a loop or a `case`, or into a folder
  that does not exist yet — holds only for the commands `&&` chains after it (`if cd X; then …` included); after
  `;`, or after the `fi` / `done` / `esac`, the folder is unknown: `cd $W || cd $E; git push` pushes from W or
  from E. A function's body runs where the function is called, not where it is defined. Here-document bodies
  are not commands, so a commit message naming `git push origin development` is no longer a push — inside
  `$(…)` too: the commit template `git commit -m "$(cat <<'EOF' … don't … EOF)" && git push …` carries a lone
  quote that, paired up, hid the push behind it in a first version of this parser. `(( 1 << 2 ))` is no
  here-document. It also holds the project root of a path (the nearest `.groundwork.json` up to the repository's
  root), the session registry, and where in-cwd.sh runs a hook.
- **`hooks/session-repos.py`** (new, PreToolUse `Bash|Edit|Write|MultiEdit|NotebookEdit`): remembers, per
  session, every Groundwork repository a call changes outside the session's own folder —
  `~/.claude/groundwork/sessions/<session id>.jsonl` (`GW_SESSIONS_DIR`), one line per repository with the
  session's transcript path; files older than 30 days are dropped. Reading (`git status/log/diff/show/…`,
  `cat`, `grep`, `ls`, `find` without `-delete`/`-exec`, `sed` / `yq` without `-i`, no redirection into a file) is
  not remembered; any other command, and every Edit / Write, is.
- **`hooks/in-cwd.sh`**: a Bash / Edit / Write hook runs in the repository the call works in — the first
  Groundwork project a command that changes something works in, then one that only reads; a `cd` never counts
  (it runs before the move) — else the call's first repository, else the session's folder; the payload is
  passed unchanged. `--each-repo` (done, test, OpenAPI, slice, defect, handoff gates and the ledger) runs the
  hook in the session's folder and, in parallel, in every remembered repository; a verdict from a remembered
  repository is headed `groundwork: in <path> — a repository this session changed from outside its folder:`;
  the exit code is the strictest (2 over 1 over 0). A remembered repository that another live session works in
  now — a `claude` process with it as its folder, or a fresh entry in follow-through's registry — is still
  judged, but its verdict is shown without blocking: those changes may be that session's. `--first-repo`
  (coverage, estimate, estimate-docs and plain-language gates, agent-contract) runs once: in the session's
  project, or — outside one — in the first remembered repository. A hook run for another directory gets it as
  the payload's `cwd`. Every hook now runs at the root of the project the session's folder is in: a session
  opened in a subfolder of a project had every gate look for `.groundwork.json` in the subfolder and stay
  inert. Without python3 or an answer, the hook runs in the payload's `cwd` as before.
- **`hooks/push-gate.py`**: each push (and `gh pr merge`) is judged in its own repository with that
  repository's config; the refspec parser now knows `git push origin HEAD` (the current branch), a bare push
  under `push.default=upstream`, `--all` / `--mirror`, deletions and tags. A branch the line does not name
  (`git push origin "$BR"`) is judged as a shared one. A push whose directory is unknown is refused when its
  branch is shared or unknown, with the request to write the path out. The denial names the repository:
  `cd "<repo>" && python3 …/test-run.py --for-push <ref>`.
- **`hooks/lane-guard.py`**: each runner command is checked in its own worktree; an unknown directory falls
  back to the session's folder, as before.
- **`hooks/suite-record.py`**: a green run is recorded on the tree of the repository it ran in; an unknown
  directory, or a test argument it cannot read, records nothing.
- **`hooks/ledger-record.sh` / `hooks/estimate-ledger.sh`**: the Stop hook passes the stopping session's
  transcript (`GW_SESSION_TRANSCRIPT`); the measurement reads this project's transcript directories, that
  transcript, and the transcripts of every session the registry says worked in the project (any worktree) from
  outside it.

## Acceptance criteria

- **GW40-AC1** A session opened in a folder with no git that runs `cd <lane> && git push origin
  HEAD:development` gets the same denial as a session opened in the lane — also for `git -C <lane> push`,
  `L=<lane>; cd $L && git push`, the incident's own line with `2>&1 | tail -8`, a commit by the template
  before the push, and a push inside `$(…)`.
- **GW40-AC2** From the main checkout, `cd <lane> && git push …` is judged on the lane's code.
- **GW40-AC3** `cd "$LANE" && git push origin HEAD:development` (and a bare `git push` after it) is refused
  from any session folder; `cd "$LANE" && git push -u origin feat/x` is allowed; a repository the line creates
  and pushes (`mkdir … && cd … && git init && git push`) is allowed.
- **GW40-AC4** Nothing the 0.49.0 gate stopped from a project's own folder passes now: `cd A || cd <no repo>;
  git push`, a `cd` inside a function that is never called, `sudo` / `gtimeout` / `xargs` before git,
  `(( 1 << 2 ))` before the push; a branch the line does not name is judged as shared.
- **GW40-AC5** The runner lock, the shipped-migration lock and lane-guard apply to a project reached by `cd`
  or by an absolute path, from an empty folder and from inside another project.
- **GW40-AC6** `cd <lane> && ./vendor/bin/sail artisan test` from the main checkout records the lane's tree,
  not the main checkout's; a run in an unknown directory records nothing.
- **GW40-AC7** The registry holds a repository changed by Edit / Write or by a command; not one only read, not
  the session's own folder, not a folder without `.groundwork.json`.
- **GW40-AC8** At Stop, a failing gate in a remembered repository blocks with that repository named; a session
  that never changed it is unaffected; while another live session works there, the verdict is shown and does
  not block; the reply gates run for a session outside any project.
- **GW40-AC9** The task done from another folder is recorded by that session's Stop, once, and
  `estimate-ledger.sh --record` run in the lane by hand finds the transcript through the registry.

## Verification

- `hooks/tests/command-repo.sh` (new): 85 of 85. Run against the 0.49.0 hooks, 33 of the 85 fail — every case
  this wave fixes; the AC4 cases pass there too (the old gate stopped them, and they guard the new one from
  letting them through), and the parser and registry cases pass only because the new modules were copied in.
- An adversarial review of the first version (61 push forms from a project's folder, 36 from an empty one,
  16 lane-guard and 11 suite-record forms against the 0.49.0 hooks) found the AC4 gaps and the commit-template
  quote; both are closed and pinned in the suite.
- All groundwork suites green, follow-through's included (`bash hooks/tests/all.sh`).
- Cost: `in-cwd.sh` now asks python3 where to run — 81 ms per hook call against 25 ms before, measured on the
  author's Mac over 10 calls; the hooks of one event run in parallel. The live-session check is one `lsof`
  (23 ms) per remembered repository at Stop.

## Not changed

- SessionStart, UserPromptSubmit, PreCompact, SessionEnd (`lane-idle.py`), the status line and the effort mod
  still read the session's folder: they carry neither a command nor a path, and the registry is empty when a
  session starts.
- follow-through, the other plugin in this repository, reads the session's folder the same way
  (`guard.py:154`, `stop_gate.py:303`, `post_tool.py:48`) — its status-file gate and its destructive-command
  prompt do not follow a `cd`.
- A push that runs through a script, a `make` target or an alias is not visible on the line — as before.
- An unknown directory refuses a push to `main` / `master` / `development` in any repository, a Groundwork one
  or not: the author's decision (2026-10-21) — the line has to name the folder.
