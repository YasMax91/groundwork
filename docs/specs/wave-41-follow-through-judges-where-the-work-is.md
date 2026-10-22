# Spec: Wave 41 — follow-through judges where the work is, not the folder the session was opened in (follow-through v0.4.0)

- Type: gate behaviour change (the destructive-command prompt, the lane checks, the status gate, the session
  registry) → **L3** (it decides whether anything checks work a session does in another repository).
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-21 — the gates are enforcement, not prose, and a gate that skips in silence looks
  the same as one that passed. Wave 40 made groundwork's hooks follow the command and left follow-through out
  («Not changed»).
- Decisions taken with the author on 2026-10-22: groundwork's `hooks/gw_repo.py` is copied into follow-through
  byte for byte, and a test fails when the two differ; the status gate checks every repository the turn
  committed, pushed or deployed in, plus the ones the session worked in before from outside its folder
  (follow-through's own list, not groundwork's registry), and blocks there as in the session's own folder —
  also while another live session works in that tree, since the commit is in this session's transcript; a
  session that works in another repository is registered in that repository's registry, and SessionEnd takes
  it out.
- Status: **implemented** (2026-10-22).

## What happened

The project A incident of wave 40: a session opened in an empty folder with no git worked in a lane through
`cd <lane> && …` and Edit / Write by absolute path. follow-through 0.3.1 judged the empty folder. Reproduced
on 2026-10-22 with throwaway repositories: from the empty folder, `cd <lane> && git reset --hard` with an
uncommitted change in the lane passed without a prompt, and `cd <lane> && git commit -am x` without a
status update passed the Stop gate; from the lane itself the first asked and the second was refused.

From a repository's own folder the same hooks judged the wrong tree: a dirty session folder asked about a
clean lane, `cd /other && git commit` demanded the session folder's status, and a session in the main
checkout that updated the lane's `docs/ai/status.md` before committing there was refused (the edit was not the
main checkout's file).

## Where the hooks found their project (follow-through 0.3.1)

- `guard.py:154` `cwd = payload.cwd`; `:155` the config from the session's folder; `:164 → :58 → :66 dirty(cwd)`
  — whether a discarding git command loses changes was asked of the session's folder, and the regex `:28-33`
  did not see `git -C <path> reset --hard`; `:158 → :85 lane_checks`: `:88` nothing outside git, `:90` the
  siblings of the session's repository only, `:95` a file in another repository or worktree had `rel = ""`
  (no overlap check), `:98-99` "same tree" compared with the session's folder, `:113`, `:126-146` the kill
  check against the session's repository only.
- `post_tool.py:48`, `:50` nothing outside git; `:55-63` an edited file recorded only inside the session's tree;
  `:65 → :19-43` a deploy matched against the session folder's status and recorded with its `HEAD` and branch;
  `:66-72` the mirror looked up in the session folder's status.
