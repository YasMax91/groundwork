#!/usr/bin/env python3
"""Groundwork plugin :: a session running an out-of-date hook list says so (wave 43).

Claude Code reads a plugin's hooks/hooks.json, and the hooks modules it names, when a session starts and on
/reload-plugins — nowhere else: /clear and /compact fire SessionStart on the list already loaded, and /reload-plugins
fires no hook at all (2.1.304 and 2.1.308, 2026-10-22). Every hook script is read from disk at each call. A plugin
loaded in place from its folder therefore runs, in a session opened before a release that changed the list, the new
scripts with the old list — a hook added since does not run, a changed one runs with its old arguments — silently.

So the list names itself: its UserPromptSubmit command carries `--registration <id>`, the id of the file's content.
The command line a hook runs with is the list the session loaded; the file on disk is the list now. When their ids
differ — or the command carries none: a list loaded before this existed — the prompt gets a notice for the user and
one for the agent, once per session and id on disk.

    ident <hooks.json>    the id the file's content gives
    check <hooks.json>    exit 1, naming both, when the id the file declares is not its content's
    stamp <hooks.json>    write the content's id into the file's --registration arguments
    warn <plugin> <hooks.json> <loaded id> <marker folder>
                          stdin: the UserPromptSubmit payload; GW_HOOK_OUTPUT: the hook's own stdout. Prints that
                          output with the notice merged in when it is due, unchanged otherwise.

groundwork compares the ids in bash (in-cwd.sh) and starts `warn` only when they differ; follow-through imports a
byte-for-byte copy of this module, as it does gw_repo.py. Any error leaves the hook's output as it was.
"""

import hashlib
import json
import os
import re
import sys
import time

TOKEN = re.compile(r"--registration ([0-9a-f]{1,64})")
SUFFIX = ".registration"


def _read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except Exception:
        return ""


def declared(hooks_json):
    """The id the file's commands carry, "" when none: the list on disk."""
    m = TOKEN.search(_read(hooks_json))
    return m.group(1) if m else ""


