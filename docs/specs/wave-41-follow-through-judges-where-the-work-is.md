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
  a status update by `perl -pi` or a Python here-document is not recognised (it is since 0.4.2, below); `git
  merge`, `rebase`, `am` and `gh pr merge` are no commits; a line that only mentions `git commit` (`echo`, `git
  log --grep`) still counts as one; one «статус не меняется: …» line answers for every tree of the turn — as
  before.
- The parser's limits are groundwork's: a folder handed in through `{}` (`xargs -I{} git -C {}`, `find -exec
  git -C {}`) is not followed, and a git that `ssh` or `docker exec` runs is elsewhere.
- A command the parser does not know as a reader registers the session in that tree (`npm test`, `git diff >
  /tmp/x.patch`); a session that only reads a tree for 30 minutes drops out of its siblings' list.
- groundwork's `lane-idle.py` stops a lane's stack when the last session in its tree closes; a session that
  worked in the lane from outside now counts as one there while it is live, and at its own end nothing stops
  the stack (its SessionEnd runs in its own folder). Changed in groundwork v0.51.0:
  `wave-42-lane-idle-follows-the-work.md`.

## 0.4.2 (2026-10-22) — a status moved by perl or a Python script counts; a gate config behind a quoted `|` asks

- Source: the «Not changed» line above, and `guard.py` still finding a gate-config write with `lanes.shell_writes`,
  which cuts the line on every `|`, so `sed -i 's/a|b/c/' .groundwork.json` was never asked about.
