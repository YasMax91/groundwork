# Spec: Wave 42 — a lane stops when the last session working in it closes, wherever that session was opened (groundwork v0.51.0)

- Type: hook behaviour change (SessionEnd `lane-idle.py`, PreToolUse `session-repos.py`) → **L2** (it decides
  whether a running stack is stopped under a session that may still use it).
- Author: Max Yastremskyi (YasMax91).
- Source: the gap wave 41 recorded under «Not changed» (2026-10-22): a session that works in a lane from outside
  its folder counts as live there, and at its own end nothing stops the lane's stack.
- Decisions taken with the author on 2026-10-22:
  - the lanes a session worked in from outside come from groundwork's records, not from follow-through's list of
    outside trees, which follow-through's own SessionEnd removes while lane-idle runs;
  - a session counts in a lane while it called into it in the last 30 minutes, its subagents included —
    groundwork notes when a session last called into each project. An earlier draft counted a session in every
    lane its registry named for as long as it lived; the second review showed that kept a lane up all day under a
    session that had left it;
  - on `/clear` and `/resume` the session's folder's lane is kept.
- Status: **implemented** (2026-10-22).

## What was missing (groundwork 0.50.1)

`lane-idle.py:60-61` judged one tree: the root of the payload's `cwd`, the closing session's folder. A session
opened in an empty folder that worked in a lane through `cd <lane> && …` or by editing files there by absolute
path ran its SessionEnd in the empty folder, found no `.claude/lane.json` and returned. Since follow-through 0.4.0
the same session is registered in the lane's repository (`cwd` the lane, `opened_in` its own folder), so the
SessionEnd of another session closing in the lane saw it live and left the stack up — and when it then closed
last, the stack stayed up with no session left. A lane the session had moved into and left again (a `cd` Claude
kept, EnterWorktree then ExitWorktree) was not judged at its end either.

Three more gaps sat in the same check, and stopping lanes from outside would have widened each:

- follow-through keeps one entry per session and repository, with the tree the session last worked in. A session
  opened in the main checkout that works in a lane of the same repository keeps its entry on the main checkout;
  a session working in two lanes of one project is registered in one of them. Another session closing in the lane
  did not see it there (`lane-idle.py:29-42` compared `cwd` with the lane) and could stop the stack under it.
- `claude` processes were found by `lsof -c claude` (`lane-idle.py:45-52`), the name the kernel gives a process: its
  file's. The CLI started from a terminal is `~/.local/bin/claude`, a link to `…/claude/versions/<version>`, so on
  macOS its process is named `2.0.61` — invisible. Only the desktop app's sessions (`…/MacOS/claude`) were seen.
- «More than one process in the worktree» (`lane-idle.py:81`) assumed the closing session's own process works
  there. In a lane the session worked in from outside, its process is not there — the process keeps the folder
  the session was opened in — so one process in the lane is another session's.

## Changes

