#!/usr/bin/env python3
"""follow-through :: PreToolUse(Bash|Edit|Write|MultiEdit) — destructive actions go to the person.

FT-AC8. Every pattern below comes from a real loss in the 2026-10-05 sweep: `migrate:fresh` wiped a
dev database, tests overwrote a working one, `git checkout <file>` destroyed uncommitted edits, an
agent switched off a gate in its project's gate config, `horizon:terminate` left the queue down, `pkill`
dropped a stand.

The verdict is `permissionDecision: "ask"`: the native permission prompt, with the reason on it. It
never allows and never denies — a `deny`/`ask` rule the user wrote still wins, so this can only add a
question, never widen what is permitted.

Wave 41: a git command that discards changes is judged in the working tree it runs in (`cd <lane> &&
git reset --hard`, `git -C <lane> …`), and an edit is checked against the sessions of the tree its file
is in — not the folder the session was opened in.
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
    r"(^|/)\.groundwork\.json$|/\.claude/settings(\.local)?\.json$|"
    r"(^|/)\.claude/follow-through\.json$|/\.claude/hooks/|/\.git/hooks/|/\.husky/"
)
GATE_CONFIG_IN_SHELL = re.compile(
    r"\.groundwork\.json|\.claude/settings(\.local)?\.json|\.claude/follow-through\.json"
)
# A line that can write one — a script may join the folder and the name: `Path(".claude") / "settings.json"`.
GATE_CONFIG_NAMED = re.compile(r"\.groundwork\.json|settings(\.local)?\.json|follow-through\.json")


def dirty(cwd):
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain"],
            capture_output=True, text=True, timeout=3,
        )
        return out.returncode == 0 and bool(out.stdout.strip())
    except Exception:
        return False


DIRTY = "the working tree has uncommitted changes and this git command discards changes"


def discards(g):
    """A parsed git call that discards changes: GIT_DISCARD's forms read from the subcommand and its
    arguments, so `git -C <lane> reset --hard` and `git reset -q --hard` count too."""
    sub, args = g["sub"] or "", [a or "" for a in g["args"]]
    if sub == "checkout":
        return "--" in args or "." in args
    if sub == "restore":
        return "--staged" not in args or "--worktree" in args or "-W" in args
    if sub == "clean":
        return any(a == "--force" or re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", a) for a in args)
    return (sub == "reset" and "--hard" in args) or (sub == "stash" and args[:1] in (["drop"], ["clear"]))


def staged_only(m, text):
    return "restore" in m.group(1) and "--staged" in text and not re.search(r"--worktree|\s-W\b", text)


def switch(top, own, own_on):
    """`gates.destructive` of a tree: the session's own switch for its own tree, that tree's for another."""
    return own_on if top == own else ft.gate_on(ft.config(top), "destructive")


def discard_reason(cmd, cwd, own_on=True):
    """Wave 41: each command that discards changes, in the working tree it runs in, by that tree's switch."""
    if "git" not in cmd:
        return ""
    own, hits = lanes.top_of(cwd), []
    for top, _, c in lanes.call_parts("Bash", {"command": cmd}, cwd):
        m = None if c.git else GIT_DISCARD.search(c.text)      # a git another command runs: find -exec, ssh …
        if (c.git and discards(c.git)) or (m and not staged_only(m, c.text)):
            hits.append((top, c))
    if not hits:
        # What the line does not show as a command — a here-document, a line the parser cannot read.
        m = GIT_DISCARD.search(cmd)
        return DIRTY if own_on and m and not staged_only(m, cmd) and dirty(cwd) else ""
    for top, c in hits:
        if top is None and own_on:
            return ("this git command discards uncommitted changes in a working tree the line does not name (%s) — "
                    "write the path out" % (c.why or "`%s`" % c.text))
        if top and switch(top, own, own_on) and dirty(top):
            return DIRTY if top == own else DIRTY.replace("the working tree", "the working tree " + top, 1)
    return ""


PURGE = re.compile(r"\blane\.py\s+down\b.*--purge")


