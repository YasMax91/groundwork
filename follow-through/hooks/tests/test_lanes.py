"""follow-through :: executable proof for wave 35 — lanes, awareness, freshness, status.

Each case builds a real repository: a bare origin with `main` and `development`, a main checkout, and
worktrees. Two "sessions" are two session ids driving the real hook scripts in subprocesses with an
isolated HOME. Run: python3 -m unittest discover -s follow-through/hooks/tests
"""

import json
import os
import re
import subprocess
import tempfile
import unittest

HOOKS = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GIT_ID = ["-c", "user.email=t@t", "-c", "user.name=t"]


def sh(cwd, *args):
    r = subprocess.run(["git", "-C", cwd] + GIT_ID + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr)
    return r.stdout.strip()


def jload(p):
    with open(p) as fh:
        return json.load(fh)


def jsave(p, data):
    with open(p, "w") as fh:
        json.dump(data, fh)


def commit(cwd, path, text, msg):
    full = os.path.join(cwd, path)
    os.makedirs(os.path.dirname(full) or cwd, exist_ok=True)
    with open(full, "w") as fh:
        fh.write(text)
    sh(cwd, "add", path)
    sh(cwd, "commit", "-qm", msg)


class Repo:
    def __init__(self):
        self.root = os.path.realpath(tempfile.mkdtemp())
        self.home = os.path.join(self.root, "home")
        os.makedirs(os.path.join(self.home, ".claude"))
        origin = os.path.join(self.root, "origin.git")
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", origin], check=True)
        self.main = os.path.join(self.root, "proj")
        subprocess.run(["git", "clone", "-q", origin, self.main], check=True, capture_output=True)
        commit(self.main, "a.txt", "1\n", "init")
        sh(self.main, "push", "-q", "origin", "main")
        sh(self.main, "checkout", "-qb", "development")
        commit(self.main, "dev.txt", "dev\n", "dev work")
        sh(self.main, "push", "-q", "origin", "development")
        sh(self.main, "remote", "set-head", "origin", "main")

    def worktree(self, name, base="origin/main"):
        path = os.path.join(self.main, ".claude", "worktrees", name)
        sh(self.main, "worktree", "add", "-q", "-b", "claude/" + name, path, base)
        return os.path.realpath(path)

    def transcript(self, cwd, tools=(), user="сделай задачу целиком, пожалуйста"):
        path = os.path.join(self.root, "t-%d.jsonl" % len(os.listdir(self.root)))
        with open(path, "w") as fh:
            fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": user}}) + "\n")
            for name, data in tools:
                fh.write(json.dumps({"type": "assistant", "message": {"content": [
                    {"type": "tool_use", "name": name, "input": data}]}}) + "\n")
        return path

    def hook(self, script, payload):
        env = dict(os.environ, HOME=self.home)
        r = subprocess.run(["python3", os.path.join(HOOKS, script)], input=json.dumps(payload),
                           capture_output=True, text=True, env=env, cwd=payload.get("cwd"), timeout=60)
        return r.stdout.strip()

    def start(self, cwd, sid, title=None):
        out = self.hook("session_start.py", {"session_id": sid, "cwd": cwd, "source": "startup",
                                              "hook_event_name": "SessionStart", "session_title": title or sid})
        return json.loads(out)["hookSpecificOutput"]["additionalContext"] if out else ""

    def edit(self, cwd, sid, rel):
        payload = {"session_id": sid, "cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Edit",
                   "tool_input": {"file_path": os.path.join(cwd, rel)}}
        out = self.hook("guard.py", payload)
        if not out:
            self.hook("post_tool.py", dict(payload, hook_event_name="PostToolUse"))
            return ""
        return json.loads(out)["hookSpecificOutput"]["permissionDecision"]

    def stop(self, cwd, sid, msg, tools=()):
        out = self.hook("stop_gate.py", {"session_id": sid, "cwd": cwd, "hook_event_name": "Stop",
                                          "stop_hook_active": False, "last_assistant_message": msg,
                                          "transcript_path": self.transcript(cwd, tools)})
        return json.loads(out)["reason"] if out else ""


RU = "Сделал правку и прогнал тесты: 12 из 12 зелёные. Ничего от тебя не нужно, работаю дальше по плану."


