"""Groundwork plugin :: which tests a change needs, and what already passed on which code (waves 37-38).

Shared by test-select.py (the selection), test-gate.sh (the Stop gate), push-gate.py (the check before a
shared branch), suite-record.py (what a run proved) and test-run.py (the one runner an agent calls).

Measured on otaje, 2026-10-06 .. 2026-10-21, before this module: the 0.47.0 selection took a routes file's
every URI and name and a non-class PHP file's basename as needles, so a quarter of its commits selected
395+ of 849 test files and the Stop gate hit the 10-minute hook limit 12 times. The rules below replayed on
the same 81 commits select a median of 5 files for the close circle.

Two circles and one verdict:
  close  — tests that exercise the change directly: the Stop gate runs these within a budget;
  wide   — tests that merely name what changed: the push check runs close + wide;
  shared — files whose change only the whole suite can check (dependencies, test bootstrap, providers…).

Records live in `<git-common-dir>/groundwork/`, shared by every worktree of the repository:
  suite-passes/<tree>       a green whole run (0.47.0 format, still read)
  verified/<tree>.json      a tree the push check accepted, with the time of the whole run its chain rests on
  file-passes/<tree>.json   test files green on that exact tree
  test-durations.json       seconds per test file, from the JUnit logs of the plugin's own runs

Every function fails soft: a missing git, an unreadable file or a malformed record costs a measurement or
a selection, never a session.
"""

import fnmatch
import json
import os
import re
import subprocess
import tempfile
import time


# --------------------------------------------------------------------------------------------- git ---

def git(*args, env=None, timeout=60, cwd=None):
    try:
        r = subprocess.run(["git"] + list(args), capture_output=True, text=True, timeout=timeout, env=env, cwd=cwd)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def toplevel(cwd=None):
    return git("rev-parse", "--show-toplevel", cwd=cwd).strip()


def common_dir(cwd=None):
    return git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=cwd).strip()


def store(name, cwd=None):
    common = common_dir(cwd)
    if not common:
        return ""
    d = os.path.join(common, "groundwork", name)
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        return ""
    return d


def config(top=None):
    try:
        with open(os.path.join(top or toplevel() or ".", ".groundwork.json"), encoding="utf-8") as fh:
            return json.load(fh) or {}
    except Exception:
        return {}


def gates(cfg):
    return (cfg or {}).get("gates") or {}


# ------------------------------------------------------------------------------------------- trees ---

def worktree_tree(cwd=None):
    """The tree id of the working tree as it would be committed.

    Built in a throwaway index (`git add -A` respects .gitignore). A skip-worktree file keeps the index's
    version: a lane's `phpunit.xml` carries the lane's own DB_DATABASE and is skip-worktree, so without
    this a green run in a lane never matched the commit made from it (otaje, 2026-10-07 .. 10-20: 15
    questions to the owner about recording such a run by hand).
    """
    top = toplevel(cwd)
    if not top:
        return ""
    fd, idx = tempfile.mkstemp(prefix="gw-index-")
    os.close(fd)
    os.unlink(idx)
    env = dict(os.environ, GIT_INDEX_FILE=idx)
    try:
        git("-C", top, "read-tree", "HEAD", env=env)
        git("-C", top, "add", "-A", env=env)
        skipped = [l[2:] for l in git("-C", top, "ls-files", "-v").splitlines() if l.startswith("S ")]
        if skipped:
            entries = git("-C", top, "ls-files", "-s", "--", *skipped)   # the REAL index's blobs
            if entries:
                subprocess.run(["git", "-C", top, "update-index", "--index-info"], input=entries,
                               capture_output=True, text=True, env=env, timeout=60)
        return git("-C", top, "write-tree", env=env).strip()
    finally:
        try:
            os.unlink(idx)
        except Exception:
            pass


def ref_tree(ref, cwd=None):
    return git("rev-parse", "%s^{tree}" % ref, cwd=cwd).strip()


# ----------------------------------------------------------------------------------------- records ---

def _read_json(path, default):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default


def _write_json(path, data):
    try:
        tmp = path + ".%d.tmp" % os.getpid()
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
        os.replace(tmp, path)
    except Exception:
        pass


