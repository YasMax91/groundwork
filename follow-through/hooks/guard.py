#!/usr/bin/env python3
"""follow-through :: PreToolUse(Bash|Edit|Write|MultiEdit) — destructive actions go to the person.

FT-AC8. Every pattern below comes from a real loss in the 2026-10-05 sweep: `migrate:fresh` wiped a
dev database, tests overwrote a working one, `git checkout <file>` destroyed uncommitted edits, an
agent switched off a gate in `.company-sdd.json`, `horizon:terminate` left the queue down, `pkill`
dropped a stand.

The verdict is `permissionDecision: "ask"`: the native permission prompt, with the reason on it. It
never allows and never denies — a `deny`/`ask` rule the user wrote still wins, so this can only add a
question, never widen what is permitted.
"""

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import lanes  # noqa: E402

MIGRATE = re.compile(r"\b(migrate:fresh|migrate:reset|migrate:refresh|db:wipe)\b")
TESTING_DB = re.compile(r"--env[= ]testing\b|DB_DATABASE=\S*test|--database[= ]\S*test")
SQL_CLIENT = re.compile(r"\b(mysql|mariadb|psql|sqlite3|tinker|db:query)\b|DB::(statement|unprepared)")
SQL_DESTRUCTIVE = re.compile(r"\b(DROP\s+(DATABASE|TABLE|SCHEMA)|TRUNCATE(\s+TABLE)?)\b", re.I)
GIT_DISCARD = re.compile(
    r"\bgit\s+("
    r"checkout\s+(\S+\s+)?--(\s|$)|checkout\s+\.(\s|$)|"
    r"restore\b|reset\s+--hard\b|clean\s+-\w*f|stash\s+(drop|clear)\b"
    r")"
)
DOCKER_DATA = re.compile(
    r"docker(-|\s+)compose\b[^|;&]*\bdown\b[^|;&]*(\s-v\b|--volumes)|docker\s+volume\s+(rm|prune)\b|docker\s+system\s+prune\b"
)
PROCESS_KILL = re.compile(r"\b(horizon:terminate|pkill|killall)\b|\bkill\s+-(9|KILL)\b")
GATE_CONFIG = re.compile(
    r"(^|/)\.groundwork\.json$|(^|/)\.company-sdd\.json$|/\.claude/settings(\.local)?\.json$|"
    r"(^|/)\.claude/follow-through\.json$|/\.claude/hooks/|/\.git/hooks/|/\.husky/"
)
GATE_CONFIG_IN_SHELL = re.compile(
    r"\.groundwork\.json|\.company-sdd\.json|\.claude/settings(\.local)?\.json|\.claude/follow-through\.json"
)
SHELL_WRITE = re.compile(r"\bsed\s+-i|>\s*\S|\btee\b|\bmv\b|\brm\b|\bcp\b|\bjq\b[^|]*>")


def dirty(cwd):
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain"],
            capture_output=True, text=True, timeout=3,
        )
        return out.returncode == 0 and bool(out.stdout.strip())
    except Exception:
        return False


def reason_for_bash(cmd, cwd):
    if MIGRATE.search(cmd) and not TESTING_DB.search(cmd):
        return "it rebuilds a database that is not the testing one — every row in it is lost"
    if SQL_CLIENT.search(cmd) and SQL_DESTRUCTIVE.search(cmd):
        return "it drops or truncates data through a database client"
    m = GIT_DISCARD.search(cmd)
    if m:
        restore_staged_only = "restore" in m.group(1) and "--staged" in cmd and not re.search(r"--worktree|\s-W\b", cmd)
        if not restore_staged_only and dirty(cwd):
            return "the working tree has uncommitted changes and this git command discards changes"
    if DOCKER_DATA.search(cmd):
        return "it removes Docker volumes — the databases inside them go with them"
    if re.search(r"\blane\.py\s+down\b.*--purge", cmd):
        return "it drops this lane's databases (dev data cloned into the lane is lost)"
    if PROCESS_KILL.search(cmd):
        return "it stops processes (workers, servers) that are not restarted by this command"
    if GATE_CONFIG_IN_SHELL.search(cmd) and SHELL_WRITE.search(cmd):
        return "it rewrites a gate or permission config — the checks that hold the work"
    return ""


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "follow-through: " + reason}}, ensure_ascii=False))