class Lanes(unittest.TestCase):
    def test_sibling_is_visible(self):
        r = Repo()
        a, b = r.worktree("one"), r.worktree("two")
        r.start(a, "sess-a", "Промокоды")
        ctx = r.start(b, "sess-b")
        self.assertIn("Промокоды", ctx)
        self.assertIn("ListAgents", ctx)

    def test_empty_lane_moves_to_development(self):
        r = Repo()
        w = r.worktree("fresh")                        # the app's default: origin/HEAD = main
        ctx = r.start(w, "s1")
        self.assertIn("origin/development", ctx)
        self.assertTrue(os.path.exists(os.path.join(w, "dev.txt")))

    def test_lane_with_own_commit_is_not_moved(self):
        r = Repo()
        w = r.worktree("busy")
        commit(w, "mine.txt", "x", "my work")
        r.start(w, "s1")
        self.assertFalse(os.path.exists(os.path.join(w, "dev.txt")))

    def test_configured_base_branch_wins(self):
        r = Repo()
        os.makedirs(os.path.join(r.main, ".claude"), exist_ok=True)
        w = r.worktree("cfg")
        os.makedirs(os.path.join(w, ".claude"), exist_ok=True)
        with open(os.path.join(w, ".claude", "follow-through.json"), "w") as fh:
            json.dump({"base_branch": "main"}, fh)
        r.start(w, "s1")
        self.assertFalse(os.path.exists(os.path.join(w, "dev.txt")))

    def test_overlap_denied_once(self):
        r = Repo()
        a, b = r.worktree("one", "origin/development"), r.worktree("two", "origin/development")
        r.start(a, "sa"); r.start(b, "sb")
        self.assertEqual(r.edit(a, "sa", "a.txt"), "")
        self.assertEqual(r.edit(b, "sb", "a.txt"), "deny")
        self.assertEqual(r.edit(b, "sb", "a.txt"), "")          # after the first stop it passes
        self.assertEqual(r.edit(b, "sb", "other.txt"), "")

    def test_same_tree_denied_once(self):
        r = Repo()
        w = r.worktree("shared", "origin/development")
        r.start(w, "s1")
        ctx = r.start(w, "s2")
        self.assertIn("THIS tree", ctx)
        self.assertEqual(r.edit(w, "s2", "x.txt"), "deny")
        self.assertEqual(r.edit(w, "s2", "x.txt"), "")

    def test_stale_sibling_is_ignored(self):
        r = Repo()
        a, b = r.worktree("one", "origin/development"), r.worktree("two", "origin/development")
        r.start(a, "old")
        reg = os.path.join(r.main, ".git", "follow-through", "sessions", "old.json")
        e = jload(reg); e["heartbeat"] -= 3600; e["files"] = ["a.txt"]
        jsave(reg, e)
        r.start(b, "new")
        self.assertEqual(r.edit(b, "new", "a.txt"), "")

    def test_session_end_removes_entry(self):
        r = Repo()
        w = r.worktree("one", "origin/development")
        r.start(w, "s1")
        r.hook("session_end.py", {"session_id": "s1", "cwd": w})
        self.assertFalse(os.path.exists(os.path.join(r.main, ".git", "follow-through", "sessions", "s1.json")))

    def test_killing_a_siblings_container_asks(self):
        r = Repo()
        a, b = r.worktree("one", "origin/development"), r.worktree("two", "origin/development")
        r.start(a, "sa")
        reg = os.path.join(r.main, ".git", "follow-through", "sessions", "sa.json")
        e = jload(reg); e["containers"] = ["proj_one_app"]; jsave(reg, e)
        r.start(b, "sb")
        out = r.hook("guard.py", {"session_id": "sb", "cwd": b, "tool_name": "Bash",
                                  "tool_input": {"command": "docker stop proj_one_app"}})
        self.assertEqual(json.loads(out)["hookSpecificOutput"]["permissionDecision"], "ask")
        out = r.hook("guard.py", {"session_id": "sb", "cwd": b, "tool_name": "Bash",
                                  "tool_input": {"command": "docker stop proj_two_app"}})
        self.assertEqual(out, "")

    def test_prompt_injects_only_on_change(self):
        r = Repo()
        a, b = r.worktree("one", "origin/development"), r.worktree("two", "origin/development")
        r.start(b, "sb")
        p = {"session_id": "sb", "cwd": b, "hook_event_name": "UserPromptSubmit", "prompt": "дальше"}
        self.assertEqual(r.hook("prompt_submit.py", p), "")          # nothing changed since start
        r.start(a, "sa", "Возвраты")
        self.assertIn("Возвраты", r.hook("prompt_submit.py", p))     # a sibling appeared
        self.assertEqual(r.hook("prompt_submit.py", p), "")


