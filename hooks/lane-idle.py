#!/usr/bin/env python3
"""Groundwork plugin :: SessionEnd — stop a lane's stack when the last session in its worktree closes.

Wave 36. Lanes outlive their sessions: on 2026-10-06 six otaje lanes were up (34 containers) with most of
their sessions closed, and the host was 7.9 of 9.2 GB into swap. When the session that ends was the last
live one in this worktree, the lane's containers are stopped — `docker compose stop`, so nothing is
removed: data, volumes, `.env` and `phpunit.xml` stay, and `lane.py up` (or `sail up -d`) brings it back.

"Last live one" = no other session in follow-through's registry with this `cwd` and no other `claude`
process whose working directory is this worktree. Runs detached so closing a session never waits on
Docker. Inert outside a provisioned lane, under `gates.lane_idle_stop: false`, and on any error.
"""

import json
import os
import subprocess
import sys
import time


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def other_registry_sessions(cwd, sid):
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    d = os.path.join(common, "follow-through", "sessions") if common else ""
    n = 0
    if d and os.path.isdir(d):
        for name in os.listdir(d):
            try:
                e = json.load(open(os.path.join(d, name), encoding="utf-8"))
            except Exception:
                continue
            if e.get("session_id") != sid and e.get("cwd") == os.path.realpath(cwd) \
                    and time.time() - float(e.get("heartbeat", 0)) < 30 * 60:
                n += 1
    return n


def claude_processes_in(cwd):
    try:
        out = subprocess.run(["lsof", "-a", "-d", "cwd", "-c", "claude", "-Fn"], capture_output=True,
                             text=True, timeout=10).stdout
    except Exception:
        return 0
    here = os.path.realpath(cwd)
    return sum(1 for line in out.splitlines() if line.startswith("n") and os.path.realpath(line[1:]) == here)


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    cwd = payload.get("cwd") or os.getcwd()
    top = git(cwd, "rev-parse", "--show-toplevel") or cwd
    lane_file = os.path.join(top, ".claude", "lane.json")
    if not os.path.isfile(lane_file):
        return
    try:
        cfg = json.load(open(os.path.join(top, ".groundwork.json"), encoding="utf-8"))
        if (cfg.get("gates") or {}).get("lane_idle_stop") is False:
            return
    except Exception:
        pass
    try:
        project = json.load(open(lane_file, encoding="utf-8")).get("compose_project") or ""
    except Exception:
        return
    main_env = os.path.join(os.path.dirname(git(top, "rev-parse", "--path-format=absolute", "--git-common-dir")), ".env")
    try:
        if any(l.strip() == "COMPOSE_PROJECT_NAME=%s" % project for l in open(main_env, encoding="utf-8")):
            return  # never the main checkout's stack
    except Exception:
        pass
    if not project or other_registry_sessions(top, payload.get("session_id") or "") or claude_processes_in(top) > 1:
        return
    subprocess.Popen(["docker", "compose", "-p", project, "stop"], cwd=top, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