def lane_checks(payload, cwd, cfg, tool, data):
    """Wave 35. Returns True when it answered (denied or asked) and the caller must stop."""
    sid = payload.get("session_id") or ""
    if not sid or not ft.gate_on(cfg, "lanes") or not lanes.common_dir(cwd):
        return False
    sibs = lanes.siblings(cwd, sid)
    if not sibs:
        return False
    if tool in ("Edit", "Write", "MultiEdit"):
        path = str(data.get("file_path") or "")
        rel = lanes.relpath(cwd, path)
        me = lanes.load(cwd, sid) or lanes.touch(cwd, sid)
        acks = me.setdefault("acks", {"paths": [], "tree": False})
        here = os.path.realpath(cwd)
        same_tree = [s for s in sibs if s.get("cwd") == here]
        if same_tree and not acks.get("tree"):
            s = same_tree[0]
            acks["tree"] = True
            lanes.save(cwd, sid, me)
            ft.log("lane_tree", payload, path)
            deny("another live session (%s, branch %s, task: %s) works in this same tree. Enter your own lane first: "
                 "EnterWorktree, then continue there. If the user wants both sessions in one tree, say so and retry — "
                 "the next edit passes." % (s.get("title") or s.get("session_id", "")[:8], s.get("branch") or "?",
                                            s.get("task") or "?"))
            return True
        owners = [s for s in sibs if rel and rel in s.get("files", [])]
        if owners and rel not in acks.get("paths", []):
            s = owners[0]
            acks.setdefault("paths", []).append(rel)
            lanes.save(cwd, sid, me)
            ft.log("lane_overlap", payload, rel)
            deny("%s is being edited by another live session (%s, branch %s, task: %s). Message it first — ListAgents, "
                 "then SendMessage with what you intend to change — and agree who changes what. Then retry; the next edit "
                 "of this file passes." % (rel, s.get("title") or s.get("session_id", "")[:8], s.get("branch") or "?",
                                           s.get("task") or "?"))
            return True
    if tool == "Bash":
        cmd = str(data.get("command") or "")
        if re.search(r"\b(kill|pkill|killall|docker\s+(stop|kill|rm)|docker(-|\s+)compose\b.*\b(down|stop))\b", cmd):
            for s in sibs:
                names = [str(c) for c in s.get("containers", [])] + [str(p) for p in s.get("ports", [])]
                try:
                    with open(os.path.join(s.get("cwd", ""), ".claude", "lane.json"), encoding="utf-8") as fh:
                        lane = json.load(fh)
                    names += [str(c) for c in lane.get("containers", [])] + [str(p) for p in lane.get("ports", [])]
                    names.append(str(lane.get("compose_project") or ""))
                except Exception:
                    pass
                hit = next((n for n in names if n and re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(n), cmd)), None)
                if hit:
                    ft.log("lane_kill", payload, cmd)
                    print(json.dumps({"hookSpecificOutput": {
                        "hookEventName": "PreToolUse", "permissionDecision": "ask",
                        "permissionDecisionReason": "follow-through: «%s» belongs to another live session (%s) — stopping it "
                        "breaks that session's work." % (hit, s.get("title") or s.get("session_id", "")[:8])}},
                        ensure_ascii=False))
                    return True
    return False


def main():
    payload = ft.read_payload()
    if not payload:
        return
    cwd = payload.get("cwd") or os.getcwd()
    cfg = ft.config(cwd)
    tool = payload.get("tool_name") or ""
    data = payload.get("tool_input") or {}
    if lane_checks(payload, cwd, cfg, tool, data):
        return
    if not ft.gate_on(cfg, "destructive"):
        return
    reason = ""
    if tool == "Bash":
        reason = reason_for_bash(str(data.get("command") or ""), cwd)
        shown = str(data.get("command") or "")
    elif tool in ("Edit", "Write", "MultiEdit"):
        shown = str(data.get("file_path") or "")
        if GATE_CONFIG.search(shown):
            reason = "it changes a gate or permission config — the checks that hold the work"
    if not reason:
        return
    ft.log("destructive", payload, shown)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "follow-through: " + reason + ". Confirm only if you asked for exactly this.",
        }
    }, ensure_ascii=False))


if __name__ == "__main__":
    ft.run(main)
