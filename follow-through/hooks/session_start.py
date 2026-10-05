#!/usr/bin/env python3
"""follow-through :: SessionStart — register the lane, start it from a fresh base, show the siblings.

Wave 34: tell the agent the formats the Stop gate expects, so the first draft passes.
Wave 35: register this session in the repository's shared registry (LN-AC1), move an empty lane to the
freshest integration branch (LN-AC2), say who else is working here and whether this tree is already
taken (LN-AC4), and list memory facts that point at files which no longer exist (ST-AC7).
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import lanes  # noqa: E402

RULES = """follow-through is active. The turn is checked before it ends:
- Do not end a turn on an announcement ("Беру X", "Next I'll…") — do the step, or say what you wait for.
- Questions to the user go through AskUserQuestion, not prose.
- Do it yourself when you have the access (browser tool, shell, seeded local login). If you cannot, say why on the same line.
- After changing screens (views, CSS, JS, components), take a browser/simulator screenshot before claiming it works — or write "UI не проверен: <screens>".
- Any text the user will forward (client, BA, manager) goes in a ```outbound <addressee> fence: no «—», no lists, no field names or ids, no mention of AI, at most 900 characters, every "cannot/нельзя" about a system sourced with a link. Fence options: lists, max=<n>, ids-ok, ai-ok.
- Destructive commands (migrate:fresh on a non-testing DB, discarding uncommitted git changes, removing Docker volumes, killing workers, editing gate configs) open a permission prompt.
- Parallel sessions: one session per working tree; a file another live session is editing is theirs — message that session (ListAgents → SendMessage) before changing it.
- Status stays current in the same turn: when docs/ai/status.md exists, a commit, merge, push, deploy or closed step updates it (and its `mirror:` artifact); a memory fact your change made wrong is fixed now, not later."""

MEM_TOKEN = re.compile(r"`([A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,5})`")


def memory_dirs(cwd):
    def enc(p):
        return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(p))
    dirs = []
    for root in {cwd, lanes.main_checkout(cwd) or cwd}:
        d = os.path.join(ft.HOME, ".claude", "projects", enc(root), "memory")
        if os.path.isdir(d):
            dirs.append(d)
    return dirs


def stale_memory(cwd):
    """ST-AC7: memory files naming repo paths that no longer exist."""
    roots = [r for r in {lanes.toplevel(cwd), lanes.main_checkout(cwd)} if r]
    found = []
    for d in memory_dirs(cwd):
        for name in sorted(os.listdir(d)):
            if not name.endswith(".md") or name == "MEMORY.md":
                continue
            try:
                text = open(os.path.join(d, name), encoding="utf-8").read()
            except Exception:
                continue
            for path in set(MEM_TOKEN.findall(text)):
                if path.startswith(("/", "~", "http")):
                    continue
                if roots and not any(os.path.exists(os.path.join(r, path)) for r in roots):
                    found.append("%s → `%s`" % (name, path))
    return found[:8]


def main():
    payload = ft.read_payload()
    cwd = payload.get("cwd") or os.getcwd()
    sid = payload.get("session_id") or ""
    cfg = ft.config(cwd)
    parts = [RULES]

    if sid and lanes.common_dir(cwd):
        note = lanes.move_to_base(cwd, lanes.base_ref(cwd, cfg)) if payload.get("source", "startup") == "startup" else ""
        me = lanes.touch(cwd, sid, title=payload.get("session_title") or None, base=lanes.base_ref(cwd, cfg))
        if note:
            parts.append(note)
        block, sig = lanes.awareness(cwd, sid, cfg, me)
        if block:
            parts.append(block)
        me["last_signature"] = sig
        lanes.save(cwd, sid, me)
        if any(s.get("cwd") == os.path.realpath(cwd) for s in lanes.siblings(cwd, sid)):
            parts.append("Another live session already works in THIS tree. Before editing anything, enter your own lane: "
                         "EnterWorktree (the lane is then moved to the fresh base on its first start, and groundwork "
                         "projects get their own stack with `groundwork:lane`). Reading and answering are fine here.")
    stale = stale_memory(cwd)
    if stale:
        parts.append("Memory facts that name files which no longer exist — verify and fix or delete them in this session:\n- "
                     + "\n- ".join(stale))

    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": "\n\n".join(parts)}}, ensure_ascii=False))


if __name__ == "__main__":
    ft.run(main)