def record_whole(tree, note=None, cwd=None):
    d = store("suite-passes", cwd)
    if not (tree and d):
        return
    now = int(time.time())
    data = {"time": now, "head": git("rev-parse", "HEAD", cwd=cwd).strip()}
    if note:
        data["note"] = note
    _write_json(os.path.join(d, tree), data)
    record_verified(tree, now, base=tree, kind="whole", cwd=cwd)


def whole_pass(tree, cwd=None):
    d = store("suite-passes", cwd)
    return _read_json(os.path.join(d, tree), None) if (tree and d and os.path.isfile(os.path.join(d, tree))) else None


def record_verified(tree, root_time, base, kind, cwd=None):
    d = store("verified", cwd)
    if tree and d:
        _write_json(os.path.join(d, tree + ".json"),
                    {"time": int(time.time()), "root_time": int(root_time), "base": base, "kind": kind})


def verified(tree, cwd=None):
    """root_time of the chain this tree rests on, or None."""
    d = store("verified", cwd)
    rec = _read_json(os.path.join(d, tree + ".json"), None) if (tree and d) else None
    if rec and rec.get("root_time"):
        return int(rec["root_time"])
    w = whole_pass(tree, cwd)
    return int(w["time"]) if (w and w.get("time")) else None


def verified_candidates(max_age_hours, cwd=None, limit=40):
    """(tree, root_time) of every verified tree whose chain is fresh enough, newest first."""
    now = time.time()
    out = {}
    for name, sub in (("suite-passes", ""), ("verified", ".json")):
        d = store(name, cwd)
        if not d:
            continue
        for f in os.listdir(d):
            if sub and not f.endswith(sub):
                continue
            tree = f[:-len(sub)] if sub else f
            if not re.fullmatch(r"[0-9a-f]{40}", tree):
                continue
            rec = _read_json(os.path.join(d, f), {})
            root = rec.get("root_time") or rec.get("time")
            if root and now - int(root) <= max_age_hours * 3600:
                out[tree] = max(out.get(tree, 0), int(root))
    return sorted(out.items(), key=lambda kv: -kv[1])[:limit]


def record_files(tree, files, cwd=None):
    d = store("file-passes", cwd)
    if not (tree and d and files):
        return
    path = os.path.join(d, tree + ".json")
    data = _read_json(path, {"files": {}})
    now = int(time.time())
    for f in files:
        data.setdefault("files", {})[f] = now
    _write_json(path, data)


def passed_files(tree, cwd=None):
    d = store("file-passes", cwd)
    return set((_read_json(os.path.join(d, tree + ".json"), {}) or {}).get("files", {})) if (tree and d) else set()


def durations(cwd=None):
    d = store("", cwd)
    return _read_json(os.path.join(d, "test-durations.json"), {}) if d else {}


def record_durations(per_file, cwd=None):
    d = store("", cwd)
    if not (d and per_file):
        return
    path = os.path.join(d, "test-durations.json")
    data = _read_json(path, {})
    for f, s in per_file.items():
        old = data.get(f)
        data[f] = round(s if old is None else 0.5 * old + 0.5 * s, 2)
    _write_json(path, data)


def junit_results(path, top):
    """{test file: {"time": s, "failed": bool, "messages": [...]}} from a PHPUnit / paratest JUnit log."""
    try:
        import xml.etree.ElementTree as ET
        root = ET.parse(path).getroot()
    except Exception:
        return {}
    out = {}
    for case in root.iter("testcase"):
        f = case.get("file") or ""
        if not f:
            continue
        f = _relative_test_path(f, top)
        if not f:
            continue
        r = out.setdefault(f, {"time": 0.0, "failed": False, "messages": []})
        try:
            r["time"] += float(case.get("time") or 0)
        except Exception:
            pass
        for bad in list(case.findall("failure")) + list(case.findall("error")):
            r["failed"] = True
            r["messages"].append(((bad.get("message") or "") + " " + (bad.text or ""))[:400])
    return out


def _relative_test_path(f, top):
    f = f.replace("\\", "/")
    for prefix in (top.rstrip("/") + "/", "/var/www/html/", "/app/"):
        if f.startswith(prefix):
            return f[len(prefix):]
    i = f.find("/tests/")
    return f[i + 1:] if i >= 0 else ""


# -------------------------------------------------------------------------------------- the change ---

SHARED_BRANCHES = ["development", "develop", "main", "master", "staging", "production"]


def _upstream_base(cwd=None):
    up = git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}", cwd=cwd).strip()
    if up:
        return git("merge-base", "HEAD", up, cwd=cwd).strip() or up
    return ""


