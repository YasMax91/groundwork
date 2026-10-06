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


def common_dir(cwd):
    d = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return d if d and os.path.isdir(d) else ""


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

def registry_dir(cwd):
    cd = common_dir(cwd)
    if not cd:
        return ""
    d = os.path.join(cd, "follow-through", "sessions")
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
    d = registry_dir(cwd)
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
            (s.get("title") or s.get("session_id", "")[:8]), s.get("branch") or "?", where,
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