- `stop_gate.py:358`, `:359-360` the heartbeat in the session's registry; `:363` its config; `:386 → :300
  check_status`: `:303-308` the session folder's status, `:311` any `git commit` of the turn wherever it ran,
  `:313-321` its environments, `:323-328` only its status file counted as updated, `:336-350` its base, mirror
  and pushes; `:384 → :284 check_freshness` the session's registry and tree only.
- `session_start.py:65`, `prompt_submit.py:23`, `session_end.py:14`, `ft.py:54-59`, `:81` — the session's folder.

## Changes

- **`follow-through/hooks/gw_repo.py`** (new): groundwork's module, byte for byte. follow-through calls its
  parser only — `commands`, `writes`, `command_top`, `toplevel` — and none of groundwork's registry or rules; a
  plugin cannot import another plugin's files once installed, so the copy ships with it.
- **`lanes.py`**: `call_parts` — every part of a Bash / Edit / Write call with the working tree it works in
  (None when the line does not say), whether it may change anything, and the parsed command; a `cd` is left
  out. `entry_for` — the registry entry a session keeps for a tree: its own entry in the repository of its
  folder, else an entry in that repository's registry with `cwd` = the tree it works in, `opened_in` = its
  folder and the task its first prompt, remembered in `~/.claude/follow-through/outside/<session>.jsonl`.
  `deploy_targets` — the repositories a Bash line deploys, by their statuses' `deploy_cmd`, shared by the
  PostToolUse record and the Stop gate. `siblings` no longer creates the registry directory of a repository it
  only reads.
- **`guard.py`**: a git command that discards changes is judged in the tree it runs in — `cd`, `pushd`,
  `git -C`, `--git-dir`/`--work-tree`, `NAME=…; cd $NAME`, subshells, `bash -c`, and the forms the old regex
  missed (`git -C <lane> reset --hard`, `git reset -q --hard`, `git checkout -q HEAD -- f`); a git another
  command runs (`find -exec`, `ssh`) is judged where that command runs. A folder the line does not name asks:
  the line has to name it. What the line shows only as text (a here-document) is judged as before. Each tree
  answers to its own `gates.destructive`: the session folder's switch holds for its own tree and for a line
  that names none, another tree's for that tree — off there is off from outside too, and off in the session's
  folder does not switch another tree's check off. The other checks of a line (`migrate:fresh`, volumes,
  `pkill`) hold by the switch of the tree the matching command runs in, and a write to a gate config by the
  switch of the tree the file is in (a hook inside `.git` included): `echo '{}' >
  <lane>/.claude/follow-through.json` asks by the lane's switch, not by the one of the folder it was typed in.
  An edit meets the session's own tree first, as in wave 35 — a live sibling in this same folder, on the first
  edit wherever the file is — and, when the file is in another tree, that tree's live sessions and the files
  they edited, each once, with a hint that fits a tree of another repository. The kill check reads the
  registries of the session's repository, of the trees the line works in, and of the ones the session worked
  in before.
- **`post_tool.py`**: an edited file is recorded in the registry of the repository it is in; a command that
  changes something in another repository registers the session there — a read before it on the same line
  does not hide it; reading alone does not register. A deploy is recorded where `lanes.deploy_targets` puts it
  (below), with the `HEAD` and branch of that repository's tree; the mirror publish is recorded for the
  repository whose mirror it is.
- **`stop_gate.py`**: `check_status` — wherever the turn worked, each tree by its own switch:
  - a commit or cherry-pick needs the status of the tree it was made in — not another worktree's (0.3.1 read
    any `docs/ai/status.md` write as an update); a command whose folder the line does not name, and what the
    line shows only as text, count in the session's own tree, as before;
  - each command is read from the folder its call was made in (the transcript's `cwd`), so a `cd` the shell
    kept from an earlier call is followed;
  - a status write is read from the command's own words, so a `|` inside a quoted `sed` script
    (`s/| doing |/| done |/`) is no pipe;
  - a deploy (`lanes.deploy_targets`): the session's own repository reads the whole line against its
    `deploy_cmd`, as before. Another repository — one the turn worked in, or one the session worked in before
    from outside its folder — counts a command its pattern names when the command deploys from it (its script,
    or a local tool such as `make` or `rsync` run in it), or deploys from no tree here (`ssh`, `curl`, `gh` …,
    or a folder outside git) and the session's own pattern does not name it; a script of a third repository
    that happens to match is never another's deploy. A deploy needs the status of that repository's tree: the
    session's own, else the one the turn worked in last, else the one the session last worked in there;
  - the mirror answers to the tree the last push was made from;
  - a verdict about another tree starts with `In <path> — a tree this session works in outside its folder:`.

  `check_freshness` also judges the lanes of other repositories the session changed files in, each by its own
  switch.
- **`session_end.py`**: takes the session out of the registries of the repositories it worked in from outside.
- **`ft.py`**: `first_prompt` — the task a registry entry carries; `current_turn` keeps each call's `cwd`.

## Acceptance criteria

- **FT41-AC1** From an empty folder, `cd <lane> && git reset --hard` asks when the lane has uncommitted changes,
  as it does in the lane — also for `git -C <lane> checkout -- .`, `bash -lc 'cd <lane> && git stash drop'`,
  `L=<lane>; cd $L && git clean -fd`, `git restore` in a pipeline and `git reset -q --hard`; `git restore
  --staged` passes. A clean lane from a dirty main checkout passes; a dirty lane from a clean one asks. `cd
  "$LANE" && git reset --hard` asks. The lane's own `gates.destructive: false` holds from outside it; the same
  switch in the session's folder does not silence the lane's check, nor `migrate:fresh` run in the lane, nor a
  write into the lane's gate config; `migrate:fresh` in the session's own tree holds by its own switch even when
  the line also reads the lane.
- **FT41-AC2** From an empty folder, `cd <lane> && git commit` without the lane's status updated gets the
  refusal a session in the lane gets, naming the lane — also `git -C <lane> commit`, `L=…; cd $L && git
  cherry-pick`, the commit template's here-document, and a `cd` kept from an earlier call. So does a session in
  the main checkout, which has no status of its own. An Edit of the lane's status, or a `sed -i` of it, passes;
  an edit of another worktree's status does not. A commit in another repository no longer asks for the
  session folder's status; a commit in a folder the line does not name still does. A session in the main
  checkout that updated the lane's status passes. A push from outside asks for the lane's mirror. An `ssh …
  deploy.sh staging` after earlier work in the lane asks for the lane's status; with no such work it names no
  repository; a deploy run in the session's own tree is its own, even when a lane it worked in has the same
  `deploy_cmd`; the session's own `deploy_cmd` reads the whole line (`make build && rsync`) as before, also
  when a lane's pattern names one of its commands, and asks for the session's status wherever the deploy runs;
  a script of the session's own tree is never a remembered repository's deploy. The session folder's
  `gates.status: false` does not silence the lane's check.
- **FT41-AC3** An edit from outside meets the lane's session — the same tree first, then the same file — and
  is recorded in the lane's registry (`cwd` the lane, `opened_in` the folder, the file); the lane's session sees
  it, named with that folder; a command that changes the lane registers the session, also after a read on the
  same line, and reading alone does not; SessionEnd takes it out; a deploy from the lane is recorded with the
  lane's `HEAD`, and one run in the session's own tree is not recorded in the lane; "done" while the base moved
  under the lane's files is refused.
- **FT41-AC4** `follow-through/hooks/gw_repo.py` equals `hooks/gw_repo.py`.
- **FT41-AC5** An edit outside git in a folder another live session shares is met once, as in wave 35.

## Verification

- `follow-through/hooks/tests/test_command_repo.py` (new): 36 of 36. Against the 0.3.1 hooks 22 of the 36 fail;
  the other 14 hold what 0.3.1 already did in the session's own folder (`git restore --staged`, a commit in a
  folder the line does not name, an edit of another worktree's status, the own deploy pattern over the whole
  line, a shared folder met on an edit outside git) or are true there by accident (an empty folder has no
  status), and guard the new code from over-asking.
- follow-through 105 of 105; every groundwork suite green (`bash hooks/tests/all.sh`).
- Two adversarial reviews ran 0.3.1 and the new hooks on the same inputs. The first, of the first version (41
  commit forms, 37 discard forms in three placements, 33 everyday commands, every hook on malformed input),
  found six defects: a changing command not registered after a read on the same line (`cd <lane> && git status
  && git commit`); a status edit in another worktree counted for this one; no refusal for a commit in a sibling
  worktree when the session's own tree had no status file; the session folder's switch silencing another
  tree's check; a deploy run in the session's own tree also charged — and recorded — to a lane with the same
  `deploy_cmd`; the same-tree check skipped for an edit outside the tree. The second, of the fixes (67 deploy,
  push, worktree, transcript-`cwd` and switch cases), found three more: the session's own pattern over several
  commands (`make build && rsync`) lost once a remembered repository's pattern matched one of them; a local
  script of the session's own tree charged to a remembered repository; the switches read for the whole line —
  `migrate:fresh` in the own tree asked by the switch of a tree the line only read — and a gate-config write
  judged by the folder it was typed in, not the file's. All nine are fixed and pinned above; the scripts of
  both reviews, re-run, find no input 0.3.1 asked or refused on that the new hooks let pass, apart from the
  changes this wave makes on purpose: a tree whose own switch is off is off from outside too; a commit in
  another repository no longer asks for the session folder's status; a discard in a clean lane is not asked
  about because the session's folder is dirty; a `git commit` whose folder is outside git is not one.
- Ten mutations — each fix undone in a copy of the hooks — each fail at least one case.
- Cost, measured on the author's Mac: `guard.py` and `post_tool.py` per call 78–96 ms against 88–96 ms on 0.3.1
  (Python's start-up; a line without `git` is not parsed for the discard check), the Stop gate on a 400-call
  turn 209 ms against 220 ms.

## Not changed

- SessionStart and UserPromptSubmit read the session's folder: they carry neither a command nor a path. The
  awareness block lists the siblings of the session's own repository; a session working in a lane from outside
  meets that lane's sessions through the edit checks.
- The language check reads the `CLAUDE.md` of the session's folder — it is about the chat, not the work.
- The status gate needs a repository: a `docs/ai/status.md` in a folder outside git is no longer read (0.3.1 read
  it, and a `git commit` there fails anyway).
- A commit, push or deploy that runs through a script, a `make` target or an alias is not visible on the line;
  a status update by `perl -pi` or a Python here-document is not recognised; `git merge`, `rebase`, `am` and
  `gh pr merge` are no commits; a line that only mentions `git commit` (`echo`, `git log --grep`) still counts
  as one; one «статус не меняется: …» line answers for every tree of the turn — as before.
- The parser's limits are groundwork's: a folder handed in through `{}` (`xargs -I{} git -C {}`, `find -exec
  git -C {}`) is not followed, and a git that `ssh` or `docker exec` runs is elsewhere.
- A command the parser does not know as a reader registers the session in that tree (`npm test`, `git diff >
  /tmp/x.patch`); a session that only reads a tree for 30 minutes drops out of its siblings' list.
- groundwork's `lane-idle.py` stops a lane's stack when the last session in its tree closes; a session that
  worked in the lane from outside now counts as one there while it is live, and at its own end nothing stops
  the stack (its SessionEnd runs in its own folder).