def parse_diff(text):
    """{path: {"lines": [(sign, text)], "touched": [new-file line numbers], "deleted": bool}}"""
    out, cur = {}, None
    for line in text.splitlines():
        if line.startswith("diff --git "):
            cur = None
            m = re.match(r"diff --git a/(.+?) b/(.+)$", line)
            if m:
                cur = out.setdefault(m.group(2), {"lines": [], "touched": [], "deleted": False})
        elif cur is None:
            continue
        elif line.startswith("+++ /dev/null"):
            cur["deleted"] = True
        elif line.startswith("@@"):
            m = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", line)
            if m:
                start, n = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
                cur["touched"].extend(range(start, start + max(n, 1)))
        elif line.startswith("+") and not line.startswith("+++"):
            cur["lines"].append(("+", line[1:]))
        elif line.startswith("-") and not line.startswith("---"):
            cur["lines"].append(("-", line[1:]))
    return out


def tests_on_disk(top):
    out = []
    for root, dirs, names in os.walk(os.path.join(top, "tests")):
        dirs[:] = [d for d in dirs if d not in ("vendor", "node_modules")]
        out += [os.path.relpath(os.path.join(root, n), top) for n in names if n.endswith("Test.php")]
    return sorted(out)


class WorkingTree:
    """The change as it stands on disk: uncommitted, untracked, and committed-but-unpushed."""

    def __init__(self, top, base=None):
        self.top, self._cache = top, {}
        self.base = base or _upstream_base(top) or ("HEAD" if git("rev-parse", "--verify", "-q", "HEAD", cwd=top) else "")
        self.diff = parse_diff(git("diff", "-U0", "--no-color", "--no-ext-diff", self.base, cwd=top)) if self.base else {}
        for f in git("ls-files", "--others", "--exclude-standard", cwd=top).split("\n"):
            if f and os.path.isfile(os.path.join(top, f)):
                text = self.read(f)
                self.diff[f] = {"lines": [("+", l) for l in text.splitlines()],
                                "touched": list(range(1, text.count("\n") + 2)), "deleted": False}
        self.files = sorted(self.diff)

    def read(self, path):
        if path not in self._cache:
            try:
                with open(os.path.join(self.top, path), encoding="utf-8", errors="ignore") as fh:
                    self._cache[path] = fh.read()
            except Exception:
                self._cache[path] = ""
        return self._cache[path]

    def tests(self):
        return tests_on_disk(self.top)

    def listing(self, prefix):
        out = []
        for root, _, names in os.walk(os.path.join(self.top, prefix)):
            for n in names:
                out.append(os.path.relpath(os.path.join(root, n), self.top))
        return sorted(out)


class TreeDiff:
    """The change between two trees — what the push check reasons about. Content is read from `new`."""

    def __init__(self, top, old, new):
        self.top, self.old, self.new = top, old, new
        self.diff = parse_diff(git("diff", "-U0", "--no-color", "--no-ext-diff", old, new, cwd=top))
        self.files = sorted(self.diff)
        self._cache = {}

    def _batch(self, paths):
        want = [p for p in paths if p not in self._cache]
        if not want:
            return
        try:
            r = subprocess.run(["git", "-C", self.top, "cat-file", "--batch"],
                               input="".join("%s:%s\n" % (self.new, p) for p in want).encode(),
                               capture_output=True, timeout=120)
            data, pos = r.stdout, 0
            for p in want:
                nl = data.index(b"\n", pos)
                head = data[pos:nl].decode(errors="ignore").split()
                pos = nl + 1
                self._cache[p] = ""
                if len(head) == 3:                     # "<sha> <type> <size>", then the object; else "missing"
                    size = int(head[2])
                    if head[1] == "blob":
                        self._cache[p] = data[pos:pos + size].decode("utf-8", errors="ignore")
                    pos += size + 1
        except Exception:
            for p in want:
                self._cache.setdefault(p, "")

    def read(self, path):
        self._batch([path])
        return self._cache.get(path, "")

    def listing(self, prefix):
        out = sorted(l for l in git("ls-tree", "-r", "--name-only", self.new, "--", prefix, cwd=self.top).split("\n") if l)
        self._batch([p for p in out if p.endswith(".php")])     # one cat-file for the lot, not one per read
        return out

    def tests(self):
        out = [p for p in self.listing("tests") if p.endswith("Test.php")]
        self._batch(out)
        return out