class Freshness(unittest.TestCase):
    def test_done_while_base_moved_under_my_files_blocks(self):
        r = Repo()
        w = r.worktree("lane", "origin/development")
        r.start(w, "s1")
        r.edit(w, "s1", "a.txt")
        commit(r.main, "a.txt", "changed elsewhere\n", "sibling changes a.txt")
        sh(r.main, "push", "-q", "origin", "development")
        sh(w, "fetch", "-q", "origin")
        self.assertIn("Rebase", r.stop(w, "s1", "Готово, всё работает. " + RU))
        self.assertNotIn("Rebase", r.stop(w, "s1", "Прогнал тесты: 12 из 12. Ничего от тебя не нужно, работаю дальше."))

    def test_unrelated_base_move_passes(self):
        r = Repo()
        w = r.worktree("lane", "origin/development")
        r.start(w, "s1")
        r.edit(w, "s1", "a.txt")
        commit(r.main, "b.txt", "other\n", "unrelated")
        sh(r.main, "push", "-q", "origin", "development")
        sh(w, "fetch", "-q", "origin")
        self.assertEqual(r.stop(w, "s1", "Готово. " + RU), "")


STATUS = """---
mirror: https://claude.ai/artifact/abc
environments:
  staging:
    branch: origin/development
    deploy_cmd: deploy\\.sh staging
---
# Status

| ID | Item | Status | Lane | Proof | Updated |
|---|---|---|---|---|---|
| P1 | Возвраты из админки | doing | refunds | | |
"""


class Status(unittest.TestCase):
    def repo_with_status(self):
        r = Repo()
        w = r.worktree("lane", "origin/development")
        os.makedirs(os.path.join(w, "docs", "ai"))
        with open(os.path.join(w, "docs", "ai", "status.md"), "w") as fh:
            fh.write(STATUS)
        return r, w

    def test_commit_without_status_update_blocks(self):
        r, w = self.repo_with_status()
        reason = r.stop(w, "s1", RU, tools=[("Bash", {"command": "git commit -m 'feat: refunds'"})])
        self.assertIn("status.md was not updated", reason)

    def test_escape_line_passes(self):
        r, w = self.repo_with_status()
        msg = RU + "\nстатус не меняется: это правка опечатки в тесте."
        self.assertEqual(r.stop(w, "s1", msg, tools=[("Bash", {"command": "git commit -m 'fix typo'"})]), "")

    def test_status_edit_without_mirror_publish_blocks(self):
        r, w = self.repo_with_status()
        tools = [("Bash", {"command": "git commit -m x"}),
                 ("Edit", {"file_path": os.path.join(w, "docs/ai/status.md")})]
        self.assertIn("mirror", r.stop(w, "s1", RU, tools=tools))

    def test_status_edit_with_mirror_publish_passes(self):
        r, w = self.repo_with_status()
        tools = [("Bash", {"command": "git commit -m x"}),
                 ("Edit", {"file_path": os.path.join(w, "docs/ai/status.md")}),
                 ("Artifact", {"url": "https://claude.ai/artifact/abc", "file_path": "/tmp/x.html"})]
        self.assertEqual(r.stop(w, "s1", RU, tools=tools), "")

    def test_deploy_is_recorded_and_shown(self):
        r, w = self.repo_with_status()
        r.start(w, "s1")
        r.hook("post_tool.py", {"session_id": "s1", "cwd": w, "tool_name": "Bash",
                                "tool_input": {"command": "./deploy.sh staging"}})
        deploys = jload(os.path.join(r.main, ".git", "follow-through", "deploys.json"))
        self.assertIn("staging", deploys)
        reason = r.stop(w, "s1", RU, tools=[("Bash", {"command": "./deploy.sh staging"})])
        self.assertIn("deployed", reason)

    def test_siblings_doing_rows_are_visible(self):
        r, w = self.repo_with_status()
        own = r.start(w, "s1", "Возвраты")
        self.assertIn("staging: origin/development", own)
        other = r.worktree("other", "origin/development")
        ctx = r.start(other, "s2")
        self.assertIn("doing: P1", ctx)


class Memory(unittest.TestCase):
    def test_stale_memory_is_listed(self):
        r = Repo()
        enc = re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(r.main))
        d = os.path.join(r.home, ".claude", "projects", enc, "memory")
        os.makedirs(d)
        with open(os.path.join(d, "fact.md"), "w") as fh:
            fh.write("The importer lives in `app/Services/OldImporter.php`; config in `a.txt/none.md`.\n")
        with open(os.path.join(d, "ok.md"), "w") as fh:
            fh.write("Seeds are in `docs/x.md`? no — see `dev.txt/a.md`\n")
        ctx = r.start(r.main, "s1")
        self.assertIn("app/Services/OldImporter.php", ctx)


if __name__ == "__main__":
    unittest.main()
