#!/usr/bin/env python3
"""Groundwork plugin :: PreToolUse(Bash) — what must be green before code reaches a shared branch (waves 37-38).

No project's CI runs the tests, so a push to a shared branch (`gates.shared_branches`, default development /
develop / main / master / staging / production) is the last moment anything checks them. A feature-branch
push is never stopped.

`gates.full_suite_before_push`:
  "when-needed" (default) — the pushed code must rest on a *verified* tree: one with a green whole run, or
      one this check accepted, whose chain starts from a whole run at most `gates.full_suite_max_age_hours`
      (default 24) old. From the closest such tree, the change may not touch a shared file (dependencies,
      test bootstrap, providers, middleware, a destructive migration — gw_tests.is_shared), and the close
      and wide tests of that change must be green on this exact code. A change no test reads needs no run.
  "always" — the 0.47.0 rule: a green whole run on this exact tree.
  false — off.

Measured before this rule (otaje, 2026-10-06 .. 10-21): 51 whole-suite episodes, ~1049 minutes, median 17;
96 of 180 commits on development changed only documents and still needed a whole run each.
The denial names one command, test-run.py --for-push, which runs exactly what is missing and records it.
Inert outside a Groundwork project and on any error.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_tests as gw  # noqa: E402


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
            branch = gw.git("branch", "--show-current", cwd=cwd).strip()
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
    top = gw.toplevel(cwd)
    if not top or not os.path.isfile(os.path.join(top, ".groundwork.json")):
        return
    cfg = gw.config(top)
    if gw.push_mode(cfg) == "off":
        return
    shared = gw.gates(cfg).get("shared_branches") or gw.SHARED_BRANCHES
    cmds = cfg.get("commands") or {}
    whole_cmd = cmds.get("test_full") or cmds.get("test") or "./vendor/bin/sail artisan test"

    targets = [(src, dst) for src, dst in pushed_refs(cmd, top) if dst in shared]
    if re.search(r"\bgh\s+pr\s+merge\b", cmd):
        targets.append(("HEAD", "the pull request's base"))
    if not targets:
        return
    runner = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test-run.py")
    problems = []
    for src, dst in targets:
        tree = gw.ref_tree(src, top)
        if not tree:
            continue
        need = gw.requirement(tree, cfg, top)
        if need["ok"]:
            if need["kind"] == "files":
                gw.record_verified(tree, need["root_time"], need["base"], "delta", top)
            continue
        if need["kind"] == "whole":
            what = "the whole suite (%s; it runs `%s`)" % (need["reason"], whole_cmd)
        else:
            what = "%s: %s" % (need["reason"], ", ".join(need["files"][:5]) + (" …" if len(need["files"]) > 5 else ""))
        problems.append("%s → %s needs %s. Run `python3 \"%s\" --for-push %s` with run_in_background: true, "
                        "wait for its notification, then push again" % (src, dst, what, runner, src))
    if not problems:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "groundwork push-gate: " + " | ".join(problems) +
            ". The runner records what passed by the exact code, so a commit of the same content still counts. "
            "A feature-branch push needs nothing. (gates.full_suite_before_push: \"always\" demands the whole "
            "suite on every push; false turns this off.)"
    }}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