# ------------------------------------------------------------------------------------------- rules ---

SHARED_EXACT = {
    "composer.json", "composer.lock", "phpunit.xml", "phpunit.xml.dist", ".env.testing",
    "tests/TestCase.php", "tests/CreatesApplication.php", "tests/Pest.php",
    "app/Http/Kernel.php", "app/Console/Kernel.php", "app/Exceptions/Handler.php",
    "config/app.php", "config/database.php", "config/auth.php",
}
SHARED_PREFIX = ("bootstrap/", "app/Providers/", "app/Http/Middleware/")

# A word that names nothing on its own. `update` alone selected 233 otaje test files.
GENERIC = {"index", "show", "store", "update", "destroy", "create", "edit", "list", "data", "item", "items",
           "value", "name", "type", "status", "search", "home", "login", "logout", "admin", "api", "web",
           "page", "view", "form", "save", "test", "user", "file", "files", "image", "images"}

# Methods that are the class itself: a change inside one selects the class's tests, not a method's.
CLASS_LEVEL = {"__construct", "__invoke", "handle", "boot", "booted", "booting", "register", "rules",
               "authorize", "toArray", "casts", "definition", "up", "down", "render", "messages", "attributes",
               "prepareForValidation", "failedValidation", "middleware", "via", "toMail", "build", "content",
               "envelope", "attachments", "broadcastOn", "setup", "setupListOperation", "setupCreateOperation",
               "setupUpdateOperation", "setupShowOperation"}

DESTRUCTIVE = re.compile(r"->(dropColumn|renameColumn|dropForeign|dropIndex|dropUnique|dropPrimary|change)\s*\(")
ROUTE_SHAPE = re.compile(r"(->|::)(middleware|withoutMiddleware|prefix|group|domain)\s*\(")


def _word(n):
    return re.compile(r"(?<![\w$])%s(?![\w])" % re.escape(n))


def _uri(u):
    return re.compile(r"""['"/]%s(?=['"/?{]|$)""" % re.escape(u.strip("/")), re.M)


def _tokens(name):
    return re.findall(r"[A-Z]+(?![a-z])|[A-Z]?[a-z0-9]+", name)


def _name_carries(test_path, base):
    """`OrderService` is carried by OrderServiceTest / OrderServiceRefundTest, not by PreorderServiceTest."""
    t, b = _tokens(os.path.basename(test_path)[:-8]), _tokens(base)
    return bool(b) and any(t[i:i + len(b)] == b for i in range(len(t) - len(b) + 1))


def _statements(text):
    return [s for s in re.split(r";\s*\n", text) if s.strip()]


def _route_needles(stmts):
    pats = []
    for s in stmts:
        for n in re.findall(r"->name\(\s*['\"]([\w.:-]+)['\"]", s):
            if n.lower() not in GENERIC and len(n) >= 4:
                pats.append(re.compile(r"['\"]%s['\"]" % re.escape(n)))
        for u in re.findall(r"Route::(?:get|post|put|patch|delete|options|any|match|view|redirect)\(\s*(?:\[[^\]]*\]\s*,\s*)?['\"](/?[\w/{}.-]+)['\"]", s):
            segs = [x for x in u.strip("/").split("/") if x and "{" not in x]
            if segs and (len(segs) > 1 or (segs[0].lower() not in GENERIC and len(segs[0]) >= 4)):
                pats.append(_uri("/".join(segs)))
        for u in re.findall(r"Route::(?:crud|resource|apiResource)\(\s*['\"]([\w/.-]+)['\"]", s):
            if len(u) >= 3:
                pats.append(re.compile(r"['\"]%s\.\w" % re.escape(u)))         # product.index, product.update …
                pats.append(re.compile(r"/admin/%s(?=['\"/?]|$)" % re.escape(u), re.M))
    return pats


def _routes_of(controller, methods, src):
    """Route statements that dispatch to `controller` (limited to `methods` when any of them appears)."""
    stmts = []
    for f in src.listing("routes"):
        if f.endswith(".php"):
            stmts += [s for s in _statements(src.read(f)) if re.search(r"(?<![\w$])%s(?![\w])" % re.escape(controller), s)]
    if methods:
        narrowed = [s for s in stmts if any(re.search(r"['\"]%s['\"]" % re.escape(m), s) for m in methods)]
        stmts = narrowed or stmts
    return stmts


