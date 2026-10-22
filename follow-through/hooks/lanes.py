"""follow-through :: the session registry, the integration base, and the status file (wave 35).

Everything a lane needs to know about its siblings lives under `<git-common-dir>/follow-through/` —
one directory shared by every worktree of a repository and never committed. Every helper is
fail-safe: an error returns an empty value, never an exception.
"""

import hashlib
import json
import os
import re
import subprocess
import time

import ft

try:
    import gw_repo  # groundwork's reader of a Bash line, copied byte for byte (wave 41)
except Exception:
    gw_repo = None

LIVE_SECONDS = 30 * 60
FORGET_SECONDS = 24 * 60 * 60
STATUS_REL = os.path.join("docs", "ai", "status.md")


# --- git ----------------------------------------------------------------------------------------

def git(cwd, *args, timeout=5):
    try:
        out = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


_COMMON = {}


def common_dir(cwd):
    if cwd not in _COMMON:
        d = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
        _COMMON[cwd] = d if d and os.path.isdir(d) else ""
    return _COMMON[cwd]


def toplevel(cwd):
    return git(cwd, "rev-parse", "--show-toplevel")


def main_checkout(cwd):
    d = common_dir(cwd)
    return os.path.dirname(d) if d.endswith(os.sep + ".git") or d.endswith("/.git") else ""


def is_worktree(cwd):
    gd = git(cwd, "rev-parse", "--path-format=absolute", "--git-dir")
    cd = common_dir(cwd)
    return bool(gd and cd and os.path.realpath(gd) != os.path.realpath(cd))


