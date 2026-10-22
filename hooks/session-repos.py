#!/usr/bin/env python3
"""Groundwork plugin :: remember the Groundwork repositories a session changes outside its own folder (wave 40).

    (no arguments)                PreToolUse(Bash|Edit|Write|MultiEdit|NotebookEdit): record them (gw_repo.remember),
                                  and the time of the call in each project it works in (gw_activity.record, wave 42)
    --hook-dirs tool|each|first   in-cwd.sh: the directories to run a hook in, one per line (stdin: the payload)
    --transcripts <dir>           estimate-ledger.sh: transcripts of the sessions that worked in <dir>'s project
                                  from outside it, one per line
    --list <session id>           the remembered repositories, one per line

A session opened in one folder that works in another through `cd <lane> && …` or by editing files there by
absolute path had no Stop gate look at that work and no estimate recorded for it (2026-10-21). Reading — git
status / log / diff, cat, grep, ls — changes nothing and is not remembered. Silent and exit 0 on every failure.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_activity as activity  # noqa: E402
import gw_repo as repo  # noqa: E402


def payload():
    try:
        p = json.loads(sys.stdin.read() or "{}")
        return p if isinstance(p, dict) else {}
    except Exception:
        return {}


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        if a[:1] == ["--hook-dirs"]:
            print("\n".join(repo.hook_dirs(payload(), a[1] if len(a) > 1 else "tool")))
        elif a[:1] == ["--transcripts"] and len(a) > 1:
            print("\n".join(repo.transcripts_for(a[1])))
        elif a[:1] == ["--list"] and len(a) > 1:
            print("\n".join(repo.remembered(a[1])))
        elif not a:
            p = payload()
            repo.remember(p)
            activity.record(p)
    except Exception:
        pass
    sys.exit(0)
