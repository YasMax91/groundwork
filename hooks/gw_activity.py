"""Groundwork plugin :: when a session last called into each Groundwork project (wave 42).

`~/.claude/groundwork/sessions/<session id>.activity.json` (`GW_SESSIONS_DIR`): {project root: the time of the
session's last Bash / Edit / Write call there}. session-repos.py notes it before each call, at most once a minute per
root — the session's own folder and reading included: a lane needs its stack while a session works in it, whatever
it runs. Hooks fire inside a subagent with its session's id, so a subagent's calls are its session's. lane-idle.py
reads the files at SessionEnd — the lanes the closing session worked in, and whether another session called into a
lane in the last 30 minutes — and removes the closing session's own, so a file is a session that has not ended.
Files a month old are dropped.
"""

import json
import os
import re
import time

import gw_repo as repo

STEP = 60
SUFFIX = ".activity.json"


def path(sid):
    sid = str(sid or "")
    return os.path.join(repo.sessions_dir(), sid + SUFFIX) if re.fullmatch(r"[A-Za-z0-9._-]{1,128}", sid) else ""


def _read(p):
    try:
        with open(p, encoding="utf-8") as fh:
            d = json.load(fh)
    except Exception:
        return {}
    if not isinstance(d, dict):
        return {}
    return {k: float(v) for k, v in d.items() if isinstance(k, str) and k and isinstance(v, (int, float))}


def read(sid):
    """{project root: time of the last call there} for one session; {} when it has none."""
    p = path(sid)
    return _read(p) if p else {}


def sessions(since=0):
    """[(session id, {project root: time})] of the sessions with a file written at `since` or later."""
    d = repo.sessions_dir()
    try:
        names = os.listdir(d)
    except Exception:
        return []
    out = []
    for n in names:
        p = os.path.join(d, n)
        try:
            if n.endswith(SUFFIX) and os.path.getmtime(p) >= since:
                out.append((n[:-len(SUFFIX)], _read(p)))
        except Exception:
            continue
    return out


def record(payload):
    """Note the time on each Groundwork project this call works in; the roots noted."""
    p = path(payload.get("session_id"))
    if not p:
        return []
    roots = []
    for root, _, known in repo.call_targets(payload):
        if known and repo.is_groundwork(root) and root not in roots:
            roots.append(root)
    now = int(time.time())
    seen = _read(p)
    due = [r for r in roots if now - seen.get(r, 0) >= STEP]
    if not due:
        return []
    seen.update({r: now for r in due})
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        first = not os.path.exists(p)
        tmp = "%s.%d" % (p, os.getpid())
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(seen, fh)
        os.replace(tmp, p)
        if first:                                       # a new session: drop the files of month-old ones
            for n in os.listdir(os.path.dirname(p)):
                f = os.path.join(os.path.dirname(p), n)
                if n.endswith(SUFFIX) and now - os.path.getmtime(f) > 30 * 86400:
                    os.unlink(f)
    except Exception:
        return []
    return due


def forget(sid):
    p = path(sid)
    try:
        if p:
            os.remove(p)
    except Exception:
        pass
