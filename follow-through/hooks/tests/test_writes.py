"""follow-through :: executable proof for 0.4.2 — a status moved by `perl -i` or by a Python script counts, and a gate
config written behind a quoted `|` asks.

Project A's sessions moved docs/ai/status.md with `perl -pi -e … docs/ai/status.md` and with `python3 - <<'PY' … open(p,
'w') … PY`; neither counted, so the Stop gate refused that turn's commit. guard.py cut the line on every `|`, so
`sed -i 's/a|b/c/' .groundwork.json` was never asked about. The word-level cases call lanes.written_paths on
groundwork's parser; the Stop and guard cases drive the real hook scripts in subprocesses (test_lanes.Repo).
Run: python3 -m unittest discover -s follow-through/hooks/tests
"""

import os
import sys
import unittest

from test_command_repo import guard, outside, with_status
from test_lanes import HOOKS, RU, Repo

sys.path.insert(0, HOOKS)
import gw_repo  # noqa: E402
import lanes  # noqa: E402

STATUS = "docs/ai/status.md"
COMMIT = "git commit -am 'E8: refunds'"


def written(cmd, cwd="/srv/lane"):
    """[(word, path)] lanes.written_paths finds on a Bash line run in `cwd`."""
    return [(w, p) for c in gw_repo.commands(cmd, cwd) for w, p in lanes.written_paths(c)]


def words(cmd):
    return [w for w, _ in written(cmd)]


def status_words(cmd):
    """The written words the Stop gate reads as a status file — `…/docs/ai/status.md` too."""
    return [w for w in words(cmd) if w == STATUS or w.endswith("/" + STATUS)]


def py(*lines, flags="-", quote="'PY'"):
    """A Python here-document as the agents write it."""
    return "python3 %s <<%s\n%s\nPY" % (flags, quote, "\n".join(lines))


class PerlWords(unittest.TestCase):
    """`perl -i` writes the files after its switches and its program — never the program, never without -i."""

    def test_in_place_writes_its_files_and_only_them(self):
        for cmd in (r"perl -pi -e 's/\| doing \|/| done |/' docs/ai/status.md",
                    r"perl -0pi -e 's{\| doing \|}{| done |}' docs/ai/status.md",
                    "perl -0777 -pi -e 's/a/b/' docs/ai/status.md",
                    "perl -i -pe 's/a/b/' docs/ai/status.md",
                    "perl -pi.bak -e 's/a/b/' docs/ai/status.md",
                    "perl -i.orig -0pe 's/a/b/' -e 's/c/d/' docs/ai/status.md",
                    "perl -Mutf8 -CSD -I lib -pi -e 's/a/b/' -- docs/ai/status.md",
                    "perl -pi fix.pl docs/ai/status.md"):                 # no -e: the first word is the program
            self.assertEqual(written(cmd), [(STATUS, "/srv/lane/" + STATUS)], cmd)

    def test_without_in_place_it_writes_nothing_there(self):
        for cmd in (r"perl -ne 'print if /\| doing \|/' docs/ai/status.md",
                    "perl -e 'print 1' docs/ai/status.md",
                    "perl -pe 's/a/b/' docs/ai/status.md > /tmp/preview.md",
                    "perl -0pi -e 's{x}{y}' .claude/groundwork/task-state.md && git add docs/ai/status.md"):
            self.assertEqual(status_words(cmd), [], cmd)


