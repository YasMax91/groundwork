"""follow-through :: executable proof for wave 43 — a session running an out-of-date list of follow-through's hooks
says so, once (gw_registration.py; prompt_submit.py --registration).

The check cases run a copy of the hooks folder, so hooks.json changes under a "session" the way a release changes it
under a running one; every case has an isolated HOME. Run: python3 -m unittest discover -s follow-through/hooks/tests
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HOOKS = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GROUNDWORK_MODULE = os.path.join(HOOKS, "..", "..", "hooks", "gw_registration.py")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_lanes import Repo  # noqa: E402

TOKEN = re.compile(r"--registration ([0-9a-f]{1,64})")


def module(hooks, *args):
    r = subprocess.run(["python3", os.path.join(hooks, "gw_registration.py")] + list(args),
                       capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout.strip()


def prompt(hooks, home, sid, cwd, args=(), root=True, raw=None):
    """prompt_submit.py as the harness runs it -> (exit code, stdout)."""
    env = dict(os.environ, HOME=home)
    env.pop("CLAUDE_PLUGIN_ROOT", None)
    if root:
        env["CLAUDE_PLUGIN_ROOT"] = os.path.dirname(hooks)
    payload = {"session_id": sid, "cwd": cwd, "hook_event_name": "UserPromptSubmit", "prompt": "дальше"}
    r = subprocess.run(["python3", os.path.join(hooks, "prompt_submit.py")] + list(args),
                       input=raw if raw is not None else json.dumps(payload),
                       capture_output=True, text=True, env=env, cwd=cwd, timeout=60)
    return r.returncode, r.stdout.strip()


def told(out):
    """(systemMessage, additionalContext) of an answer; ("", "") for none."""
    if not out:
        return "", ""
    d = json.loads(out)
    return d.get("systemMessage", ""), d["hookSpecificOutput"]["additionalContext"]


class TheId(unittest.TestCase):
    """FT43: follow-through's hooks.json names its own content (GW43-AC7, AC8)."""

    def test_the_copy_is_groundworks_module_byte_for_byte(self):
        if not os.path.exists(GROUNDWORK_MODULE):
            self.skipTest("groundwork's hooks/gw_registration.py is not beside this plugin (an installed copy)")
        with open(os.path.join(HOOKS, "gw_registration.py"), "rb") as a, open(GROUNDWORK_MODULE, "rb") as b:
            self.assertTrue(a.read() == b.read(), "follow-through/hooks/gw_registration.py differs from "
                            "hooks/gw_registration.py — copy groundwork's module over it: "
                            "cp hooks/gw_registration.py follow-through/hooks/gw_registration.py")

    def test_hooks_json_declares_the_id_of_its_content(self):
        rc, out = module(HOOKS, "check", os.path.join(HOOKS, "hooks.json"))
        self.assertEqual(rc, 0, out)

    def test_only_the_prompt_command_carries_it(self):
        with open(os.path.join(HOOKS, "hooks.json"), encoding="utf-8") as fh:
            hooks = json.load(fh)["hooks"]
        carrying = [(event, h["command"]) for event, groups in hooks.items() for g in groups for h in g["hooks"]
                    if TOKEN.search(h["command"])]
        self.assertEqual(len(carrying), 1, carrying)
        self.assertEqual(carrying[0][0], "UserPromptSubmit")
        self.assertRegex(carrying[0][1], r'prompt_submit\.py" --registration [0-9a-f]{12}$')