def _enclosing_methods(text, touched):
    decls = [(i + 1, m.group(1)) for i, line in enumerate(text.splitlines())
             for m in [re.search(r"\bfunction\s+(\w+)\s*\(", line)] if m]
    out = set()
    for n in touched:
        prior = [name for ln, name in decls if ln <= n]
        if prior:
            out.add(prior[-1])
    return out


def _migration_is_shared(text, lines, touched):
    """A migration that drops, renames or retypes, or adds a NOT NULL column to a table it did not create."""
    created = set(re.findall(r"Schema::create\(\s*['\"]([\w]+)['\"]", text))
    changed = "\n".join(t for s, t in lines if s == "+")
    if DESTRUCTIVE.search(changed):
        return True
    for t in re.findall(r"Schema::(?:rename|drop|dropIfExists)\(\s*['\"]([\w]+)['\"]", changed):
        if t not in created:
            return True
    mode, modes = None, {}
    for i, line in enumerate(text.splitlines(), 1):
        m = re.search(r"Schema::(create|table)\(\s*['\"]([\w]+)['\"]", line)
        if m:
            mode = (m.group(1), m.group(2))
        modes[i] = mode
    lines_text = text.splitlines()
    for n in touched:
        mode = modes.get(n)
        if not mode or mode[0] != "table" or mode[1] in created or n > len(lines_text):
            continue
        stmt = lines_text[n - 1]
        if re.search(r"\$table->(?!index|unique|foreign|primary|dropColumn|timestamps|softDeletes|nullable)\w+\(\s*['\"]\w+['\"]", stmt) \
                and not re.search(r"->nullable\(|->default\(|->useCurrent\(|->nullableTimestamps", stmt):
            return True
    return False


def is_shared(path, entry, read):
    if path in SHARED_EXACT or path.startswith(SHARED_PREFIX):
        return True
    if path.startswith("database/migrations/") and path.endswith(".php"):
        return _migration_is_shared(read(path), entry["lines"], entry["touched"])
    if path.startswith("routes/") and path.endswith(".php"):
        return any(ROUTE_SHAPE.search(t) for _, t in entry["lines"])
    return False