class PythonWords(unittest.TestCase):
    """A Python script writes what it opens to write, by a path it spells out, where the call runs."""

    def test_what_it_opens_to_write(self):
        cases = {
            "python3 -c \"p='docs/ai/status.md'; s=open(p).read(); "
            "open(p,'w').write(s.replace('| doing |','| done |'))\"": [STATUS],
            py("from pathlib import Path", "p = Path('docs/ai/status.md')",
               "p.write_text(p.read_text().replace('| doing |', '| done |'))"): [STATUS],
            # project A, 2026-10-16: one script, one name, two files — each call reads the name where it runs
            py("p = 'docs/ai/specs/refunds.md'", "s = open(p).read()", "open(p, 'w').write(s)",
               "p = 'docs/ai/status.md'", "open(p, 'w', encoding='utf-8').write(s)", flags="-I -"):
                ["docs/ai/specs/refunds.md", STATUS],
            py("import os", "open('docs/ai/status.md.tmp', 'w').write('x')",
               "os.replace('docs/ai/status.md.tmp', 'docs/ai/status.md')"): ["docs/ai/status.md.tmp", STATUS],
            py("from pathlib import Path", "p = Path('docs/ai/status.md')", "tmp = Path('/tmp/status.new')",
               "tmp.write_text('x')", "tmp.replace(p)"): ["/tmp/status.new", STATUS],
            py("import os", "root = '/srv/other'", "open(os.path.join(root, 'docs', 'ai', 'status.md'), 'a')",
               "open(f'{root}/docs/ai/status.md', 'r+')"): ["/srv/other/" + STATUS] * 2,
            py("from pathlib import Path", "(Path('.claude') / 'settings.json').write_text('{}')"):
                [".claude/settings.json"],
        }
        for cmd, files in cases.items():
            self.assertEqual(words(cmd), files, cmd)

    def test_what_it_reads_or_cannot_name_is_not_written(self):
        for cmd in ("python3 -c \"print(open('docs/ai/status.md').read().count('| doing |'))\"",
                    py("s = open('docs/ai/status.md').read()", "open('/tmp/status.html', 'w').write(s)"),
                    py("p = 'docs/ai/status.md'", "s = open(p).read()", "p = 'docs/ai/plan.md'",
                       "open(p, 'w').write(s)"),
                    py("p = 'docs/ai/status.md'", "for p in ['docs/ai/plan.md']:", "    open(p, 'w')"),
                    py("p = 'docs/ai/status.md'", "[open(p, 'w') for p in ['docs/ai/plan.md']]"),
                    py("p = 'docs/ai/status.md'", "def save(p, s):", "    open(p, 'w').write(s)", "save('a.md', '')"),
                    py("text = 'see docs/ai/status.md'", "print(text.replace('docs/ai/status.md', 'docs/ai/plan.md'))"),
                    py("p = 'docs/ai/status.md'", "p.write_text('x')"),                 # a str has no write_text
                    py("open('$LANE/docs/ai/status.md', 'w')", quote="PY"),            # the shell fills the path in
                    "python3 tools/refresh_status.py docs/ai/status.md",
                    "python3 -m json.tool docs/ai/status.md"):
            self.assertEqual(status_words(cmd), [], cmd)

    def test_a_relative_path_is_where_the_script_runs(self):
        self.assertEqual(written("cd /srv/lane && python3 -c \"open('docs/ai/status.md', 'w')\"", "/srv/main"),
                         [(STATUS, "/srv/lane/" + STATUS)])
        moved = py("import os", "os.chdir('/srv/lane')", "open('docs/ai/status.md', 'w')")
        self.assertEqual(written(moved, "/srv/main"), [("/srv/lane/" + STATUS, "/srv/lane/" + STATUS)])
        lost = py("import os, sys", "os.chdir(sys.argv[1])", "open('docs/ai/status.md', 'w')")
        self.assertEqual(written(lost, "/srv/main"), [(STATUS, None)])        # a folder the line does not name