class TheCheck(unittest.TestCase):
    """FT43: prompt_submit.py tells a session once that its list is out of date (GW43-AC1..AC5)."""

    def setUp(self):
        self.root = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        self.hooks = os.path.join(self.root, "plugin", "hooks")
        shutil.copytree(HOOKS, self.hooks, ignore=shutil.ignore_patterns("tests", "__pycache__"))
        self.home = os.path.join(self.root, "home")
        os.makedirs(os.path.join(self.home, ".claude"))
        self.plain = os.path.join(self.root, "plain")              # no git
        os.makedirs(self.plain)
        self.id = module(self.hooks, "ident", os.path.join(self.hooks, "hooks.json"))[1]

    def ask(self, sid, args=(), **kw):
        return prompt(self.hooks, self.home, sid, kw.pop("cwd", self.plain), args, **kw)

    def marker(self, sid):
        p = os.path.join(self.home, ".claude", "follow-through", "registration", sid + ".registration")
        if not os.path.exists(p):
            return None
        with open(p, encoding="utf-8") as fh:
            return fh.read().strip()

    def change_on_disk(self):
        p = os.path.join(self.hooks, "hooks.json")
        with open(p, encoding="utf-8") as fh:
            d = json.load(fh)
        d["hooks"]["Stop"][0]["hooks"][0]["statusMessage"] = "changed"
        with open(p, "w", encoding="utf-8") as fh:
            json.dump(d, fh, indent=2)
        return module(self.hooks, "stamp", p)[1]

    def test_a_current_list_says_nothing(self):
        self.assertEqual(self.ask("c1", ("--registration", self.id)), (0, ""))
        self.assertIsNone(self.marker("c1"))

    def test_a_list_from_before_is_told_once(self):
        rc, out = self.ask("s1")
        user, agent = told(out)
        self.assertEqual(rc, 0)
        self.assertIn("follow-through's hooks changed after this session loaded them", user)
        self.assertIn("Run /reload-plugins in this session, or reopen it.", user)
        self.assertIn("(loaded: none, a list from before this check existed; on disk: %s)" % self.id, agent)
        self.assertEqual(self.marker("s1"), self.id)
        self.assertEqual(self.ask("s1"), (0, ""))
        self.assertEqual(self.ask("s1"), (0, ""))

    def test_another_id_is_named_and_a_reload_is_silent(self):
        _, agent = told(self.ask("s2", ("--registration", "0123456789ab"))[1])
        self.assertIn("(loaded: 0123456789ab; on disk: %s)" % self.id, agent)
        self.assertEqual(self.ask("s3", ("--registration", self.id)), (0, ""))

    def test_a_change_on_disk_tells_again(self):
        self.ask("s4")
        new = self.change_on_disk()
        self.assertNotEqual(new, self.id)
        _, agent = told(self.ask("s4")[1])
        self.assertIn("on disk: %s" % new, agent)
        _, agent = told(self.ask("s5", ("--registration", self.id))[1])
        self.assertIn("(loaded: %s; on disk: %s)" % (self.id, new), agent)
        self.assertEqual(self.ask("s6", ("--registration", new)), (0, ""))

    def test_in_a_lane_the_notice_comes_first_and_the_lane_news_stays(self):
        r = Repo()
        a, b = r.worktree("one", "origin/development"), r.worktree("two", "origin/development")
        r.start(b, "sb")
        r.start(a, "sa", "Возвраты")
        rc, out = prompt(HOOKS, r.home, "sb", b)                    # the real plugin; the command carries no id
        user, agent = told(out)
        self.assertEqual(rc, 0)
        self.assertIn("/reload-plugins", user)
        self.assertTrue(agent.startswith("follow-through: this session runs an out-of-date list"), agent)
        self.assertIn("follow-through, what changed around you:", agent)
        self.assertIn("Возвраты", agent)
        self.assertLess(agent.index("out-of-date list"), agent.index("what changed around you"))

    def test_not_started_by_the_harness_no_check(self):
        self.assertEqual(self.ask("f1", root=False), (0, ""))
        self.assertIsNone(self.marker("f1"))

    def test_a_broken_payload_or_no_session_says_nothing(self):
        self.assertEqual(self.ask("f2", raw="not json"), (0, ""))
        self.assertEqual(self.ask("f3", raw=json.dumps({"hook_event_name": "UserPromptSubmit"})), (0, ""))

    def test_no_id_on_disk_says_nothing(self):
        p = os.path.join(self.hooks, "hooks.json")
        with open(p, encoding="utf-8") as fh:
            text = fh.read()
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(TOKEN.sub("", text))
        self.assertEqual(self.ask("f4"), (0, ""))
        os.remove(p)
        self.assertEqual(self.ask("f5"), (0, ""))

    def test_an_unwritable_marker_folder_still_tells(self):
        os.makedirs(os.path.join(self.home, ".claude", "follow-through"))
        with open(os.path.join(self.home, ".claude", "follow-through", "registration"), "w") as fh:
            fh.write("a file")
        rc, out = self.ask("f6")
        self.assertEqual(rc, 0)
        self.assertIn("/reload-plugins", told(out)[0])


if __name__ == "__main__":
    unittest.main()
