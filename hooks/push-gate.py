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

Measured before this rule (project A, 2026-10-06 .. 10-21): 51 whole-suite episodes, ~1049 minutes, median 17;
96 of 180 commits on development changed only documents and still needed a whole run each.
The denial names one command, test-run.py --for-push, which runs exactly what is missing and records it.

Each push is judged in the repository it runs in, read off the line itself (gw_repo.py, wave 40): a session
opened in an empty folder pushed `cd <lane> && git push origin HEAD:development` with nothing checked,
because this gate read the session's folder (2026-10-21). A push whose directory the line does not name —
`cd "$LANE" && git push …` — is refused when it may reach a shared branch: which code it pushes is unknown.
Inert outside a Groundwork project and on any error.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_repo as repo  # noqa: E402
import gw_tests as gw  # noqa: E402

PUSH_VALUE = ("--repo", "-o", "--push-option", "--receive-pack", "--exec")


def push_kind(c):
    argv = c.argv or []
    if c.git and c.git["sub"] == "push":                # git itself, or one that sudo / xargs / gtimeout … runs
        return "push"
    if argv and argv[0] and os.path.basename(argv[0]) == "gh" and argv[1:3] == ["pr", "merge"]:
        return "merge"
    return ""


def current_branch(top):
    return gw.git("branch", "--show-current", cwd=top).strip() if top else ""


def default_branch(top):
    """Where a bare `git push` goes: the current branch, or its upstream's under push.default=upstream."""
    if top and gw.git("config", "push.default", cwd=top).strip() == "upstream":
        up = gw.git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}", cwd=top).strip()
        if "/" in up:
            return up.split("/", 1)[1]
    return current_branch(top)


def pushed_refs(args, top):
    """(local ref, remote branch) pairs a `git push` with these arguments would update. The branch is None when
    neither the line nor the repository says (no repository known)."""
    flags, pos, i = set(), [], 0
    while i < len(args):
        a = args[i]
        if a is None:
            pos.append(None)
        elif a == "--":
            pos += args[i + 1:]
            break
        elif a.startswith("--"):
            flags.add(a.split("=", 1)[0])
            if a in PUSH_VALUE:
                i += 1
        elif a.startswith("-") and len(a) > 1:
            flags.update("-" + ch for ch in a[1:])
            if a == "-o":
                i += 1
        else:
            pos.append(a)
        i += 1
    if flags & {"--delete", "-d"}:
        return []                                       # deleting a branch carries no code
    if flags & {"--all", "--mirror", "--branches"}:
        if not top:
            return [("HEAD", None)]
        heads = gw.git("for-each-ref", "--format=%(refname:short)", "refs/heads", cwd=top).split()
        return [(b, b) for b in heads]
    specs = pos[1:]
    if not specs:
        return [] if "--tags" in flags else [("HEAD", (default_branch(top) or None) if top else None)]
    out = []
    for spec in specs:
        if spec is None:
            out.append(("HEAD", None))
            continue
        src, sep, dst = spec.lstrip("+").partition(":")
        if sep and not src:
            continue                                    # `:branch` deletes it
        dst = dst if sep else src
        if src.startswith("refs/tags/") or dst.startswith("refs/tags/"):
            continue
        if dst in ("HEAD", "@"):                        # `git push origin HEAD`: the current branch's name
            dst = (current_branch(top) or None) if top else None
        out.append((src or "HEAD", dst.replace("refs/heads/", "") if dst else None))
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
    home = gw.toplevel(cwd)
    home_cfg = gw.config(home) if home and os.path.isfile(os.path.join(home, ".groundwork.json")) else {}
    runner = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test-run.py")
    problems, unread = [], []
    for c in repo.commands(cmd, cwd):
        kind = push_kind(c)
        if not kind:
            continue
        top, known = repo.command_top(c)
        if not known:
            shared = set(gw.SHARED_BRANCHES) | set(gw.gates(home_cfg).get("shared_branches") or [])
            dsts = [d for _, d in pushed_refs(c.git["args"], "")] if kind == "push" else [None]
            if any(d is None or d in shared for d in dsts):
                unread.append("`%s` — the line does not say which repository it runs in (%s)" % (c.text, c.why))
            continue
        if not top or not os.path.isfile(os.path.join(top, ".groundwork.json")):
            continue
        cfg = gw.config(top)
        if gw.push_mode(cfg) == "off":
            continue
        shared = gw.gates(cfg).get("shared_branches") or gw.SHARED_BRANCHES
        whole_cmd = (cfg.get("commands") or {}).get("test_full") or gw.test_command(cfg)
        if kind == "push":
            # A branch the line does not name (`git push origin "$BR"`) may be a shared one: judged as such.
            targets = [(src, dst or "a branch the line does not name (write it out if it is not a shared one)")
                       for src, dst in pushed_refs(c.git["args"], top) if dst is None or dst in shared]
        else:
            targets = [("HEAD", "the pull request's base")]
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
            problems.append("%s → %s needs %s. Run `cd \"%s\" && python3 \"%s\" --for-push %s` with "
                            "run_in_background: true, wait for its notification, then push again"
                            % (src, dst, what, top, runner, src))
    if not problems and not unread:
        return
    reason = "groundwork push-gate: "
    if unread:
        reason += " | ".join(unread) + (
            ". Which code this pushes is unknown, so nothing could be checked. Repeat the push with the repository's "
            "path written out — `cd /path/to/repo && git push …` or `git -C /path/to/repo push …`.")
    if problems:
        reason += (" | " if unread else "") + " | ".join(problems) + (
            ". The runner records what passed by the exact code, so a commit of the same content still counts. "
            "A feature-branch push needs nothing. (gates.full_suite_before_push: \"always\" demands the whole "
            "suite on every push; false turns this off.)")
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason
    }}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