- **`hooks/gw_activity.py`** (new): `~/.claude/groundwork/sessions/<session id>.activity.json` (`GW_SESSIONS_DIR`)
  — {project root: the time of the session's last Bash / Edit / Write call there}. Every Groundwork project a call
  works in counts — the session's own folder and reading included: a lane needs its stack while a session works
  in it, whatever it runs; a directory the line does not name does not. A root is rewritten at most once a minute,
  through a temporary file. Hooks fire inside a subagent with its session's id — checked on 2026-10-22: a subagent's
  Bash call into a throwaway repository was registered by follow-through under the session's id — so a subagent's
  calls are its session's. Files a month old are dropped when a new one is made.
- **`hooks/session-repos.py`** (PreToolUse `Bash|Edit|Write|MultiEdit|NotebookEdit`) records the call there, next
  to `gw_repo.remember`.
- **`hooks/lane-idle.py`**:
  - judges the session's folder, as before, and the worktree of every project the session worked in — the ones
    groundwork's registry remembers for it (`gw_repo.remembered`) and the ones its activity file names — each taken
    to its repository's root, once. Each is judged on its own: its `.claude/lane.json`, its `gates.lane_idle_stop`,
    the main-stack guard; it is stopped with `docker compose -p <lane> stop`, detached, when no other session works
    in it. A folder that is gone or is no lane adds nothing; an error in one tree does not stop the others. The
    closing session's activity file is read, then removed — a file is a session that has not ended.
  - Another session works in a lane when its entry in follow-through's registry of the lane's repository has its
    `cwd` there and a heartbeat under 30 minutes old (as before); or its activity file names the lane with a call in
    the last 30 minutes; or a `claude` process other than the closing session's own has its folder there.
  - A `claude` process is one started as `claude` — `ps`'s `comm`, the path it was started by: `~/.local/bin/claude`
    for the CLI, `…/MacOS/claude` for the desktop app — and `lsof -p` gives its folder. The closing session's own
    is the nearest ancestor of the hook among them (`ps -A -o pid=,ppid=,comm=`), so a session started inside
    another one (`claude -p` from a Bash call) finds itself first. When no ancestor is one, the 0.50.1 rule holds in
    the session's folder — one process there is taken for its own — and in any other lane every process counts.
    When the processes cannot be read (`ps` fails, no `lsof`), nothing is stopped: never stop blind.
  - «In a lane» is the lane or a folder of it that is not in a lane nested in it — a submodule or a clone inside
    the lane is the lane's, a worktree with its own `.claude/lane.json` inside it is another lane — for an entry's
    `cwd`, a project root in an activity file and a process's folder alike.
  - On `/clear` and `/resume` (SessionEnd `reason`) the process goes on as another session: the lane of its folder
    is not judged, the other lanes are, and its process counts as anyone's.
  - The closing session is never another one: its entries are skipped by session id — follow-through's SessionEnd
    removes them alongside, so lane-idle may still find them — and so is its activity file if it could not be
    removed.
  - The main checkout's stack is never stopped: it has no `.claude/lane.json` (`lane.py` refuses the main
    checkout), a lane.json naming the main checkout's `COMPOSE_PROJECT_NAME` is skipped as before, and now so is a
    lane whose repository's common dir cannot be read. A registry line that names no folder, and an activity value
    that is no time, are skipped.
