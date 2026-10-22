#!/usr/bin/env python3
"""Groundwork plugin :: remember what a test run proved, keyed by the exact code it ran on (waves 37-38).

    suite-record.py --record                       the working tree passed the whole suite
    suite-record.py --check REF                    exit 0 when REF's tree (or "WORKTREE") has a whole pass
    suite-record.py --record-run --status N [--junit PATH]   test files on stdin: record the green ones
    (no arguments)                                 PostToolUse(Bash): read what an agent's own run proved

The key is a git tree id built from the working tree (gw_tests.worktree_tree): committing the same content
later yields the same id, and a lane's skip-worktree phpunit.xml takes the committed version, so a green run
in a lane counts for the commit made from it.

An agent's whole-suite run (`artisan test` / `composer test`, no paths, no filter) with a summary and no
failures is a whole pass. An agent's run of named test files or folders with a green summary records those
files as passed on this code, so neither the Stop gate nor the push check repeats them. `--filter` runs are
never recorded: which files they covered is not knowable from the command.

The code a run proved is the tree of the repository the run happened in, read off the line (gw_repo.py,
wave 40): `cd <lane> && ./vendor/bin/sail artisan test` from a session opened in the main checkout used to
record the MAIN checkout's tree as green. A run whose directory the line does not name is not recorded.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_repo as repo  # noqa: E402
import gw_tests as gw  # noqa: E402

FULL = re.compile(r"(artisan\s+test|composer\s+(run\s+)?test)(?![^\n;&|]*(--filter|--group|--testsuite|tests/|\.php\b))")
TARGETED = re.compile(r"(artisan\s+test|vendor/bin/(?:phpunit|pest|paratest))\b([^\n;&|>]*)")
GREEN = re.compile(r"Tests:\s+.*\bpassed\b")


def green_summary(out):
    summary = [l for l in out.splitlines() if l.strip().startswith("Tests:")]
    return bool(summary) and bool(GREEN.search(summary[-1])) and not re.search(r"\b(failed|errors?)\b", summary[-1])


def expand(paths, top, base=None):
    out, real = [], os.path.realpath(top)
    for p in paths:
        full = os.path.realpath(os.path.join(base or top, p))
        if p.endswith(".php") and os.path.isfile(full):
            out.append(os.path.relpath(full, real))
        elif os.path.isdir(full):
            for root, _, names in os.walk(full):
                out += [os.path.relpath(os.path.join(root, n), real) for n in names if n.endswith("Test.php")]
    return sorted(f for f in set(out) if not f.startswith(".."))


def record_run(status, junit, files, top):
    """Record the files a gate/runner run proved green, and fold the JUnit timings into the durations."""
    tree = gw.worktree_tree(top)
    results = gw.junit_results(junit, top) if junit and os.path.isfile(junit) else {}
    if results:
        gw.record_durations({f: r["time"] for f, r in results.items()}, top)
        passed = [f for f in files if f in results and not results[f]["failed"]]
    else:
        passed = list(files) if status == 0 else []
    gw.record_files(tree, passed, top)
    if junit:
        try:
            os.unlink(junit)
        except Exception:
            pass
    return passed


def post_tool():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return
    if payload.get("tool_name") != "Bash":
        return
    cmd = str((payload.get("tool_input") or {}).get("command") or "")
    resp = payload.get("tool_response") or {}
    out = resp if isinstance(resp, str) else (str(resp.get("stdout") or "") + str(resp.get("stderr") or ""))
    if not green_summary(out):
        return
    for c in repo.commands(cmd, payload.get("cwd") or os.getcwd()):
        text = " ".join(a if a is not None else "$?" for a in c.argv)
        full, m = FULL.search(text), TARGETED.search(text)
        if not (full or m):
            continue
        top, known = repo.command_top(c)
        if not known or not top or "$?" in text:
            return                                      # which code ran, or which tests, is unknown: record nothing
        if full:
            gw.record_whole(gw.worktree_tree(top), cwd=top)
            return
        if "--filter" in m.group(2) or any(x in cmd for x in ("$(", "`", "xargs", " < ")):
            return
        files = expand(re.findall(r"(?<!\S)['\"]?(tests/[\w./-]+?)['\"]?(?=\s|$)", m.group(2)), top, c.dir)
        if files:
            gw.record_files(gw.worktree_tree(top), files, top)
        return


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        top = gw.toplevel() or os.getcwd()
        if a[:1] == ["--record"]:
            tree = gw.worktree_tree(top)
            gw.record_whole(tree, cwd=top)
            print(tree)
        elif a[:1] == ["--check"]:
            ref = a[1] if len(a) > 1 else "WORKTREE"
            tree = gw.worktree_tree(top) if ref == "WORKTREE" else gw.ref_tree(ref, top)
            print(tree)
            sys.exit(0 if (tree and gw.whole_pass(tree, top)) else 1)
        elif a[:1] == ["--record-run"]:
            status = int(a[a.index("--status") + 1]) if "--status" in a else 1
            junit = a[a.index("--junit") + 1] if "--junit" in a and a.index("--junit") + 1 < len(a) else ""
            files = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
            print("\n".join(record_run(status, junit, files, top)))
        else:
            post_tool()
    except SystemExit:
        raise
    except Exception:
        pass
    sys.exit(0)
