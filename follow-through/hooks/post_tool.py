#!/usr/bin/env python3
"""follow-through :: PostToolUse(Edit|Write|MultiEdit|Bash) — record what this lane touched and deployed.

LN-AC5 needs to know which files each live session is editing; ST-AC5 needs to know what a session
deployed where. Both are written to the shared registry, nothing is returned to the model.

Wave 41: in the repository the call worked in. An edit by absolute path, or a command after `cd <lane>`,
is recorded in that lane's registry — the session appears there, working in the lane, opened elsewhere.
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import lanes  # noqa: E402


def record_deploy(cwd, sid, cmd, parts):
    """In every repository whose status names this deploy (lanes.deploy_targets): the session's own, one the
    line works in, or one the session worked in before from outside its folder — an ssh deploy names no folder.
    The commit recorded is the one of the tree the line works in there, else of the session's tree there."""
    own = lanes.top_of(cwd)
    line_tops = [t for t, _, _ in parts if t]
    roots = []
    for trees in lanes.by_repo([own] + line_tops + [t for t, _ in lanes.outside_trees(sid)]).values():
        current = lanes.current_tree(trees[0], sid)
        roots.append(next((t for t in line_tops + [own, current] + trees if t in trees and lanes.read_status(t)), ""))
    for root, name in lanes.deploy_targets(cmd, parts, roots, own):
        path = os.path.join(lanes.common_dir(root), "follow-through", "deploys.json")
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            data = {}
        data[name] = {"commit": lanes.git(root, "rev-parse", "HEAD"), "time": int(time.time()),
                      "session": sid, "branch": lanes.git(root, "branch", "--show-current")}
        try:
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(data, fh, ensure_ascii=False)
        except Exception:
            pass


def main():
    payload = ft.read_payload()
    cwd = payload.get("cwd") or os.getcwd()
    sid = payload.get("session_id") or ""
    if not sid:
        return
    tool = payload.get("tool_name") or ""
    data = payload.get("tool_input") or {}
    transcript = payload.get("transcript_path") or ""
    if tool in ("Edit", "Write", "MultiEdit"):
        path = str(data.get("file_path") or "")
        path = path if not path or os.path.isabs(path) else os.path.join(cwd, path)
        top = lanes.top_of(path)
        rel = lanes.relpath(top, path) if top else ""
        if not rel or rel.startswith(".claude/") or lanes.ignored_by_git(top, rel):
            return  # a worktree's own file never conflicts with a sibling's
        where, me = lanes.entry_for(cwd, sid, top, transcript)
        if rel not in me.get("files", []):
            me.setdefault("files", []).append(rel)
            me["files"] = me["files"][-200:]
        me["heartbeat"] = int(time.time())
        lanes.save(where, sid, me)
    elif tool == "Bash":
        parts = lanes.call_parts("Bash", data, cwd)
        joined = []
        for top, changes, _ in parts:
            # A command that changes something in another repository keeps this session live there.
            if top and changes and top not in joined and not lanes.same_repo(cwd, top):
                joined.append(top)
                where, me = lanes.entry_for(cwd, sid, top, transcript)
                me["heartbeat"] = int(time.time())
                lanes.save(where, sid, me)
        record_deploy(cwd, sid, str(data.get("command") or ""), parts)
    elif tool == "Artifact":
        # Remember which committed status the mirror now shows, so only a real change asks for a republish.
        own = lanes.top_of(cwd)
        for trees in lanes.by_repo([own] + [t for t, _ in lanes.outside_trees(sid)]).values():
            current = lanes.current_tree(trees[0], sid)
            root = own if own in trees else (current if current in trees else trees[-1])
            base = lanes.base_ref(root, ft.config(cwd if root == own else root))
            mirror = lanes.front_matter(lanes.status_at(root, base) or lanes.read_status(root)).get("mirror")
            if mirror and str(data.get("url") or "").rstrip("/") == mirror.rstrip("/"):
                lanes.record_mirror_published(root, base)


if __name__ == "__main__":
    ft.run(main)
