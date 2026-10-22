#!/usr/bin/env python3
"""follow-through :: UserPromptSubmit — keep the lane's registry entry alive and the siblings visible.

LN-AC1: the awareness block is injected again only when something changed — a sibling started, moved
or stopped, the base moved, a deploy happened — so an unchanged state costs no context. The base is
fetched at most every five minutes, so drift is measured against the remote, not a stale local ref.

Wave 43: `--registration <id>` is the id of the hooks.json this session loaded. When the file on disk carries
another one, or the command carries none, the answer says once that the session runs an out-of-date list of
follow-through's hooks (gw_registration.py) — in every session, a folder outside git included.
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import gw_registration  # noqa: E402
import lanes  # noqa: E402

FETCH_EVERY = 5 * 60
HOOKS_JSON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hooks.json")


def awareness(payload):
    """The «what changed around you» answer, "" when nothing changed or the folder is no lane."""
    cwd = payload.get("cwd") or os.getcwd()
    sid = payload.get("session_id") or ""
    if not sid or not lanes.common_dir(cwd):
        return ""
    cfg = ft.config(cwd)
    me = lanes.load(cwd, sid)
    task = me.get("task") or (payload.get("prompt") or "").strip().replace("\n", " ")[:140]
    base = lanes.base_ref(cwd, cfg)
    if base and time.time() - float(me.get("fetched", 0)) > FETCH_EVERY:
        lanes.git(cwd, "fetch", "--quiet", "origin", timeout=8)
        me["fetched"] = int(time.time())
        lanes.save(cwd, sid, me)
    me = lanes.touch(cwd, sid, task=task, base=base)
    block, sig = lanes.awareness(cwd, sid, cfg, me)
    if sig == me.get("last_signature"):
        return ""
    me["last_signature"] = sig
    lanes.save(cwd, sid, me)
    if not block:
        return ""
    return json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                              "additionalContext": "follow-through, what changed around you:\n" + block}},
                      ensure_ascii=False)


def main():
    payload = ft.read_payload()
    try:
        out = awareness(payload)
    except Exception:
        out = ""
    out = gw_registration.checked(out, payload, "follow-through", HOOKS_JSON,
                                  os.path.join(ft.HOME, ".claude", "follow-through", "registration"),
                                  gw_registration.loaded(sys.argv[1:]))
    if out:
        print(out)


if __name__ == "__main__":
    ft.run(main)
