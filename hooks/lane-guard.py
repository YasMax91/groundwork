#!/usr/bin/env python3
"""Groundwork plugin :: PreToolUse(Bash) — a lane's runner never reaches another lane's stack (GW35-AC2).

A worktree whose `.env` is missing, or carries the main checkout's COMPOSE_PROJECT_NAME or DB_DATABASE,
sends every `sail …` into the MAIN stack: the main checkout's code under test, the shared dev database
written, the shared test database raced. Observed on 2026-10-05 in 4 (stack) and 9 (dev DB) of otaje's
26 worktrees, and behind «15 phpstan errors and 91 failures» that were another session's work.

Denies such a runner command with the fix (`lane.py up`). Inert in the main checkout, outside a
Groundwork project, and under `gates.lane_guard: false`. Any error → allow.
"""

import json
import os
import re
import subprocess
import sys

RUNNER = re.compile(r"(^|[\s;&|(])(\./)?vendor/bin/sail\b|(^|[\s;&|(])(php\s+)?artisan\b|\bsail\s+(artisan|test|composer|php|up|pint|npm)\b")
LANE_TOOL = re.compile(r"\blane\.py\b")


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def env_value(path, key):
    try:
        for line in open(path, encoding="utf-8"):
            m = re.match(r"^\s*%s\s*=\s*(.*)$" % key, line)
            if m:
                return m.group(1).strip().strip('"').strip("'")
    except Exception:
        return None
    return ""


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    cmd = str((payload.get("tool_input") or {}).get("command") or "")
    if not RUNNER.search(cmd) or LANE_TOOL.search(cmd):
        return
    cwd = payload.get("cwd") or os.getcwd()
    top = git(cwd, "rev-parse", "--show-toplevel")
    if not top or not os.path.isfile(os.path.join(top, ".groundwork.json")):
        return
    try:
        cfg = json.load(open(os.path.join(top, ".groundwork.json"), encoding="utf-8"))
        if (cfg.get("gates") or {}).get("lane_guard") is False:
            return
    except Exception:
        pass
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    gitdir = git(cwd, "rev-parse", "--path-format=absolute", "--git-dir")
    if not common or os.path.realpath(common) == os.path.realpath(gitdir):
        return  # the main checkout owns the main stack
    main_root = os.path.dirname(common)
    lane_env, main_env = os.path.join(top, ".env"), os.path.join(main_root, ".env")
    if not os.path.isfile(main_env):
        return
    problems = []
    if not os.path.isfile(lane_env):
        problems.append("this worktree has no .env")
    else:
        for key, what in (("COMPOSE_PROJECT_NAME", "Docker stack"), ("DB_DATABASE", "dev database")):
            mine, theirs = env_value(lane_env, key), env_value(main_env, key)
            if theirs and (mine == theirs or mine == ""):
                problems.append("its %s is the main checkout's (%s=%s)" % (what, key, theirs))
    if not problems:
        return
    lane_py = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lane.py")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": (
            "groundwork lane-guard: this command would run in the MAIN checkout's stack — %s. Its code is another "
            "session's, and its databases are shared. Provision this worktree as its own lane first: "
            "`python3 %s up` (own stack, own domain, dev DB cloned, own test DB), then rerun." % ("; ".join(problems), lane_py))
    }}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