- What the log shows. The two `status_event` refusals of 2026-10-14 in `triggers.log` (project A, the excerpt
  starting `perl -0pi -e 's{- Mode: Releasing`) were not perl's: that perl rewrote `.claude/groundwork/task-state.md`
  on the commit's line, and the status had been moved earlier in the turn by `sed -i '' 's/… | blocked/…/'
  docs/ai/status.md`, which the line reading of that time cut on its `|`. Replayed, both turns pass since 0.4.0.
  The perl and Python forms are real all the same: between 2026-10-05 and 10-16 project A's sessions moved the
  status 30 times by a Python script on the line (`p = 'docs/ai/status.md'` … `open(p, 'w')`,
  `pathlib.Path(…).write_text`) and 5 times by `perl -pi`.

### Changes

- **`lanes.written_paths`** reads two more writers from the command's own words.
  - `perl -i`, its switches bundled or not (`-pi`, `-0pi`, `-0777 -pi`, `-pi.bak`, `-i -pe`): the files are the
    words after the switches and the program — never the `-e` code, never the program file when there is no
    `-e`. Without `-i` perl writes nothing there.
  - A Python script the line holds — `python3 -c CODE`, or a here-document for `python3 -` or a `python3` with no
    script — read with Python's `ast`, imported only for such a line: what it opens to write by a path it spells
    out. `open(p, …)` with `w`, `a`, `x` or `+` in its mode (also `io.open`, `codecs.open`); `Path.write_text`,
    `write_bytes`, `touch`, `unlink`, `open('w')`; `x.replace(p)` / `x.rename(p)` with one argument (a str's
    `replace` takes two); the destination of `os.replace`, `os.rename`, `shutil.copy*`, `shutil.move`;
    `os.remove`, `os.unlink`, `os.truncate`. `p` is a literal, `Path(…)`, `os.path.join(…)`, `/`, `+`, an
    f-string of them, or a name bound to one where the call runs — the statements are read in the order they
    run, so one `p` that holds a spec and then the status writes each in turn. A name bound inside a function, a
    lambda, a class or a comprehension is unknown there. `os.chdir` to a path the script spells out moves the
    relative paths after it; after one it does not spell out they are in no known folder and count where a
    command's folder is unknown. In an unquoted here-document (`<<PY`) a path with `$` or a backquote is the
    shell's, not spelled out. A script file the line only runs (`python3 tools/x.py`), `python3 -m`, a script
    that does not parse: nothing.
  - A caller after one file names it (`written_paths(c, named)`), and a Python script that never spells that name
    is not read: the Stop gate passes `status.md`, so the scripts of a turn that never touch the status cost
    nothing.
- **`stop_gate.turn_work`**: a status write counts in the tree of the file it writes also when the command runs
  in a folder outside git — `Path('<lane>/docs/ai/status.md').write_text(…)`, or `sed -i … <lane>/docs/ai/status.md`,
  from the empty folder of wave 40. 0.4.1 skipped every command whose own folder was outside git, and its
  writes with it.
- **`guard.py`**: a gate-config write asks when a command's own words write one (`lanes.written_paths`) — `sed -i
  's/a|b/c/' .groundwork.json`, `sed -i '' 's|"test": …|…|' .groundwork.json`, `perl -pi … .claude/follow-through.json`,
  a Python script writing `.groundwork.json` or `Path('.claude') / 'settings.json'` — by the switch of the tree
  the file is in, as since 0.4.0. The line cut on `|` and `;` (`lanes.shell_writes`) still answers for what no
  command shows: `echo '{}' > "$CFG/.groundwork.json"`, a write inside `ssh '…'`. A line that names no gate-config
  file is not parsed for it.

### Acceptance criteria

- **FT41-AC6** A commit after `perl -pi -e 's/\| doing \|/| done |/' docs/ai/status.md` (also `-0pi`, `-0777 -i -pe`),
  or after a Python here-document or `python3 -c` that opens the status to write (`open(p, 'w')`,
  `pathlib.Path(…).write_text`), passes. After `perl -ne …`, `perl -pe … > /tmp/x`, a perl that rewrites another
  file on a line that only stages the status, a script that reads the status and writes another file, or a
  script file, it is refused as before. The write counts in the tree of the file — from a folder outside git
  too — and never for another worktree.
- **FT41-AC7** `sed -i 's/a|b/c/' .groundwork.json`, `sed -i '' …` on `.claude/settings.json`, `perl -pi` on
  `.claude/follow-through.json`, and a Python script writing `.groundwork.json` or `Path('.claude') /
  'settings.json'` ask. Reading a gate config with `grep`, `jq` in a pipeline, `perl -ne`, `sed -n` or a Python
  script does not. `echo '{}' > "$CFG/.groundwork.json"` still asks. A script writing a lane's gate config asks
  by the lane's switch.

### Verification

- `follow-through/hooks/tests/test_writes.py` (new): 15 of 15. Against the 0.4.1 hooks 9 of the 15 fail; the other
  six hold that a read stays a read and a script file stays unseen. follow-through 120 of 120; `bash
  hooks/tests/all.sh` green.
- Replayed on the author's machine, 0.4.1 against 0.4.2 run at one moment (the mirror check reads the live
  `origin/development`): every turn of every transcript with a Bash line that
  names `docs/ai/status.md` (160 turns), and every Bash line that names a gate-config file (493 lines). No
  turn loses a status edit 0.4.1 counted, no line 0.4.1 asked on passes. 11 turns 0.4.1 refused pass now,
  each a script that moved the status (read one by one: 10 Python, 1 perl). 15 lines ask now, each a
  real write of a file named as a gate config: 3 `sed -i '' 's|…|…|' .groundwork.json` in project A lanes,
  the rest Python scripts writing a project's `.groundwork.json` or groundwork's own template.
- 26 mutations — each fix undone in a copy of the hooks, the name filter inverted or pointed at another file —
  each fail at least one case.
- Cost, measured on the author's Mac: `guard.py` per call 82–91 ms against 79–86 ms on 0.4.1 (Python's start-up;
  a line that names a gate config and runs a Python script reads the script, +5–9 ms); the Stop gate on a
  401-call turn with 100 Python scripts 184 ms against 182 ms. On the 40 largest real turns the reader ran on 6
  scripts, 3 ms in all; without the name filter it read 2034 of them, ~0.8 s.

### Changed on purpose

- A Python script writing another tree's gate config answers to that tree's `gates.destructive`, as every other
  write has since 0.4.0 (`echo '{}' > <lane>/.groundwork.json`). 0.4.1 asked it by the session folder's switch,
  since it could not see where the script wrote: off in the lane now silences it from outside, and off in the
  session's folder no longer does. No such line is in the replay.

### Not changed

- `sed` in place is read as before, `-i…` only as its own word: `sed -Ei`, `sed --in-place` are not seen (none in
  the transcripts touches the status).
- Not seen: a script file the line only runs, `python3 -m`, a script fed through a pipe (`cat x.py | python3 -`),
  `xargs perl -pi`, a path from `sys.argv`, the environment or a function's parameter, perl's own `open(F, '>',
  …)` without `-i`. The status gate refuses as before; the gate-config prompt asks only when the line shows the
  write.