def base_ref(cwd, cfg):
    """The integration branch: configured, else origin/development, else origin/HEAD."""
    configured = (cfg or {}).get("base_branch")
    if configured:
        ref = configured if configured.startswith("origin/") else "origin/" + configured
        return ref if git(cwd, "rev-parse", "--verify", "-q", ref) else ""
    if git(cwd, "rev-parse", "--verify", "-q", "refs/remotes/origin/development"):
        return "origin/development"
    head = git(cwd, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    return head or ""


def own_commit_count(cwd):
    """Commits on HEAD that no remote branch has — the lane's own work."""
    n = git(cwd, "rev-list", "--count", "HEAD", "--not", "--remotes")
    return int(n) if n.isdigit() else -1


def tracked_clean(cwd):
    return git(cwd, "status", "--porcelain", "--untracked-files=no") == "" and git(cwd, "rev-parse", "HEAD") != ""


def move_to_base(cwd, base):
    """LN-AC2: an empty lane starts from the freshest integration branch. Returns a note or ''."""
    if not base or not is_worktree(cwd):
        return ""
    if own_commit_count(cwd) != 0 or not tracked_clean(cwd):
        return ""
    branch = base.split("/", 1)[1] if "/" in base else base
    git(cwd, "fetch", "--quiet", "origin", branch, timeout=25)
    head, target = git(cwd, "rev-parse", "HEAD"), git(cwd, "rev-parse", base)
    if not target or head == target:
        return ""
    try:
        if subprocess.run(["git", "-C", cwd, "merge-base", "--is-ancestor", target, "HEAD"],
                          capture_output=True, timeout=5).returncode == 0:
            return ""  # HEAD already contains the base
    except Exception:
        return ""
    r = subprocess.run(["git", "-C", cwd, "reset", "--keep", base], capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        return ""
    return "This lane had no commits of its own, so it was moved to the freshest %s (%s)." % (base, target[:8])


def base_drift(cwd, base, my_files):
    """LN-AC3: commits on the base since this lane forked, and the ones touching my files."""
    if not base:
        return 0, [], []
    mb = git(cwd, "merge-base", "HEAD", base)
    if not mb:
        return 0, [], []
    log = git(cwd, "log", "--format=%h %s", "%s..%s" % (mb, base))
    commits = [l for l in log.splitlines() if l.strip()]
    if not commits:
        return 0, [], []
    changed = set(git(cwd, "diff", "--name-only", mb, base).splitlines())
    mine = set(my_files) | set(git(cwd, "diff", "--name-only", mb, "HEAD").splitlines())
    return len(commits), commits[:5], sorted(changed & mine)


# --- registry -----------------------------------------------------------------------------------

def registry_dir(cwd, create=True):
    cd = common_dir(cwd)
    if not cd:
        return ""
    d = os.path.join(cd, "follow-through", "sessions")
    if not create:
        return d if os.path.isdir(d) else ""
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        return ""
    return d


def _path(cwd, sid):
    d = registry_dir(cwd)
    return os.path.join(d, re.sub(r"[^A-Za-z0-9_-]", "_", sid) + ".json") if d and sid else ""


def load(cwd, sid):
    p = _path(cwd, sid)
    try:
        with open(p, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def save(cwd, sid, entry):
    p = _path(cwd, sid)
    if not p:
        return
    try:
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(entry, fh, ensure_ascii=False)
        os.replace(tmp, p)
    except Exception:
        pass


def touch(cwd, sid, **fields):
    """Create or refresh this session's entry; returns it."""
    entry = load(cwd, sid) or {
        "session_id": sid, "started": int(time.time()), "files": [], "ports": [],
        "containers": [], "acks": {"paths": [], "tree": False}, "task": "",
    }
    entry.update({k: v for k, v in fields.items() if v is not None})
    entry["cwd"] = os.path.realpath(cwd)
    entry["branch"] = git(cwd, "branch", "--show-current") or entry.get("branch", "")
    entry["heartbeat"] = int(time.time())
    save(cwd, sid, entry)
    return entry


def remove(cwd, sid):
    try:
        os.remove(_path(cwd, sid))
    except Exception:
        pass


def siblings(cwd, sid):
    """Live entries of other sessions in this repository; forgets very old ones."""
    d = registry_dir(cwd, create=False)
    out, now = [], time.time()
    if not d:
        return out
    for name in os.listdir(d):
        if not name.endswith(".json"):
            continue
        p = os.path.join(d, name)
        try:
            with open(p, encoding="utf-8") as fh:
                e = json.load(fh)
        except Exception:
            continue
        age = now - float(e.get("heartbeat", 0))
        if age > FORGET_SECONDS:
            try:
                os.remove(p)
            except Exception:
                pass
            continue
        if e.get("session_id") == sid or age > LIVE_SECONDS:
            continue
        out.append(e)
    return out


def relpath(cwd, path):
    top = toplevel(cwd) or cwd
    try:
        rp = os.path.relpath(os.path.realpath(path), os.path.realpath(top))
    except Exception:
        return ""
    return "" if rp.startswith("..") else rp


def who(s):
    """A sibling as a message names it: its title or id, and the folder it was opened in when it works
    in this repository from outside it."""
    name = s.get("title") or s.get("session_id", "")[:8]
    return name + (" (opened in %s)" % os.path.basename(s["opened_in"]) if s.get("opened_in") else "")


# --- where a call works (wave 41) -----------------------------------------------------------------
# A session need not be opened in the repository it works in: it can `cd <lane> && git commit`, call
# `git -C <lane>`, or edit a file there by absolute path. Every hook used to judge the session's own
# folder, so on 2026-10-21 a session opened in an empty folder worked in a project A lane and no
# follow-through gate saw it. A call is now judged in the working tree each of its parts works in.

EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")


def top_of(path):
    """The working tree a file or directory belongs to, as a real path; '' outside git."""
    top = gw_repo.toplevel(path) if gw_repo and path else ""
    return os.path.realpath(top) if top else ""


def same_repo(a, b):
    """Two directories share one repository — its git common dir, and so its registry."""
    ca, cb = common_dir(a), common_dir(b)
    return bool(ca and cb) and os.path.realpath(ca) == os.path.realpath(cb)


def call_parts(tool, inp, cwd):
    """[(tree, changes, command)] for every part of a Bash / Edit / Write call: the working tree it works
    in ('' outside git, None when the line does not say — `cd "$X"` with X set elsewhere), whether it may
    change anything, and the parsed simple command (None for an edit). A `cd` is left out: it runs in the
    folder it leaves."""
    if tool in EDIT_TOOLS:
        path = str(inp.get("file_path") or inp.get("notebook_path") or "")
        path = path if not path or os.path.isabs(path) else os.path.join(cwd, path)
        return [(top_of(path), True, None)] if path else []
    if tool != "Bash" or not gw_repo:
        return []
    out = []
    for c in gw_repo.commands(str(inp.get("command") or ""), cwd):
        if c.argv and c.argv[0] and os.path.basename(c.argv[0]) in ("cd", "pushd", "popd"):
            continue
        top, known = gw_repo.command_top(c)
        out.append(((os.path.realpath(top) if top else "") if known else None, gw_repo.writes(c), c))
    return out


def by_repo(tops):
    """{repository: [working trees]}, in first-seen order: the worktrees of one repository share its
    registry and its plan."""
    out = {}
    for t in tops:
        cd = common_dir(t) if t else ""
        if cd and t not in out.setdefault(os.path.realpath(cd), []):
            out[os.path.realpath(cd)].append(t)
    return out


# The trees in other repositories a session works in: `~/.claude/follow-through/outside/<session>.jsonl`,
# one line per tree. SessionEnd takes the session out of those registries; the Stop gate reads them.

def _outside_file(sid):
    sid = re.sub(r"[^A-Za-z0-9_-]", "_", sid or "")
    return os.path.join(ft.HOME, ".claude", "follow-through", "outside", sid + ".jsonl") if sid else ""


def outside_trees(sid):
    """[(tree, git common dir)] this session works in outside the repository of its folder, oldest first."""
    out = []
    try:
        with open(_outside_file(sid), encoding="utf-8") as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if isinstance(e, dict) and e.get("top") and e["top"] not in [t for t, _ in out]:
                    out.append((e["top"], e.get("common") or ""))
    except Exception:
        pass
    return out


def remember_outside(sid, top):
    f = _outside_file(sid)
    if not f or any(t == top for t, _ in outside_trees(sid)):
        return
    try:
        os.makedirs(os.path.dirname(f), exist_ok=True)
        first = not os.path.exists(f)
        with open(f, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"top": top, "common": common_dir(top), "time": int(time.time())}) + "\n")
        if first:                                       # a new session: drop the lists of month-old ones
            for n in os.listdir(os.path.dirname(f)):
                p = os.path.join(os.path.dirname(f), n)
                if n.endswith(".jsonl") and time.time() - os.path.getmtime(p) > 30 * 86400:
                    os.unlink(p)
    except Exception:
        pass


def forget_outside(sid):
    """SessionEnd: take this session out of every other repository's registry, then drop its list."""
    for _, common in outside_trees(sid):
        try:
            os.remove(os.path.join(common, "follow-through", "sessions",
                                   re.sub(r"[^A-Za-z0-9_-]", "_", sid) + ".json"))
        except Exception:
            pass
    try:
        os.remove(_outside_file(sid))
    except Exception:
        pass


def current_tree(top, sid):
    """The tree this session last worked in, in the repository of `top`, by its registry entry; '' when it
    has none (and no registry directory is made to find out)."""
    if not sid or not registry_dir(top, create=False):
        return ""
    return load(top, sid).get("cwd") or ""


def written_paths(c):
    """[(word, path)] the files a parsed command writes — a redirect, `tee`, `sed -i`, `rm`, `truncate`, the
    destination of `mv` / `cp` / `install` (shell_writes' rules, read from the command's own words, so a `|`
    inside a quoted sed script is no pipe); the path absolute, or None where the command's folder is unknown."""
    words = [a or "" for a in c.argv]
    words = words[1:] if words[:1] == ["sudo"] else words
    name = os.path.basename(words[0]) if words else ""
    found = [o for o in c.outputs if o not in ("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty")]
    if name in ("tee", "rm", "truncate") or (name == "sed" and any(w.startswith("-i") for w in words[1:])):
        found += words[1:]
    elif name in ("mv", "cp", "install"):
        found += words[-1:]                             # only the destination is written
    return [(w, w if os.path.isabs(w) else (os.path.join(c.dir, w) if c.dir else None)) for w in found if w]


# Commands that act on another machine: a deploy through them runs from no tree here.
REACHES_OUT = frozenset("""
ssh scp sftp mosh docker podman kubectl helm gh curl wget http https aws gcloud az fly flyctl heroku vercel netlify
ansible ansible-playbook
""".split())


def deploy_place(c, top):
    """The tree a command deploys from: the one its script is in (`./deploy.sh`, `/srv/app/deploy.sh`), the one
    it runs in for a local tool (make, npm, rsync, envoy …); '' for one that reaches another machine (ssh, curl,
    gh …), runs outside git, or runs where the line does not say."""
    name = c.argv[0] if c.argv and c.argv[0] else ""
    if os.path.basename(name) in REACHES_OUT:
        return ""
    if "/" in name:
        p = name if os.path.isabs(name) else (os.path.join(c.dir, name) if c.dir else "")
        return top_of(p) if p else ""
    return top or ""


def deploy_targets(line, parts, roots, own):
    """[(root, environment)] a Bash line deploys, by the `deploy_cmd` of each repository's status (`roots`: one
    tree per repository). The session's own repository reads the whole line, as before. Another one counts a
    command its pattern names when the command deploys from it, or deploys from no tree here (ssh, curl, gh …)
    and the session's own pattern does not name it — never a script of a third repository that matches too."""
    envs = {r: front_matter(read_status(r)).get("environments") or {} for r in roots if r}

    def named(r, text):
        out = []
        for name, spec in envs[r].items():
            try:
                if spec.get("deploy_cmd") and re.search(spec["deploy_cmd"], text):
                    out.append(name)
            except re.error:
                pass
        return out

    mine = next((r for r in envs if own and same_repo(r, own)), "")
    out = [(mine, n) for n in named(mine, line)] if mine else []
    for r in envs:
        if r == mine:
            continue
        names = []
        for top, _, c in parts:
            if named(r, c.text):
                place = deploy_place(c, top)
                if (place and same_repo(place, r)) or (not place and not (mine and named(mine, c.text))):
                    names += [n for n in named(r, c.text) if n not in names]
        if not names and named(r, line):                # a pattern that spans commands
            places = [p for p in (deploy_place(c, top) for top, _, c in parts) if p]
            if any(same_repo(p, r) for p in places) or (not places and not (mine and named(mine, line))):
                names = named(r, line)
        out += [(r, n) for n in names]
    return out


def entry_for(cwd, sid, top, transcript=""):
    """(where, entry): the registry entry this session keeps for working tree `top`, and the directory it
    is saved through. In the repository of the session's folder that is its own entry. In another one it
    is an entry in that repository's registry — `cwd` the tree it works in, `opened_in` its own folder, the
    task its first prompt — so the sessions there see it; it is remembered for SessionEnd."""
    if same_repo(cwd, top):
        return cwd, (load(cwd, sid) or touch(cwd, sid))
    e = load(top, sid)
    if e.get("cwd") != top:
        e = touch(top, sid, opened_in=os.path.realpath(cwd), task=e.get("task") or ft.first_prompt(transcript))
    remember_outside(sid, top)
    return top, e


# --- the status file (Layer C) ------------------------------------------------------------------

def read_status(root):
    try:
        with open(os.path.join(root, STATUS_REL), encoding="utf-8") as fh:
            return fh.read()
    except Exception:
        return ""


def front_matter(text):
    """A two-level YAML subset: `key: value`, and `environments:` with indented maps."""
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        return {}
    out, env, cur = {}, {}, None
    for line in m.group(1).splitlines():
        if not line.strip() or line.strip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        key, _, val = line.strip().partition(":")
        val = val.strip().strip('"').strip("'")
        if indent == 0:
            cur = None
            if key == "environments":
                out["environments"] = env
            else:
                out[key] = val
        elif indent <= 4 and not val and "environments" in out:
            cur = key
            env[cur] = {}
        elif cur:
            env[cur][key] = val
    return out


def doing_rows(text):
    rows = []
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[2].lower() == "doing":
            rows.append("%s %s" % (cells[0], cells[1][:70]))
    return rows


def environments_view(cwd, base, fm):
    lines = []
    deploys = {}
    cd = common_dir(cwd)
    try:
        with open(os.path.join(cd, "follow-through", "deploys.json"), encoding="utf-8") as fh:
            deploys = json.load(fh)
    except Exception:
        pass
    for name, spec in (fm.get("environments") or {}).items():
        parts = [name + ":"]
        branch = spec.get("branch")
        if branch:
            sha = git(cwd, "rev-parse", "--short", branch)
            behind = git(cwd, "rev-list", "--count", "%s..%s" % (branch, base)) if base and sha else ""
            parts.append("%s @ %s" % (branch, sha or "?") + (", %s commits behind %s" % (behind, base) if behind else ""))
        last = deploys.get(name)
        if last:
            parts.append("last deploy by a session: %s at %s" % (last.get("commit", "?")[:8],
                         time.strftime("%Y-%m-%d %H:%M", time.localtime(last.get("time", 0)))))
        if spec.get("version_url"):
            parts.append("live version: " + spec["version_url"])
        lines.append(" ".join(parts))
    return lines


# --- the awareness block (LN-AC1, LN-AC3, ST-AC4, ST-AC5) -----------------------------------------

def awareness(cwd, sid, cfg, me):
    base = base_ref(cwd, cfg)
    sibs = siblings(cwd, sid)
    n, subjects, touching = base_drift(cwd, base, me.get("files", []))
    root = toplevel(cwd) or cwd
    fm = front_matter(read_status(root))
    envs = environments_view(cwd, base, fm)

    lines = []
    for s in sibs:
        mins = int((time.time() - s.get("heartbeat", 0)) / 60)
        where = "same tree as you" if s.get("cwd") == os.path.realpath(cwd) else os.path.basename(s.get("cwd", ""))
        lines.append("- %s · branch %s · %s · %d files edited · active %d min ago%s" % (
            who(s), s.get("branch") or "?", where,
            len(s.get("files", [])), mins, (" · task: " + s["task"]) if s.get("task") else ""))
        for row in doing_rows(read_status(s.get("cwd", "")))[:3]:
            lines.append("    doing: " + row)
    text = []
    if lines:
        text.append("Other live sessions in this repository (message them with ListAgents → SendMessage before touching their work):")
        text += lines
    if n:
        text.append("The base %s moved by %d commits since this lane forked%s:" % (
            base, n, ("; %d touch files you changed: %s" % (len(touching), ", ".join(touching[:6]))) if touching else ""))
        text += ["    " + c for c in subjects]
    if envs:
        text.append("Environments: " + " | ".join(envs))
    signature = hashlib.sha1(json.dumps([lines, n, touching, envs]).encode()).hexdigest()
    return "\n".join(text), signature


# --- does a shell command WRITE a file? (wave 36) -------------------------------------------------
# The first version asked "does the command mention the file and contain a `>` anywhere", so
# `cat .groundwork.json 2>/dev/null` opened a permission prompt and `grep … status.md 2>/dev/null`
# demanded a mirror republish. Only an operation whose TARGET is the file counts.

_SEGMENT = re.compile(r"(?:&&|\|\||;|\n|(?<![|>])\|(?!\|))")


def shell_writes(cmd, target):
    """True when `cmd` writes a path matching the compiled regex `target`."""
    for seg in _SEGMENT.split(cmd or ""):
        seg = seg.strip()
        if not seg:
            continue
        for m in re.finditer(r"(?<![0-9&])>>?\s*([^\s;&|<>]+)|\b[12]>>?\s*([^\s;&|<>]+)", seg):
            dest = m.group(1) or m.group(2) or ""
            if dest.startswith("&") or dest == "/dev/null":
                continue
            if target.search(dest):
                return True
        if re.match(r"(sudo\s+)?(tee|sed|mv|cp|rm|truncate|install)\b", seg) or re.search(r"\|\s*tee\b", seg):
            words = seg.split()
            if words and words[0] == "sed" and not any(w.startswith("-i") for w in words[1:]):
                continue
            if words and words[0] in ("mv", "cp", "install"):
                words = words[-1:]          # only the destination is written
            if any(target.search(w.strip("'\"")) for w in words[1:] or words):
                return True
        if target.search(seg) and re.search(r"open\([^)]*['\"][wa]['\"]|write_text|\.write\(|file_put_contents", seg):
            return True
    return False


def ignored_by_git(cwd, rel):
    if not rel:
        return False
    try:
        r = subprocess.run(["git", "-C", cwd, "check-ignore", "-q", rel], capture_output=True, timeout=3)
        return r.returncode == 0
    except Exception:
        return False


# --- the mirror follows the integration branch (wave 36) ---------------------------------------------

def status_at(root, ref):
    """docs/ai/status.md as committed on `ref` (e.g. origin/development), or ''."""
    return git(root, "show", "%s:%s" % (ref, STATUS_REL)) if ref else ""


def status_blob(root, ref):
    return git(root, "rev-parse", "-q", "--verify", "%s:%s" % (ref, STATUS_REL)) if ref else ""


def mirror_record_path(root):
    cd = common_dir(root)
    return os.path.join(cd, "follow-through", "mirror.json") if cd else ""


def mirror_published_blob(root):
    try:
        with open(mirror_record_path(root), encoding="utf-8") as fh:
            return json.load(fh).get("blob", "")
    except Exception:
        return ""


def record_mirror_published(root, base):
    p = mirror_record_path(root)
    blob = status_blob(root, base)
    if not p or not blob:
        return
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            json.dump({"blob": blob, "ref": base, "time": int(time.time())}, fh)
    except Exception:
        pass
