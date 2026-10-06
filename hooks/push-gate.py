#!/usr/bin/env python3
"""Groundwork plugin :: PreToolUse(Bash) — the whole suite, once, before code reaches a shared branch (wave 37).

No project's CI runs the tests, so a push to a shared branch is the last moment anything checks the whole
suite. While working, the Stop gate runs only the tests that touch the change (test-select.py). This hook
refuses `git push` to a shared branch — `gates.shared_branches`, default development / main / master /
staging / production — and `gh pr merge`, until the commit being pushed has a green whole-suite run
recorded for its exact tree (suite-record.py). A run recorded on the working tree counts for the commit
made from it. A push of a feature branch is never stopped.

Inert outside a Groundwork project, without a runnable `commands.test`, under
`gates.full_suite_before_push: false`, and on any error.
"""

import json
import os
import re
import subprocess
import sys

DEFAULT_SHARED = ["development", "develop", "main", "master", "staging", "production"]


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def pushed_refs(cmd, cwd):
    """(local ref, remote branch) pairs a `git push …` segment would update."""
    out = []
    for seg in re.split(r"&&|\|\||;|\n", cmd):
        words = seg.strip().split()
        if "push" not in words or not any(w.endswith("git") for w in words[:words.index("push")]):
            continue
        args = [w for w in words[words.index("push") + 1:] if not w.startswith("-")]
        specs = args[1:] if args else []
        if not specs:
            branch = git(cwd, "branch", "--show-current")
            if branch:
                out.append(("HEAD", branch))
            continue
        for spec in specs:
            spec = spec.lstrip("+")
            src, _, dst = spec.partition(":")
            dst = dst or src
            out.append((src or "HEAD", dst.replace("refs/heads/", "")))
    return out


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    cmd = str((payload.get("tool_input") or {}).get("command") or "")
    if "push" not in cmd and "pr merge" not in cmd:
        return
    cwd = payload.get("cwd") or os.getcwd()
    top = git(cwd, "rev-parse", "--show-toplevel")
    if not top:
        return
    try:
        cfg = json.load(open(os.path.join(top, ".groundwork.json"), encoding="utf-8"))
    except Exception:
        return
    gates = cfg.get("gates") or {}
    if gates.get("full_suite_before_push") is False or gates.get("test_on_stop") is False:
        return
    shared = gates.get("shared_branches") or DEFAULT_SHARED
    cmds = cfg.get("commands") or {}
    test_cmd = cmds.get("test_full") or cmds.get("test") or "./vendor/bin/sail artisan test"

    targets = [(src, dst) for src, dst in pushed_refs(cmd, cwd) if dst in shared]
    if re.search(r"\bgh\s+pr\s+merge\b", cmd):
        targets.append(("HEAD", "the pull request's base"))
    if not targets:
        return
    rec = os.path.join(os.path.dirname(os.path.abspath(__file__)), "suite-record.py")
    missing = []
    for src, dst in targets:
        r = subprocess.run([sys.executable, rec, "--check", src], cwd=top, capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            missing.append("%s → %s" % (src, dst))
    if not missing:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": (
            "groundwork push-gate: %s goes to a shared branch and this exact code has no green run of the whole "
            "suite. Run it once — `%s` (no paths, no --filter) — then push again; the pass is recorded by the "
            "tree, so committing the same content afterwards still counts. A feature-branch push needs no full "
            "run. (gates.full_suite_before_push=false turns this off.)" % (", ".join(missing), test_cmd))
    }}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
