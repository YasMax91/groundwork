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
    if PROCESS_KILL.search(cmd):
        return "it stops processes (workers, servers) that are not restarted by this command"
    if GATE_CONFIG_IN_SHELL.search(cmd) and SHELL_WRITE.search(cmd):
        return "it rewrites a gate or permission config — the checks that hold the work"
    return ""


def main():
    payload = ft.read_payload()
    if not payload:
        return
    cwd = payload.get("cwd") or os.getcwd()
    cfg = ft.config(cwd)
    if not ft.gate_on(cfg, "destructive"):
        return
    tool = payload.get("tool_name") or ""
    data = payload.get("tool_input") or {}
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
