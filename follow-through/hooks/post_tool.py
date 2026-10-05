#!/usr/bin/env python3
"""follow-through :: PostToolUse(Edit|Write|MultiEdit|Bash) — record what this lane touched and deployed.

LN-AC5 needs to know which files each live session is editing; ST-AC5 needs to know what a session
deployed where. Both are written to the shared registry, nothing is returned to the model.
"""

import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import lanes  # noqa: E402


def record_deploy(cwd, sid, cmd):
    root = lanes.toplevel(cwd) or cwd
    envs = (lanes.front_matter(lanes.read_status(root)).get("environments") or {})
    for name, spec in envs.items():
        pattern = spec.get("deploy_cmd")
        if not pattern:
            continue
        try:
            hit = re.search(pattern, cmd)
        except re.error:
            hit = pattern in cmd
        if not hit:
            continue
        path = os.path.join(lanes.common_dir(cwd), "follow-through", "deploys.json")
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            data = {}
        data[name] = {"commit": lanes.git(cwd, "rev-parse", "HEAD"), "time": int(time.time()),
                      "session": sid, "branch": lanes.git(cwd, "branch", "--show-current")}
        try:
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh, ensure_ascii=False)
        except Exception:
            pass


def main():
    payload = ft.read_payload()
    cwd = payload.get("cwd") or os.getcwd()
    sid = payload.get("session_id") or ""
    if not sid or not lanes.common_dir(cwd):
        return
    tool = payload.get("tool_name") or ""
    data = payload.get("tool_input") or {}
    if tool in ("Edit", "Write", "MultiEdit"):
        rel = lanes.relpath(cwd, str(data.get("file_path") or ""))
        if not rel:
            return
        me = lanes.load(cwd, sid) or lanes.touch(cwd, sid)
        if rel not in me.get("files", []):
            me.setdefault("files", []).append(rel)
            me["files"] = me["files"][-200:]
        me["heartbeat"] = int(time.time())
        lanes.save(cwd, sid, me)
    elif tool == "Bash":
        record_deploy(cwd, sid, str(data.get("command") or ""))


if __name__ == "__main__":
    ft.run(main)