def reason_for_bash(cmd, cwd, own_on=True):
    """The first reason this line needs the person. Since wave 41 each check holds by the switch of the tree the
    matching command runs in — for a write, the tree of the file it writes — and the session's own switch where
    the line does not say."""
    own, memo = lanes.top_of(cwd), []

    def parts():
        if not memo:
            memo.append(lanes.call_parts("Bash", {"command": cmd}, cwd))
        return memo[0]

    def held(trees):
        return any(switch(t, own, own_on) if t else own_on for t in trees) if trees else own_on

    def on(*patterns):
        return held([top for top, _, c in parts() if any(p.search(c.text) for p in patterns)])

    if MIGRATE.search(cmd) and not TESTING_DB.search(cmd) and on(MIGRATE):
        return "it rebuilds a database that is not the testing one — every row in it is lost"
    if SQL_CLIENT.search(cmd) and SQL_DESTRUCTIVE.search(cmd) and on(SQL_CLIENT, SQL_DESTRUCTIVE):
        return "it drops or truncates data through a database client"
    reason = discard_reason(cmd, cwd, own_on)
    if reason:
        return reason
    if DOCKER_DATA.search(cmd) and on(DOCKER_DATA):
        return "it removes Docker volumes — the databases inside them go with them"
    if PURGE.search(cmd) and on(PURGE):
        return "it drops this lane's databases (dev data cloned into the lane is lost)"
    if PROCESS_KILL.search(cmd) and on(PROCESS_KILL):
        return "it stops processes (workers, servers) that are not restarted by this command"
    if GATE_CONFIG_NAMED.search(cmd):
        # Each command's own words (lanes.written_paths), so `sed -i 's/a|b/c/' .groundwork.json` is one command and
        # no pipe; the line cut on `|` and `;` still answers for what no command shows (a here-document to a shell).
        written = [path for _, _, c in parts() for word, path in lanes.written_paths(c) if GATE_CONFIG_IN_SHELL.search(word)]
        if (written or lanes.shell_writes(cmd, GATE_CONFIG_IN_SHELL)) and \
                held([lanes.top_of(tree_path(p)) if p else "" for p in written]):
            return "it rewrites a gate or permission config — the checks that hold the work"
    return ""


def tree_path(path):
    """A file inside `.git` (a hook) belongs to the tree whose `.git` it is."""
    return path.split(os.sep + ".git" + os.sep)[0] if (os.sep + ".git" + os.sep) in path else path


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse", "permissionDecision": "deny",
        "permissionDecisionReason": "follow-through: " + reason}}, ensure_ascii=False))


def lane_checks(payload, cwd, cfg, tool, data):
    """Wave 35, and since wave 41 in the tree the call works in. Returns True when it answered (denied or
    asked) and the caller must stop."""
    sid = payload.get("session_id") or ""
    if not sid:
        return False
    if tool in ("Edit", "Write", "MultiEdit"):
        return edit_checks(payload, cwd, cfg, sid, str(data.get("file_path") or ""))
    if tool == "Bash":
        return kill_check(payload, cwd, cfg, sid, str(data.get("command") or ""))
    return False


TREE_SHARED = ("another live session (%s, branch %s, task: %s) works in this same tree. Enter your own lane first: "
               "EnterWorktree, then continue there. If the user wants both sessions in one tree, say so and retry — "
               "the next edit passes.")
TREE_OTHER = ("another live session (%s, branch %s, task: %s) works in %s, the tree this file is in. Work in a lane "
              "of your own there (git worktree add), or message that session first — ListAgents, then SendMessage — "
              "and agree who changes what. If the user wants both sessions in that tree, say so and retry — the next "
              "edit there passes.")
OVERLAP = ("%s is being edited by another live session (%s, branch %s, task: %s). Message it first — ListAgents, "
           "then SendMessage with what you intend to change — and agree who changes what. Then retry; the next edit "
           "of this file passes.")