def ident(hooks_json):
    """The id the file's content gives: sha256 over the parsed JSON — its ids blanked, keys sorted, no whitespace — and
    the bytes of each hooks module it names; "" when the file is not JSON."""
    try:
        data = json.loads(_read(hooks_json))
    except Exception:
        return ""

    def blank(x):
        if isinstance(x, str):
            return TOKEN.sub("--registration", x)
        if isinstance(x, list):
            return [blank(v) for v in x]
        if isinstance(x, dict):
            return {k: blank(v) for k, v in x.items()}
        return x

    h = hashlib.sha256(json.dumps(blank(data), sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())
    modules = data.get("modules") if isinstance(data, dict) else None
    for name in modules if isinstance(modules, list) else []:
        h.update(b"\0module\0" + str(name).encode() + b"\0")
        try:
            with open(os.path.join(os.path.dirname(os.path.abspath(hooks_json)), str(name)), "rb") as fh:
                h.update(fh.read())
        except Exception:
            h.update(b"\0missing\0")
    return h.hexdigest()[:12]


def stamp(hooks_json):
    """Write the content's id into every --registration argument of the file; the id, "" when there is none to write."""
    new, text = ident(hooks_json), _read(hooks_json)
    if not new or not TOKEN.search(text):
        return ""
    tmp = "%s.%d" % (hooks_json, os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(TOKEN.sub("--registration " + new, text))
    os.replace(tmp, hooks_json)
    return new


def loaded(argv):
    """The id in a hook's own command line: the list the session loaded; "" when the command carries none."""
    for i, a in enumerate(argv[:-1]):
        if a == "--registration":
            return argv[i + 1] if re.fullmatch(r"[0-9a-f]{1,64}", argv[i + 1]) else ""
    return ""


def notice(plugin, loaded_id, disk):
    """(for the user, for the agent)"""
    user = ("%s's hooks changed after this session loaded them, so some of its checks may not run as released. "
            "Run /reload-plugins in this session, or reopen it." % plugin)
    agent = ("{p}: this session runs an out-of-date list of {p}'s hooks — hooks/hooks.json changed after the session "
             "loaded it (loaded: {l}; on disk: {d}). The hook scripts are read from disk at each call, the list only "
             "when a session starts or on /reload-plugins, so until then the new scripts run with the old list: a hook "
             "added since does not run and a changed one runs with its old arguments — checks before a command runs and "
             "at the end of a turn among them. Tell the user in one line, before anything else: run /reload-plugins in "
             "this session, or reopen it. This is said once per change."
             ).format(p=plugin, l=loaded_id or "none, a list from before this check existed", d=disk)
    return user, agent


def merge(output, user, agent):
    """One UserPromptSubmit answer: the notice first, then whatever the hook itself said."""
    out, plain = {}, ""
    text = (output or "").strip()
    if text:
        try:
            parsed = json.loads(text)
        except Exception:
            parsed = None
        if isinstance(parsed, dict):
            out = parsed
        else:
            plain = text                                # plain stdout is context on UserPromptSubmit too
    hso = out.get("hookSpecificOutput") if isinstance(out.get("hookSpecificOutput"), dict) else {}
    own = hso.get("additionalContext") if isinstance(hso.get("additionalContext"), str) else ""
    out["hookSpecificOutput"] = dict(hso, hookEventName="UserPromptSubmit",
                                     additionalContext="\n\n".join(x for x in (agent, own, plain) if x))
    said = out.get("systemMessage") if isinstance(out.get("systemMessage"), str) else ""
    out["systemMessage"] = "\n".join(x for x in (user, said) if x)
    return json.dumps(out, ensure_ascii=False)


def _mark(marker, disk):
    """Remember that the session was told about this list; drop the markers of month-old sessions."""
    try:
        folder = os.path.dirname(marker)
        os.makedirs(folder, exist_ok=True)
        tmp = "%s.%d" % (marker, os.getpid())
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(disk + "\n")
        os.replace(tmp, marker)
        now = time.time()
        for n in os.listdir(folder):
            p = os.path.join(folder, n)
            if n.endswith(SUFFIX) and now - os.path.getmtime(p) > 30 * 86400:
                os.unlink(p)
    except Exception:
        pass


def checked(output, payload, plugin, hooks_json, folder, loaded_id):
    """The hook's output, with the notice merged in when the session runs an out-of-date list and was not told yet.

    Only in a hook process the harness started (CLAUDE_PLUGIN_ROOT set), on UserPromptSubmit, with a session id; the
    marker <folder>/<session id>.registration holds the id on disk the session was last told about."""
    try:
        if not os.environ.get("CLAUDE_PLUGIN_ROOT"):
            return output
        disk = declared(hooks_json)
        if not disk or disk == loaded_id or not isinstance(payload, dict):
            return output
        if payload.get("hook_event_name", "UserPromptSubmit") != "UserPromptSubmit":
            return output
        sid = str(payload.get("session_id") or "")
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", sid):
            return output
        marker = os.path.join(folder, sid + SUFFIX)
        if _read(marker).strip() == disk:
            return output
        _mark(marker, disk)
        return merge(output, *notice(plugin, loaded_id, disk))
    except Exception:
        return output


def main(argv):
    if len(argv) == 2 and argv[0] in ("ident", "check", "stamp"):
        if argv[0] == "stamp":
            new = stamp(argv[1])
            print(new or "%s: no --registration argument to write, or not JSON" % argv[1])
            return 0 if new else 1
        want = ident(argv[1])
        if argv[0] == "ident":
            print(want)
            return 0 if want else 1
        have = declared(argv[1])
        if have and have == want and set(TOKEN.findall(_read(argv[1]))) == {want}:
            print(want)
            return 0
        print("%s declares %s, its content gives %s — run: python3 %s stamp %s"
              % (argv[1], ", ".join(sorted(set(TOKEN.findall(_read(argv[1]))))) or "no id", want or "nothing (not JSON)",
                 os.path.abspath(__file__), argv[1]))
        return 1
    if len(argv) == 5 and argv[0] == "warn":
        output = os.environ.get("GW_HOOK_OUTPUT", "")
        try:
            payload = json.loads(sys.stdin.read() or "{}")
        except Exception:
            payload = {}
        result = checked(output, payload, argv[1], argv[2], argv[4], argv[3])
        if result:
            print(result)
        return 0
    print("usage: gw_registration.py ident|check|stamp <hooks.json> | warn <plugin> <hooks.json> <loaded id> <folder>",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
