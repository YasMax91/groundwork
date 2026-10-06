#!/usr/bin/env python3
"""Groundwork plugin :: remember a green whole-suite run, keyed by the exact code it ran on (wave 37).

    suite-record.py --record      record the current working tree as passed
    suite-record.py --check REF   exit 0 when REF's tree (or the working tree for "WORKTREE") has a pass

The key is a git tree id: for the working tree it is built in a throwaway index (`git add -A` respects
.gitignore), so committing the same content later yields the same id and the pass still counts. Records
live in `<git-common-dir>/groundwork/suite-passes/`, shared by every worktree of the repository.
Also a PostToolUse(Bash) hook: an agent's own whole-suite run (`artisan test` / `composer test` with no
paths or --filter) that printed a summary with no failures is recorded too, so the gate never repeats it.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time


def git(*args, env=None):
    try:
        r = subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=60, env=env)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def worktree_tree():
    top = git("rev-parse", "--show-toplevel")
    if not top:
        return ""
    fd, idx = tempfile.mkstemp(prefix="gw-index-")
    os.close(fd)
    os.unlink(idx)
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    try:
        if git("read-tree", "HEAD", env=env) is None:
            return ""
        git("-C", top, "add", "-A", env=env)
        return git("write-tree", env=env)
    finally:
        try:
            os.unlink(idx)
        except Exception:
            pass


def store():
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    if not common:
        return ""
    d = os.path.join(common, "groundwork", "suite-passes")
    os.makedirs(d, exist_ok=True)
    return d


def record():
    tree, d = worktree_tree(), store()
    if tree and d:
        with open(os.path.join(d, tree), "w") as fh:
            json.dump({"time": int(time.time()), "head": git("rev-parse", "HEAD")}, fh)
    return tree


def has_pass(ref):
    tree = worktree_tree() if ref == "WORKTREE" else git("rev-parse", "%s^{tree}" % ref)
    d = store()
    return bool(tree and d and os.path.isfile(os.path.join(d, tree))), tree


FULL = re.compile(r"(artisan\s+test|composer\s+(run\s+)?test)(?![^\n;&|]*(--filter|--group|--testsuite|tests/|\.php\b))")
SUMMARY = re.compile(r"Tests:\s+.*\bpassed\b")


def post_tool():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    cmd = str((payload.get("tool_input") or {}).get("command") or "")
    if not FULL.search(cmd):
        return
    resp = payload.get("tool_response") or {}
    out = resp if isinstance(resp, str) else (str(resp.get("stdout") or "") + str(resp.get("stderr") or ""))
    summary = [l for l in out.splitlines() if l.strip().startswith("Tests:")]
    if summary and SUMMARY.search(summary[-1]) and not re.search(r"\b(failed|errors?)\b", summary[-1]):
        record()


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        if a[:1] == ["--record"]:
            print(record())
        elif a[:1] == ["--check"]:
            ok, tree = has_pass(a[1] if len(a) > 1 else "WORKTREE")
            print(tree)
            sys.exit(0 if ok else 1)
        else:
            post_tool()
    except SystemExit:
        raise
    except Exception:
        pass
    sys.exit(0)