def select(src):
    """{"close": [ordered], "wide": [...], "shared": [...], "why": {test: reason}} for a WorkingTree / TreeDiff."""
    tests = src.tests()
    bodies = {t: src.read(t) for t in tests}
    test_set = set(tests)
    close, why, wide, shared = {}, {}, set(), []
    # A needle found in more than 5 % of the tests (at least 20 files) narrows nothing: on otaje's 81 commits a
    # migration column (`position`, `description`), a common seeder and a central model's family of test names
    # each pulled 50-470 files into the close circle. Such a group still runs before the push, as wide.
    cap = max(20, len(tests) // 20)

    def to_close(ts, rank, reason, always=False):
        ts = set(ts)
        if len(ts) > cap and not always:
            wide.update(ts)
            return
        for t in ts:
            if t not in close or rank < close[t]:
                close[t], why[t] = rank, reason

    def naming(pats):
        return {t for t, b in bodies.items() if any(p.search(b) for p in pats)} if pats else set()

    def per_needle(pats, rank, reason):
        for p in pats:
            to_close(naming([p]), rank, reason)

    for f in src.files:
        entry = src.diff.get(f) or {"lines": [], "touched": [], "deleted": False}
        if f.startswith("tests/") and f.endswith("Test.php"):
            if f in test_set:
                to_close([f], 0, "changed test", always=True)
            continue
        if is_shared(f, entry, src.read):
            shared.append(f)          # only the whole suite checks it; its "tests" would be every test there is
            continue
        text_lines = [t for _, t in entry["lines"]]
        changed = "\n".join(text_lines)
        base = os.path.basename(f)
        stem = base[:-4] if base.endswith(".php") else base

        if f.startswith("tests/"):                                        # a trait or helper the tests use
            to_close(naming([_word(stem)]), 2, "uses " + stem)
        elif f.startswith("routes/") and f.endswith(".php"):
            added = [t.strip() for s, t in entry["lines"] if s == "+" and t.strip()]
            stmts = [s for s in _statements(src.read(f)) if any(a in s for a in added)]
            stmts += [t for s, t in entry["lines"] if s == "-"]          # a removed route is gone from the file
            pats = _route_needles(stmts or [changed])
            pats += [_word(c) for c in re.findall(r"(\w+Controller)(?:::class|['\"])", changed)]
            per_needle(pats, 3, "route changed in " + f)
        elif f.startswith("config/") and f.endswith(".php"):
            keys = set(re.findall(r"['\"]([\w-]{3,})['\"]\s*=>", changed))
            if keys:
                per_needle([re.compile(re.escape("%s.%s" % (stem, k))) for k in keys], 3, "config key")
            else:
                wide |= naming([re.compile(re.escape(stem + "."))])
        elif f.startswith(("lang/", "resources/lang/")):
            keys = set(re.findall(r"['\"]([\w.-]{3,})['\"]\s*=>", changed))
            per_needle([re.compile(re.escape("%s.%s" % (stem, k))) for k in keys], 3, "translation key")
        elif f.startswith("database/migrations/"):
            tables = set(re.findall(r"Schema::(?:create|table|rename|dropIfExists|drop)\(\s*['\"]([a-z0-9_]+)['\"]", src.read(f) + "\n" + changed))
            cols = {c for c in re.findall(r"->\w+\(\s*['\"]([a-z0-9_]{4,})['\"]", changed)
                    if c not in GENERIC and c not in tables and ("_" in c or len(c) >= 6)}
            wide |= naming([_word(x) for x in tables | cols])     # 455 close picks on 81 otaje commits
        elif f.startswith("database/factories/") and stem.endswith("Factory"):
            to_close(naming([_word(stem)]), 2, "factory")
            wide |= naming([_word(stem[:-7])]) if len(stem) > 7 else set()
        elif f.startswith("database/seeders/"):
            to_close(naming([_word(stem)]), 2, "seeder")
        elif f.startswith("resources/views/") and base.endswith(".blade.php"):
            dotted = f[len("resources/views/"):-len(".blade.php")].replace("/", ".")
            to_close(naming([re.compile(r"['\"]%s['\"]" % re.escape(dotted))]), 3, "view " + dotted)
            consumers = [c for c in src.listing("app") if c.endswith(".php") and dotted in src.read(c)][:15]
            for c in consumers:
                cb = os.path.basename(c)[:-4]
                wide |= naming([_word(cb)])
                if cb.endswith("Controller"):
                    wide |= naming(_route_needles(_routes_of(cb, set(), src)))
        elif f.endswith(".php") and f.startswith(("app/", "src/", "Modules/", "modules/", "packages/", "domain/")):
            content = src.read(f)
            family = [t for t in tests if _name_carries(t, stem)]
            own = [t for t in family if os.path.basename(t) == stem + "Test.php"]
            to_close(own, 1, "named after " + stem, always=True)
            to_close(family, 1, "named after " + stem)
            methods = {m for m in _enclosing_methods(content, entry["touched"]) if m not in CLASS_LEVEL and len(m) >= 4}
            consts = set(re.findall(r"\bconst\s+(\w{4,})\s*=", changed))
            cls = _word(stem)
            for m in sorted(methods | consts):        # one needle at a time, so a common one cannot drag the rest
                mp = _word(m)
                to_close({t for t, b in bodies.items() if cls.search(b) and mp.search(b)}, 2, "calls a changed method of " + stem)
            if stem.endswith("Controller"):
                named = [st for st in _routes_of(stem, methods, src)
                         if methods and any(re.search(r"['\"]%s['\"]" % re.escape(m), st) for m in methods)]
                if named:        # a route names the changed action: its tests are this change's own
                    per_needle(_route_needles(named), 3, "routes of " + stem)
                else:            # class-level change (setup, middleware, a helper): every route, wide
                    wide |= naming(_route_needles(_routes_of(stem, set(), src)))
            wide |= naming([_word(stem)])
            if not f.startswith("app/Models/"):
                consumers = [c for c in src.listing("app") if c.endswith(".php") and c != f
                             and _word(stem).search(src.read(c) or "")]
                if len(consumers) <= 15:
                    for c in consumers:
                        cb = os.path.basename(c)[:-4]
                        if cb.endswith("Controller"):
                            hinted = set(re.findall(r"function\s+(\w+)\s*\([^)]*\b%s\b" % re.escape(stem), src.read(c)))
                            wide |= naming(_route_needles(_routes_of(cb, hinted, src)))
                        wide |= naming([_word(cb)])
        else:                                                             # a document, a stylesheet, a fixture
            # A test reads `f` when a quoted path in its code names it — `base_path('docs/ai/x.md')`,
            # `public_path('css/admin.css')`, a glob. A file name in a comment is not a read: on otaje's commits
            # that rule pulled a spec's or api-reference.md's 100-170 mentioning tests into the close circle.
            readers = set()
            for t, b in bodies.items():
                for lit in re.findall(r"['\"]([\w./*{}-]*/[\w./*{}-]+\.\w+|[\w.-]+\.(?:md|json|css|js|xml|csv|html|txt|yml|yaml))['\"]", b):
                    if len(lit) >= 6 and (lit == f or f.endswith("/" + lit) or fnmatch.fnmatch(f, lit)
                                          or fnmatch.fnmatch(f, "*/" + lit)):
                        readers.add(t)
                        break
            to_close(readers, 3, "reads " + f)

    order = sorted(close, key=lambda t: (close[t], t))
    return {"close": order, "wide": sorted(wide - set(close)), "shared": sorted(set(shared)),
            "why": {t: why[t] for t in order}}


def suite_files(top):
    """Every test file the whole suite runs: phpunit.xml's testsuites (directories, files, excludes)."""
    import xml.etree.ElementTree as ET
    found = set()
    for name in ("phpunit.xml", "phpunit.xml.dist"):
        path = os.path.join(top, name)
        if not os.path.isfile(path):
            continue
        try:
            root = ET.parse(path).getroot()
        except Exception:
            break
        for suite in root.iter("testsuite"):
            excludes = [os.path.normpath(os.path.join(top, (e.text or "").strip())) for e in suite.findall("exclude")]
            for d in suite.findall("directory"):
                base = os.path.normpath(os.path.join(top, (d.text or "").strip()))
                suffix = d.get("suffix") or "Test.php"
                for r, dirs, names in os.walk(base):
                    if any(r == x or r.startswith(x + os.sep) for x in excludes):
                        dirs[:] = []
                        continue
                    found |= {os.path.relpath(os.path.join(r, n), top) for n in names if n.endswith(suffix)}
            for f in suite.findall("file"):
                p = os.path.normpath(os.path.join(top, (f.text or "").strip()))
                if os.path.isfile(p):
                    found.add(os.path.relpath(p, top))
        break
    return sorted(found) or tests_on_disk(top)


# ---------------------------------------------------------------------------------- the push check ---

def push_mode(cfg):
    v = gates(cfg).get("full_suite_before_push", "when-needed")
    if v is False or gates(cfg).get("test_on_stop") is False:
        return "off"
    return "always" if v == "always" else "when-needed"


def requirement(tree, cfg, top):
    """What the push of `tree` still needs: {"ok": bool, "kind": "verified|whole|files", ...}."""
    max_age = float(gates(cfg).get("full_suite_max_age_hours") or 24)
    if push_mode(cfg) == "always":
        ok = bool(whole_pass(tree, top))
        return {"ok": ok, "kind": "whole", "reason": "" if ok else "this exact code has no green whole run"}
    root = verified(tree, top)
    if root and time.time() - root <= max_age * 3600:
        return {"ok": True, "kind": "verified", "root_time": root}
    cands = verified_candidates(max_age, top)
    if not cands:
        return {"ok": False, "kind": "whole",
                "reason": "no green whole run in the last %g hours to build on" % max_age}
    best, best_root, best_n = None, 0, None
    for cand, cand_root in cands:
        n = len([l for l in git("diff", "--name-only", cand, tree, cwd=top).split("\n") if l])
        if best_n is None or n < best_n:
            best, best_root, best_n = cand, cand_root, n
    sel = select(TreeDiff(top, best, tree))
    if sel["shared"]:
        return {"ok": False, "kind": "whole", "base": best, "shared": sel["shared"],
                "reason": "shared files changed since the last verified code: " + ", ".join(sel["shared"][:6])}
    needed = sel["close"] + sel["wide"]
    missing = [t for t in needed if t not in passed_files(tree, top)]
    if not missing:
        return {"ok": True, "kind": "files", "base": best, "root_time": best_root, "selected": needed}
    return {"ok": False, "kind": "files", "base": best, "root_time": best_root, "files": missing,
            "selected": needed, "reason": "%d of the %d tests touching what changed since the last verified code "
                                          "have not passed on this exact code" % (len(missing), len(needed))}