- **Tests.** `hooks/tests/lane-idle.sh`: `ps` and `lsof` are stubs too — `ps` gives the real pid/ppid table with
  only the pids a case names called `claude` (the test's own shell, an ancestor of the hook, stands for the closing
  session's process), `lsof -p` their folders and `lsof -c claude` nothing, what macOS answers for the CLI; a case
  waits for the stub docker processes the hook started instead of a fixed second (`Popen` returns once they run).
  `hooks/tests/command-repo.sh`: the activity file next to the registry.

## Acceptance criteria

- **GW42-AC1** A session opened outside the project (an empty folder) that worked in a lane and closes last stops
  the lane's stack; while another session works in the lane — by a fresh entry there, a call there in the last 30
  minutes, or a `claude` process there — the stack stays up.
- **GW42-AC2** The closing session is never counted in a lane: not by its own entry in the lane's registry
  (whether follow-through's SessionEnd removed it yet or not), not by its own calls, not by its own `claude`
  process; its activity file is gone after its end.
- **GW42-AC3** A session opened in the main checkout that worked in a lane of the same repository, or that moved
  into a lane and left it, stops the lane's stack when it closes last; the main checkout's stack is never stopped.
- **GW42-AC4** A session that called into the lane in the last 30 minutes keeps it up, whatever tree its entry
  names and however quiet its entry is (a subagent's calls); one whose last call there is older does not, though
  its registry names the lane and it works elsewhere now; once it ended it does not.
- **GW42-AC5** A `claude` process keeps a lane whatever its file is named: the CLI's process, which `lsof -c claude`
  does not find, keeps it as the app's does; so does a process or an entry in a folder of the lane or in a clone
  inside it, and not one in a lane nested in it. When the processes cannot be read, nothing is stopped.
- **GW42-AC6** Each lane is judged by its own files: `gates.lane_idle_stop: false` in the session's folder keeps
  that folder's lane only, and in the lane itself keeps the lane; a lane.json naming the main stack is never
  stopped; a folder that is gone or is no lane adds nothing; the session's folder's lane and another one are both
  stopped, each once.
- **GW42-AC7** In the session's own folder wave 36 holds, exactly once the session's own process is found: its own
  process does not keep the lane, one more `claude` process does; when none is found, one process there is taken
  for its own.
- **GW42-AC8** On `/clear` and `/resume` the lane of the session's folder stays up, the lanes it worked in from
  outside are judged, and its process keeps a lane it is in.
- **GW42-AC9** A call notes every Groundwork project it works in — a read, an Edit, the session's own folder, a
  subagent's call — at most once a minute per project; a folder that is no Groundwork project and a directory the
  line does not name are not noted; a new session's file drops the month-old ones.

## Verification

- `hooks/tests/lane-idle.sh`: 44 of 44 (38 new). Run against the 0.50.1 hook, 21 of the 44 fail — every case where a
  stack must now stop, and a CLI session's process the old `lsof -c claude` did not see; the cases where a stack must
  stay up pass there too, and guard the new stops from going further than they should.
- `hooks/tests/command-repo.sh`: 94 of 94 (9 new, the activity file).
- 27 mutations — 22 of `lane-idle.py` (the remembered lanes, the activity lanes, the closing session's file kept or
  counted, its entries counted, the activity rule dropped or taken at any age, «in a lane» as the exact path for
  an entry and for a process, nested lanes counted, clones not counted, stale entries taken as live, the own
  process counted, `/clear` judging its folder or not counting its process, the 0.50.1 fallback dropped, processes
  by `lsof -c claude` again, every process taken for a `claude`, stopping blind when `ps` fails, no deduplication,
  the main-stack guard, the opt-out) and 5 of `gw_activity.py` (no once-a-minute limit, reads not noted, unknown
  directories noted, month-old files kept, values that are no time read) — each fail at least one case.
- On the author's Mac, with the real `ps` and `lsof` and a stub docker: a process started through a link named
  `claude` (`ps` says `…/claude`, the kernel `sleep`) in a lane kept it — closing from an empty folder and closing in
  the lane — while the 0.50.1 hook, closing in the lane, stopped it; with the process gone the lane stopped.
- Two adversarial reviews. The first found the CLI's process invisible to `lsof -c claude`, a parent session taken
  for the closing one's own process, an entry gone stale under Bash-only work, sessions and processes in a folder
  of the lane not counted, and a broken registry line skipping the lane. The second, on the draft that counted a
  session by its registry, found lanes kept up all day under sessions that had left them, a subagent's work not
  seen, clones inside a lane not counted, `ps` failing into a blind stop, and the cost of checking stale entries.
  All are fixed and pinned above; the rest is under «Not changed».
- All groundwork suites green, follow-through's included (`bash hooks/tests/all.sh`).
- Not run live: the SessionEnd of a real session.

## Not changed

- A single call longer than 30 minutes (a whole suite) is noted when it starts: a session working in the lane from
  elsewhere — its process not there — no longer keeps the lane once that call is 30 minutes old and its entry is
  not refreshed in between.
- Read, Grep and Glob are no calls here (session-repos.py runs on Bash, Edit and Write): a session that only reads
  the lane's files through them for 30 minutes does not keep it.
- `/clear` and `/resume`: the new session has no record of the old one's lanes, so a lane the old one worked in
  from outside is judged at the `/clear`, not at the new session's end.
- Sessions that close at the same moment each see the others, and none stops the lane — as before.
- On a host without `lsof` the processes cannot be read, so lane-idle stops nothing there.
- `gw_repo.live_elsewhere`, which decides whether a Stop gate's verdict from a remembered repository blocks, still
  finds `claude` processes by `lsof -c claude` and reads only entries naming that tree.
- A background session that runs inside a process named otherwise than `claude` is not counted by its process.
