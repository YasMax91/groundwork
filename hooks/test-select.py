#!/usr/bin/env python3
"""Groundwork plugin :: which tests does this change touch? (waves 37-38)

    python3 test-select.py [--base <ref>]          the close circle, one test file per line
    python3 test-select.py --json [--base <ref>]   {"close", "wide", "shared", "why"} for the working change
    python3 test-select.py --json --from <tree> --to <tree>    the same for the change between two trees
    python3 test-select.py --plan-stop             what the Stop gate runs now, as JSON (see plan_stop)

The rules live in gw_tests.py. "The working change" = uncommitted, untracked, and committed-but-unpushed
(against the upstream's merge base), so a task's own work stays covered until it is pushed.
Nothing selectable -> nothing printed; any error -> nothing printed, exit 0 (the gate then says so).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_tests as gw  # noqa: E402


def arg(name, args):
    return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else None


def plan_stop(top, cfg):
    """The close circle minus what already passed on this exact code, cut to the budget by recorded time.

    The budget exists because the 0.47.0 gate ran whatever it selected: in project A 30 Stop runs took 5+
    minutes and 12 hit the 10-minute hook limit with nothing verified. What does not fit is named and left
    to the push check, which runs close + wide before code reaches a shared branch.
    """
    sel = gw.select(gw.WorkingTree(top))
    tree = gw.worktree_tree(top)
    green = gw.passed_files(tree, top)
    todo = [t for t in sel["close"] if t not in green]
    try:
        budget = float(gw.gates(cfg).get("test_budget_seconds") or 180)
    except Exception:
        budget = 180.0
    known = gw.durations(top)
    run, spent = [], 0.0
    for t in todo:
        cost = float(known.get(t, 1.5))
        if run and spent + cost > budget:
            break
        run.append(t)
        spent += cost
    return {"run": run, "deferred": todo[len(run):], "green": len(sel["close"]) - len(todo),
            "close": len(sel["close"]), "wide": len(sel["wide"]), "shared": sel["shared"],
            "estimate": round(spent), "budget": budget, "tree": tree}


def main():
    args = sys.argv[1:]
    top = gw.toplevel() or os.getcwd()
    if "--plan-stop" in args:
        print(json.dumps(plan_stop(top, gw.config(top))))
        return
    if "--from" in args and "--to" in args:
        src = gw.TreeDiff(top, arg("--from", args), arg("--to", args))
    else:
        src = gw.WorkingTree(top, arg("--base", args))
    sel = gw.select(src)
    if "--json" in args:
        print(json.dumps(sel))
    else:
        for f in sel["close"]:
            print(f)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
