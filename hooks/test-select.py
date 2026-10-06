#!/usr/bin/env python3
"""Groundwork plugin :: which tests does this change touch? (wave 37)

    python3 test-select.py [--base <ref>]        prints one test file per line, then exits 0

The Stop gate used to run the whole suite whenever PHP had changed since the last push: in otaje that was
79 runs in a week, 383 minutes of waiting, a median of 5.4 minutes each — for changes whose own tests were
a handful of files (median 2 of 647 over the last commits). The whole suite now runs once, before a push
to a shared branch (push-gate.py); while working, the gate runs what this script selects:

  * every changed test file;
  * tests that name a changed class (its basename as a word);
  * for a migration — tests that name the tables it creates or alters;
  * for config/<name>.php — tests that read `<name>.` keys;
  * for a routes file — tests that name its route names or URIs.

"Changed" = uncommitted, untracked, and committed-but-not-pushed (the same set the gates use), so a task's
own work stays covered until it is pushed. Nothing selectable → nothing printed, and the gate says so.
"""

import os
import re
import subprocess
import sys


def git(*args):
    try:
        r = subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=20)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def changed_files(base=None):
    files = set(git("diff", "--name-only", "HEAD").split())
    files |= set(git("ls-files", "--others", "--exclude-standard").split())
    upstream = base or git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}").strip()
    if upstream:
        files |= set(git("diff", "--name-only", "%s...HEAD" % upstream).split())
    return sorted(f for f in files if os.path.isfile(f))


def read(path):
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            return fh.read()
    except Exception:
        return ""


def test_files():
    out = []
    for root, _, names in os.walk("tests"):
        for n in names:
            if n.endswith("Test.php"):
                out.append(os.path.join(root, n))
    return sorted(out)


def needles_for(path):
    """Words a test would contain if it exercised `path`."""
    text = read(path)
    words = set()
    if path.startswith("database/migrations/"):
        words |= set(re.findall(r"Schema::(?:create|table|rename|dropIfExists|drop)\(\s*['\"]([a-z0-9_]+)['\"]", text))
    elif path.startswith("config/") and path.endswith(".php"):
        words.add(os.path.basename(path)[:-4] + ".")
    elif path.startswith("routes/"):
        words |= set(re.findall(r"->name\(\s*['\"]([\w.-]+)['\"]", text))
        words |= {u.strip("/") for u in re.findall(r"Route::\w+\(\s*['\"](/?[\w/{}-]{4,})['\"]", text) if "{" not in u}
    elif path.endswith(".php"):
        words.add(os.path.basename(path)[:-4])
    return {w for w in words if len(w) >= 3}


def select(files):
    tests = test_files()
    chosen = {f for f in files if f.startswith("tests/") and f.endswith("Test.php")}
    needles = set()
    for f in files:
        if not f.startswith("tests/"):
            needles |= needles_for(f)
    if not needles:
        return sorted(chosen)
    patterns = [re.compile(r"(?<![\w$])%s(?![\w])" % re.escape(n)) if not n.endswith(".") else re.compile(re.escape(n))
                for n in needles]
    for t in tests:
        body = read(t)
        if any(p.search(body) for p in patterns):
            chosen.add(t)
    return sorted(chosen)


def main():
    args = sys.argv[1:]
    base = args[args.index("--base") + 1] if "--base" in args and args.index("--base") + 1 < len(args) else None
    for f in select(changed_files(base)):
        print(f)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
