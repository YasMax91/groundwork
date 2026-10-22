#!/usr/bin/env python3
"""Groundwork plugin :: SessionEnd — stop a lane's stack when the last session working in it closes.

Wave 36. Lanes outlive their sessions: on 2026-10-06 six project A lanes were up (34 containers) with most of
their sessions closed, and the host was 7.9 of 9.2 GB into swap. When the session that ends was the last
live one in this worktree, the lane's containers are stopped — `docker compose stop`, so nothing is
removed: data, volumes, `.env` and `phpunit.xml` stay, and `lane.py up` (or `sail up -d`) brings it back.

Wave 42. A session also works in lanes outside its folder (`cd <lane> && …`, edits by absolute path) and in lanes it
moved into (a `cd` Claude kept, EnterWorktree). At its end each lane it worked in is judged like its folder: the
lanes groundwork's registry remembers for it (gw_repo.remembered) and the ones its activity file names
(gw_activity). Before, a session opened in an empty folder that closed last left the lane it worked in running.

"Last live one" = no other session works in the worktree: no other session's entry in follow-through's registry of
that repository has its `cwd` there and a heartbeat under 30 minutes old; no other session's activity file names it
with a call in the last 30 minutes; and no `claude` process but the closing session's own has its folder there. On
`/clear` and `/resume` the process goes on as another session: its folder's lane is kept, and the process counts as
anyone's. Runs detached so closing a session never waits on Docker. Inert outside a provisioned lane, under the
lane's `gates.lane_idle_stop: false`, for the main checkout's stack, when the processes cannot be read, and on any
error.
"""

import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_activity as activity  # noqa: E402
import gw_repo as repo  # noqa: E402

LIVE_SECONDS = 30 * 60
_TOPS = {}


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def lane(top):
    """(Compose project, git common dir) of the lane at `top`; no project when it is no lane, opts out, or names
    the main checkout's stack."""
    lane_file = os.path.join(top, ".claude", "lane.json")
    if not os.path.isfile(lane_file):
        return "", ""
    try:
        cfg = json.load(open(os.path.join(top, ".groundwork.json"), encoding="utf-8"))
        if (cfg.get("gates") or {}).get("lane_idle_stop") is False:
            return "", ""
    except Exception:
        pass
    try:
        project = json.load(open(lane_file, encoding="utf-8")).get("compose_project") or ""
    except Exception:
        return "", ""
    common = git(top, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not project or not common:
        return "", ""
    try:
        if any(l.strip() == "COMPOSE_PROJECT_NAME=%s" % project
               for l in open(os.path.join(os.path.dirname(common), ".env"), encoding="utf-8")):
            return "", ""  # never the main checkout's stack
    except Exception:
        pass
    return project, common


def within(path, here):
    """`path` is in the worktree `here`: the worktree, or a folder of it that is not in a lane nested in it (a
    submodule or a clone inside it is the lane's)."""
    path = os.path.realpath(path)
    if path == here:
        return True
    if not path.startswith(here + os.sep):
        return False
    if path not in _TOPS:
        _TOPS[path] = os.path.realpath(git(path, "rev-parse", "--show-toplevel") or here)
    return _TOPS[path] == here or not os.path.isfile(os.path.join(_TOPS[path], ".claude", "lane.json"))


def registry_live(top, common, sid, now):
    """Another session's entry in follow-through's registry has its `cwd` in `top`, refreshed in the last 30 minutes."""
    d = os.path.join(common, "follow-through", "sessions")
    here = os.path.realpath(top)
    try:
        files = os.listdir(d)
    except Exception:
        return False
    for name in files:
        try:
            e = json.load(open(os.path.join(d, name), encoding="utf-8"))
            cwd = e.get("cwd")
            if e.get("session_id") != sid and isinstance(cwd, str) and cwd \
                    and now - float(e.get("heartbeat", 0)) < LIVE_SECONDS and within(cwd, here):
                return True
        except Exception:
            continue
    return False


def claude_processes():
    """([(pid, real cwd)] of the `claude` processes, the closing session's own pid or ''); None when they cannot be read.

    A `claude` process is one started as `claude` (`ps` comm): the kernel's name — lsof's `-c` — is the file's, and the
    CLI's file is named by its version (`~/.local/bin/claude` → `…/versions/2.0.61`). The closing session's own is the
    nearest ancestor of this hook among them."""
    try:
        r = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,comm="], capture_output=True, text=True, timeout=5)
        if r.returncode != 0:
            return None
    except Exception:
        return None
    parent, claude = {}, set()
    for line in r.stdout.splitlines():
        f = line.split(None, 2)
        if len(f) == 3:
            parent[f[0]] = f[1]
            if os.path.basename(f[2].strip()) == "claude":
                claude.add(f[0])
    own, p = "", str(os.getppid())
    for _ in range(64):
        if p in claude:
            own = p
            break
        p = parent.get(p, "")
        if p in ("", "0"):
            break
    if not claude:
        return [], own
    try:
        out = subprocess.run(["lsof", "-a", "-d", "cwd", "-p", ",".join(sorted(claude)), "-Fpn"],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return None
    procs, pid = [], ""
    for line in out.splitlines():
        if line.startswith("p"):
            pid = line[1:]
        elif line.startswith("n") and pid in claude:
            procs.append((pid, os.path.realpath(line[1:])))
    return procs, own


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    sid = payload.get("session_id") or ""
    cwd = payload.get("cwd") or os.getcwd()
    goes_on = payload.get("reason") in ("clear", "resume")  # the process goes on as another session
    worked = activity.read(sid)
    activity.forget(sid)  # a file is a session that has not ended
    home = git(cwd, "rev-parse", "--show-toplevel") or cwd
    seen = {os.path.realpath(home)}
    tops = [] if goes_on else [home]
    for root in dict.fromkeys(repo.remembered(sid) + sorted(worked)):  # the lanes it worked in (wave 42)
        top = git(root, "rev-parse", "--show-toplevel")
        if top and os.path.realpath(top) not in seen:
            seen.add(os.path.realpath(top))
            tops.append(top)
    now, others, procs = time.time(), None, False
    for top in tops:
        try:
            project, common = lane(top)
            if not project or registry_live(top, common, sid, now):
                continue
            here = os.path.realpath(top)
            if others is None:
                others = [(s, r) for s, r in activity.sessions(since=now - LIVE_SECONDS) if s != sid]
            if any(now - t < LIVE_SECONDS and within(root, here) for _, roots in others for root, t in roots.items()):
                continue
            if procs is False:
                procs = claude_processes()
            if procs is None:
                continue  # the processes cannot be read: never stop blind
            found, own = procs
            n = sum(1 for p, d in found if (goes_on or p != own) and within(d, here))
            if n > (1 if top == home and not own else 0):  # own process unknown: one in its folder is taken for it
                continue
            subprocess.Popen(["docker", "compose", "-p", project, "stop"], cwd=top, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception:
            continue


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