class StatusByScript(unittest.TestCase):
    """The Stop gate counts a status moved by `perl -i` or a Python script, in the tree whose file it writes."""

    def setUp(self):
        self.r = Repo()
        self.lane = self.r.worktree("lane", "origin/development")
        with_status(self.r, self.lane)

    def stop(self, *lines, cwd=None):
        return self.r.stop(cwd or self.lane, "sa", RU, tools=[("Bash", {"command": line}) for line in lines])

    def test_perl_in_place_counts(self):
        for line in (r"perl -pi -e 's/\| doing \|/| done |/' docs/ai/status.md",
                     r"perl -0pi -e 's{\| P1 \|[^\n]*}{| P1 | Возвраты | done | refunds | abc1234 | 2026-10-22 |}' "
                     "docs/ai/status.md",
                     "perl -0777 -i -pe 's/doing/done/' docs/ai/status.md"):
            self.assertEqual(self.stop(line, COMMIT), "", line)

    def test_perl_that_leaves_the_status_alone_does_not_count(self):
        for line in (r"perl -ne 'print if /\| doing \|/' docs/ai/status.md",
                     "perl -pe 's/doing/done/' docs/ai/status.md > /tmp/preview.md",
                     # project A, 2026-10-14: perl moved the task state; the status was only staged
                     "perl -0pi -e 's{- Mode: Releasing}{- Mode: Done}' .claude/groundwork/task-state.md && "
                     "git add docs/ai/status.md"):
            self.assertIn("was not updated", self.stop(line, COMMIT), line)

    def test_a_python_script_that_writes_the_status_counts(self):
        for line in (py("p = 'docs/ai/status.md'", "s = open(p, encoding='utf-8').read()",
                        "open(p, 'w', encoding='utf-8').write(s.replace('| doing |', '| done |'))"),
                     py("import pathlib", "p = pathlib.Path('docs/ai/status.md')",
                        "p.write_text(p.read_text().replace('| doing |', '| done |'))", flags="-I -"),
                     "python3 -c \"p='docs/ai/status.md'; s=open(p).read(); "
                     "open(p,'w').write(s.replace('| doing |','| done |'))\""):
            self.assertEqual(self.stop(line, COMMIT), "", line)

    def test_a_python_script_that_only_reads_the_status_does_not_count(self):
        for line in (py("s = open('docs/ai/status.md').read()", "open('/tmp/status.html', 'w').write(s)"),
                     "python3 -c \"print(open('docs/ai/status.md').read().count('| doing |'))\"",
                     "python3 tools/refresh_status.py docs/ai/status.md"):
            self.assertIn("was not updated", self.stop(line, COMMIT), line)

    def test_the_write_counts_in_the_tree_its_path_is_in(self):
        e, status = outside(self.r), os.path.join(self.lane, STATUS)
        commit = "git -C %s commit -am x" % self.lane
        for line in (py("from pathlib import Path", "Path('%s').write_text('x')" % status),
                     py("import os", "os.chdir('%s')" % self.lane, "open('docs/ai/status.md', 'a').write('x')"),
                     "perl -pi -e 's/doing/done/' %s" % status,
                     "sed -i '' 's/| doing |/| done |/' %s" % status):     # run in a folder outside git
            self.assertEqual(self.stop(line, commit, cwd=e), "", line)
        with_status(self.r, self.r.main)
        line = "python3 -c \"open('%s', 'a').write('x')\"" % os.path.join(self.r.main, STATUS)
        self.assertIn("was not updated", self.stop(line, commit, cwd=e))          # another worktree's status


class GateConfig(unittest.TestCase):
    """guard.py: a gate config written by any command asks — behind a quoted `|`, by perl, by Python; reading one
    does not."""

    def setUp(self):
        self.r = Repo()

    def ask(self, cmd, cwd=None):
        return guard(self.r, cwd or self.r.main, cmd)[0]

    def test_a_quoted_pipe_is_no_pipe(self):
        for cmd in ("sed -i 's/\"lanes\": true|false/\"lanes\": false/' .groundwork.json",
                    "sed -i '' 's/a|b/c/' .claude/settings.json"):
            self.assertEqual(self.ask(cmd), "ask", cmd)

    def test_perl_and_python_writes_ask(self):
        for cmd in ("perl -pi -e 's/\"status\": true/\"status\": false/' .claude/follow-through.json",
                    py("import json", "p = '.groundwork.json'", "d = json.load(open(p))", "d['gates'] = {}",
                       "open(p, 'w').write(json.dumps(d))"),
                    "python3 -c \"from pathlib import Path; (Path('.claude') / 'settings.json').write_text('{}')\""):
            self.assertEqual(self.ask(cmd), "ask", cmd)

    def test_reading_one_does_not_ask(self):
        for cmd in ("grep -E '\"(lanes|status)\": (true|false)' .groundwork.json",
                    "cat .groundwork.json | jq '.gates|keys'",
                    "perl -ne 'print if /lanes|status/' .claude/settings.json",
                    "sed -n 's/a|b/c/p' .groundwork.json",
                    "python3 -c \"import json; print(json.load(open('.groundwork.json'))['gates'])\""):
            self.assertEqual(self.ask(cmd), "", cmd)

    def test_the_line_answers_for_what_no_command_shows(self):
        self.assertEqual(self.ask("echo '{}' > \"$CFG/.groundwork.json\""), "ask")   # a folder the line does not set

    def test_a_script_writing_a_lanes_config_answers_to_the_lanes_switch(self):
        lane = self.r.worktree("lane", "origin/development")
        line = "python3 -c \"open('%s/.groundwork.json', 'w').write('{}')\"" % lane
        self.assertEqual(self.ask(line), "ask")
        with_status(self.r, lane, gates={"destructive": False})
        self.assertEqual(self.ask(line), "")                                  # off in the lane is off from outside
        with_status(self.r, self.r.main, gates={"destructive": False})
        os.remove(os.path.join(lane, ".claude", "follow-through.json"))
        self.assertEqual(self.ask(line), "ask")                               # off in the session's folder only


if __name__ == "__main__":
    unittest.main()