def edit_checks(payload, cwd, cfg, sid, path):
    """The session's own tree, as in wave 35: a live sibling in this same folder is met on the first edit,
    wherever the file is. Since wave 41 also the tree the file is in, when it is another one: its live
    sessions, then the files they edited."""
    path = path if os.path.isabs(path) else os.path.join(cwd, path)
    top, own = lanes.top_of(path), lanes.top_of(cwd)
    if ft.gate_on(cfg, "lanes") and lanes.common_dir(cwd):
        sibs = lanes.siblings(cwd, sid)
        if sibs:
            me = lanes.load(cwd, sid) or lanes.touch(cwd, sid)
            acks = me.setdefault("acks", {"paths": [], "tree": False})
            same_tree = [s for s in sibs if s.get("cwd") == os.path.realpath(cwd)]
            if same_tree and not acks.get("tree"):
                s = same_tree[0]
                acks["tree"] = True
                lanes.save(cwd, sid, me)
                ft.log("lane_tree", payload, path)
                deny(TREE_SHARED % (lanes.who(s), s.get("branch") or "?", s.get("task") or "?"))
                return True
            if top == own:
                return overlap(payload, cwd, sid, me, sibs, top, path, own=True)
    if not top or top == own or not ft.gate_on(cfg if lanes.same_repo(cwd, top) else ft.config(top), "lanes"):
        return False
    sibs = lanes.siblings(top, sid)
    if not sibs:
        return False
    where, me = lanes.entry_for(cwd, sid, top, payload.get("transcript_path") or "")
    acks = me.setdefault("acks", {"paths": [], "tree": False})
    same_tree = [s for s in sibs if s.get("cwd") == top]
    if same_tree and top not in acks.get("trees", []):
        s = same_tree[0]
        acks.setdefault("trees", []).append(top)
        lanes.save(where, sid, me)
        ft.log("lane_tree", payload, path)
        deny(TREE_OTHER % (lanes.who(s), s.get("branch") or "?", s.get("task") or "?", top))
        return True
    return overlap(payload, where, sid, me, sibs, top, path, own=False)


def overlap(payload, where, sid, me, sibs, top, path, own):
    """A file a live sibling edited: denied once, with that sibling's name."""
    rel = lanes.relpath(top, path)
    # A path git ignores (the groundwork checkpoint, a lane's .env, caches) is each worktree's own
    # file: the same relative path in a sibling is a different file. 9 of 9 overlap stops on
    # 2026-10-05/06 were `.claude/groundwork/task-state.md`.
    if not rel or rel.startswith(".claude/") or lanes.ignored_by_git(top, rel):
        return False
    acks = me.setdefault("acks", {"paths": [], "tree": False})
    owners = [s for s in sibs if rel in s.get("files", [])]
    if owners and rel not in acks.get("paths", []):
        s = owners[0]
        acks.setdefault("paths", []).append(rel)
        lanes.save(where, sid, me)
        ft.log("lane_overlap", payload, rel)
        deny(OVERLAP % (rel if own else os.path.join(top, rel), lanes.who(s), s.get("branch") or "?", s.get("task") or "?"))
        return True
    return False


def kill_check(payload, cwd, cfg, sid, cmd):
    """A sibling's container or port named in a stop/kill: the siblings of the session's repository, of the
    trees this line works in, and of the ones the session worked in from outside its folder."""
    if not ft.gate_on(cfg, "lanes") or not re.search(
            r"\b(kill|pkill|killall|docker\s+(stop|kill|rm)|docker(-|\s+)compose\b.*\b(down|stop))\b", cmd):
        return False
    tops = [t for t, _, _ in lanes.call_parts("Bash", {"command": cmd}, cwd) if t]
    sibs, seen = [], set()
    for trees in lanes.by_repo([cwd] + tops + [t for t, _ in lanes.outside_trees(sid)]).values():
        for s in lanes.siblings(trees[0], sid):
            if s.get("session_id") not in seen:
                seen.add(s.get("session_id"))
                sibs.append(s)
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
                "breaks that session's work." % (hit, lanes.who(s))}}, ensure_ascii=False))
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
    own_on = ft.gate_on(cfg, "destructive")      # the session's own switch; another tree has its own (wave 41)
    reason = ""
    if tool == "Bash":
        reason = reason_for_bash(str(data.get("command") or ""), cwd, own_on)
        shown = str(data.get("command") or "")
    elif tool in ("Edit", "Write", "MultiEdit"):
        shown = str(data.get("file_path") or "")
        top = lanes.top_of(tree_path(shown if os.path.isabs(shown) else os.path.join(cwd, shown)))
        if GATE_CONFIG.search(shown) and (switch(top, lanes.top_of(cwd), own_on) if top else own_on):
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
