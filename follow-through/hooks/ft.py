"""follow-through :: shared helpers for every hook in this plugin.

Fail-safe contract, identical to groundwork's: a hook built on this module must never break a tool
call or a turn on its own bug. Every public helper swallows its own errors and returns an empty value;
the entry points wrap `main()` in `run()`, which turns any exception into a silent allow.
"""

import json
import os
import re
import sys
import time

HOME = os.path.expanduser("~")
LOG_PATH = os.path.join(HOME, ".claude", "follow-through", "triggers.log")

DEFAULTS = {
    "gates": {
        "announce_stop": True,
        "empty_reply": True,
        "prose_question": True,
        "hand_back": True,
        "language": True,
        "outbound": True,
        "ui_proof": True,
        "destructive": True,
        "lanes": True,
        "freshness": True,
        "status": True,
    },
    # None = detect from CLAUDE.md; "ru" / "uk" / "off" to force.
    "chat_language": None,
    "outbound_max": 900,
}


def read_payload():
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def _load_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def config(cwd):
    """Defaults < ~/.claude/follow-through.json < <project>/.claude/follow-through.json."""
    cfg = json.loads(json.dumps(DEFAULTS))
    for layer in (
        _load_json(os.path.join(HOME, ".claude", "follow-through.json")),
        _load_json(os.path.join(cwd or ".", ".claude", "follow-through.json")),
    ):
        for key, value in layer.items():
            if key == "gates" and isinstance(value, dict):
                cfg["gates"].update({k: bool(v) for k, v in value.items()})
            else:
                cfg[key] = value
    return cfg


def gate_on(cfg, name):
    return bool(cfg.get("gates", {}).get(name, True))


def log(gate, payload, excerpt):
    """One line per trigger. The log is what the thresholds are tuned from; a failed write never
    costs the verdict."""
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        line = "\t".join(
            [
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                os.path.basename(payload.get("cwd") or os.getcwd()),
                str(payload.get("session_id") or "unknown"),
                gate,
                re.sub(r"[\t\n\r]+", " ", excerpt or "")[:160],
            ]
        )
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except Exception:
        pass


# --- transcript ---------------------------------------------------------------------------------

def _is_genuine_user(entry):
    """A message the person typed — not a tool result, not a meta/hook injection, not a
    background-task notification."""
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isSidechain"):
        return None
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, list):
        if any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content):
            return None
        content = " ".join(
            c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"
        )
    if not isinstance(content, str):
        return None
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", content, flags=re.S).strip()
    if not text or text.startswith(("<task-notification", "<command-", "<local-command", "Caveat:")):
        return None
    return text


def current_turn(transcript_path):
    """(last user text, [tool_use dicts in order]) for the turn that is ending.

    The turn starts at the last message the person typed. Tool uses are collected from the main
    thread only."""
    user_text, tools = "", []
    try:
        with open(transcript_path, encoding="utf-8", errors="ignore") as fh:
            lines = fh.readlines()
    except Exception:
        return user_text, tools
    for line in lines:
        try:
            entry = json.loads(line)
        except Exception:
            continue
        text = _is_genuine_user(entry)
        if text is not None:
            user_text, tools = text, []
            continue
        if entry.get("type") != "assistant" or entry.get("isSidechain"):
            continue
        content = (entry.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_use":
                tools.append({"name": item.get("name", ""), "input": item.get("input") or {}})
    return user_text, tools


def run(main):
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        pass
    sys.exit(0)
