"""follow-through :: executable proof for wave 41 — the gates judge where the work is.

Reproduces project A, 2026-10-21: a session opened in an empty folder with no git worked in a lane through
`cd <lane> && …` and Edit / Write by absolute path, and no follow-through gate saw the lane. Each case builds
a real repository (test_lanes.Repo) and drives the real hook scripts in subprocesses with an isolated HOME.
Run: python3 -m unittest discover -s follow-through/hooks/tests
"""

import json
import os
import subprocess
import unittest

from test_lanes import HOOKS, RU, STATUS, Repo, commit, jload, sh

GROUNDWORK_PARSER = os.path.join(HOOKS, "..", "..", "hooks", "gw_repo.py")


def outside(r):
    """The empty folder the session was opened in."""
    e = os.path.join(r.root, "empty-folder")
    os.makedirs(e, exist_ok=True)
    return e


def guard(r, cwd, cmd, sid="sa"):
    """(decision, reason) of guard.py for a Bash call; ("", "") when it says nothing."""
    out = r.hook("guard.py", {"session_id": sid, "cwd": cwd, "hook_event_name": "PreToolUse",
                              "tool_name": "Bash", "tool_input": {"command": cmd}})
    if not out:
        return "", ""
    h = json.loads(out)["hookSpecificOutput"]
    return h["permissionDecision"], h["permissionDecisionReason"]


def edit(r, cwd, sid, path):
    """An Edit by absolute path as the harness runs it: guard.py, then post_tool.py when allowed."""
    payload = {"session_id": sid, "cwd": cwd, "hook_event_name": "PreToolUse", "tool_name": "Edit",
               "tool_input": {"file_path": path}}
    out = r.hook("guard.py", payload)
    if out:
        h = json.loads(out)["hookSpecificOutput"]
        return h["permissionDecision"], h["permissionDecisionReason"]
    r.hook("post_tool.py", dict(payload, hook_event_name="PostToolUse"))
    return "", ""


def ran(r, cwd, sid, cmd):
    r.hook("post_tool.py", {"session_id": sid, "cwd": cwd, "hook_event_name": "PostToolUse", "tool_name": "Bash",
                            "tool_input": {"command": cmd}})


def registry(r, sid):
    p = os.path.join(r.main, ".git", "follow-through", "sessions", sid + ".json")
    return jload(p) if os.path.exists(p) else {}


def with_status(r, w, deploy_cmd=None, gates=None):
    os.makedirs(os.path.join(w, "docs", "ai"), exist_ok=True)
    with open(os.path.join(w, "docs", "ai", "status.md"), "w") as fh:
        fh.write(STATUS if deploy_cmd is None else STATUS.replace("deploy\\.sh staging", deploy_cmd))
    if gates:
        os.makedirs(os.path.join(w, ".claude"), exist_ok=True)
        with open(os.path.join(w, ".claude", "follow-through.json"), "w") as fh:
            json.dump({"gates": gates}, fh)


def repo(r, name):
    path = os.path.join(r.root, name)
    subprocess.run(["git", "init", "-q", path], check=True)
    return path


class Parser(unittest.TestCase):
    def test_the_copy_is_groundworks_module_byte_for_byte(self):
        if not os.path.isfile(GROUNDWORK_PARSER):
            self.skipTest("groundwork's hooks/gw_repo.py is not beside this plugin (an installed copy)")
        with open(os.path.join(HOOKS, "gw_repo.py"), "rb") as a, open(GROUNDWORK_PARSER, "rb") as b:
            self.assertTrue(a.read() == b.read(), "follow-through/hooks/gw_repo.py differs from hooks/gw_repo.py — "
                            "copy groundwork's module over it: cp hooks/gw_repo.py follow-through/hooks/gw_repo.py")


class Destructive(unittest.TestCase):
    """FT41-AC1: a git command that discards changes asks in the tree it runs in, as it does in that tree."""

    def setUp(self):
        self.r = Repo()
        self.lane = self.r.worktree("lane", "origin/development")
        with open(os.path.join(self.lane, "a.txt"), "w") as fh:
            fh.write("uncommitted\n")
        self.e = outside(self.r)

    def test_cd_lane_reset_hard_from_an_empty_folder_asks(self):
        decision, reason = guard(self.r, self.e, "cd %s && git reset --hard" % self.lane)
        self.assertEqual(decision, "ask")
        self.assertIn(self.lane, reason)

    def test_the_same_command_asks_in_the_lane_itself(self):
        self.assertEqual(guard(self.r, self.lane, "git reset --hard")[0], "ask")

    def test_every_form_that_names_the_lane_asks(self):
        for cmd in ("git -C %s checkout -- ." % self.lane,
                    "bash -lc 'cd %s && git stash drop'" % self.lane,
                    "L=%s; cd $L && git clean -fd" % self.lane,
                    "cd %s && git restore a.txt 2>&1 | tail -3" % self.lane,
                    "cd %s && git reset -q --hard origin/development" % self.lane):
            self.assertEqual(guard(self.r, self.e, cmd)[0], "ask", cmd)

    def test_unstaging_in_the_lane_passes(self):
        self.assertEqual(guard(self.r, self.e, "cd %s && git restore --staged a.txt" % self.lane)[0], "")

    def test_a_folder_the_line_does_not_name_asks(self):
        decision, reason = guard(self.r, self.e, 'cd "$LANE" && git reset --hard')
        self.assertEqual(decision, "ask")
        self.assertIn("does not name", reason)

    def test_a_clean_lane_from_a_dirty_main_checkout_passes(self):
        sh(self.lane, "checkout", "--", "a.txt")
        with open(os.path.join(self.r.main, "a.txt"), "w") as fh:
            fh.write("main is dirty\n")
        self.assertEqual(guard(self.r, self.r.main, "cd %s && git reset --hard" % self.lane)[0], "")
        self.assertEqual(guard(self.r, self.r.main, "git reset --hard")[0], "ask")

    def test_a_dirty_lane_from_a_clean_main_checkout_asks(self):
        with open(os.path.join(self.r.main, ".git", "info", "exclude"), "a") as fh:
            fh.write(".claude/\n")                                      # the lanes inside it
        self.assertEqual(guard(self.r, self.r.main, "git checkout -- a.txt")[0], "")
        self.assertEqual(guard(self.r, self.r.main, "cd %s && git checkout -- a.txt" % self.lane)[0], "ask")

    def test_the_lanes_own_switch_holds(self):
        os.makedirs(os.path.join(self.lane, ".claude"), exist_ok=True)
        with open(os.path.join(self.lane, ".claude", "follow-through.json"), "w") as fh:
            json.dump({"gates": {"destructive": False}}, fh)
        self.assertEqual(guard(self.r, self.lane, "git reset --hard")[0], "")
        self.assertEqual(guard(self.r, self.e, "cd %s && git reset --hard" % self.lane)[0], "")

    def test_the_session_folders_switch_does_not_hold_for_another_tree(self):
        other = self.r.worktree("other", "origin/development")
        os.makedirs(os.path.join(other, ".claude"), exist_ok=True)
        with open(os.path.join(other, ".claude", "follow-through.json"), "w") as fh:
            json.dump({"gates": {"destructive": False}}, fh)
        self.assertEqual(guard(self.r, other, "git reset --hard")[0], "")
        self.assertEqual(guard(self.r, other, "cd %s && git reset --hard" % self.lane)[0], "ask")
        self.assertEqual(guard(self.r, other, "cd %s && ./vendor/bin/sail artisan migrate:fresh" % self.lane)[0], "ask")
        self.assertEqual(guard(self.r, other, "echo '{}' > %s/.claude/follow-through.json" % self.lane)[0], "ask")

    def test_each_check_holds_by_the_tree_of_its_own_command(self):
        other = self.r.worktree("other", "origin/development")
        with_status(self.r, other, gates={"destructive": False})
        line = "./vendor/bin/sail artisan migrate:fresh && git -C %s status" % self.lane   # the lane is only read
        self.assertEqual(guard(self.r, other, line)[0], "")
        self.assertEqual(guard(self.r, self.lane, "./vendor/bin/sail artisan migrate:fresh")[0], "ask")


class Status(unittest.TestCase):
    """FT41-AC2: a commit or deploy in a repository the turn worked in needs that repository's status."""

    def setUp(self):
        self.r = Repo()
        self.lane = self.r.worktree("lane", "origin/development")
        with_status(self.r, self.lane)
        self.e = outside(self.r)

    def test_commit_in_the_lane_from_an_empty_folder_blocks_like_the_lane_itself(self):
        line = "cd %s && git commit -am 'E8: redirect a signed-in admin'" % self.lane
        there = self.r.stop(self.e, "sa", RU, tools=[("Bash", {"command": line})])
        here = self.r.stop(self.lane, "sb", RU, tools=[("Bash", {"command": "git commit -am 'E8'"})])
        self.assertIn("was not updated", here)
        self.assertIn("was not updated", there)
        self.assertIn(self.lane, there)

    def test_every_form_that_names_the_lane_blocks(self):
        for line in ("git -C %s commit -m x" % self.lane,
                     "L=%s; cd $L && git cherry-pick abc1234" % self.lane,
                     "cd %s && git commit -q -F - <<'EOF'\nfix: don't (re)break it\nEOF" % self.lane):
            self.assertIn("was not updated", self.r.stop(self.e, "sa", RU, tools=[("Bash", {"command": line})]), line)

    def test_status_edited_in_the_lane_passes(self):
        tools = [("Edit", {"file_path": os.path.join(self.lane, "docs/ai/status.md")}),
                 ("Bash", {"command": "cd %s && git commit -am x" % self.lane})]
        self.assertEqual(self.r.stop(self.e, "sa", RU, tools=tools), "")

    def test_status_written_by_the_shell_in_the_lane_passes(self):
        line = "cd %s && sed -i '' 's/| doing |/| done |/' docs/ai/status.md && git commit -am x" % self.lane
        self.assertEqual(self.r.stop(self.e, "sa", RU, tools=[("Bash", {"command": line})]), "")

    def test_a_commit_in_another_repository_does_not_ask_for_this_ones_status(self):
        other = os.path.join(self.r.root, "other")
        subprocess.run(["git", "init", "-q", other], check=True)
        line = "cd %s && git commit --allow-empty -m x" % other
        self.assertEqual(self.r.stop(self.lane, "sb", RU, tools=[("Bash", {"command": line})]), "")

    def test_a_commit_in_a_folder_the_line_does_not_name_counts_here(self):
        line = 'cd "$X" && git commit -am x'
        self.assertIn("was not updated", self.r.stop(self.lane, "sb", RU, tools=[("Bash", {"command": line})]))

    def test_main_checkout_session_updating_the_lanes_status_passes(self):
        with_status(self.r, self.r.main)
        tools = [("Edit", {"file_path": os.path.join(self.lane, "docs/ai/status.md")}),
                 ("Bash", {"command": "cd %s && git commit -am x" % self.lane})]
        self.assertEqual(self.r.stop(self.r.main, "sm", RU, tools=tools), "")

    def test_a_commit_in_a_sibling_worktree_needs_that_worktrees_status(self):
        line = "cd %s && git commit -am x" % self.lane
        reason = self.r.stop(self.r.main, "sm", RU, tools=[("Bash", {"command": line})])   # main has no status
        self.assertIn("was not updated", reason)
        self.assertIn(self.lane, reason)

    def test_another_worktrees_status_is_not_this_ones(self):
        with_status(self.r, self.r.main)
        tools = [("Edit", {"file_path": os.path.join(self.r.main, "docs/ai/status.md")}),
                 ("Bash", {"command": "git commit -am x"})]
        self.assertIn("was not updated", self.r.stop(self.lane, "sb", RU, tools=tools))

    def test_the_session_folders_switch_does_not_hold_for_another_tree(self):
        other = self.r.worktree("other", "origin/development")
        os.makedirs(os.path.join(other, ".claude"), exist_ok=True)
        with open(os.path.join(other, ".claude", "follow-through.json"), "w") as fh:
            json.dump({"gates": {"status": False}}, fh)
        line = "cd %s && git commit -am x" % self.lane
        self.assertIn("was not updated", self.r.stop(other, "so", RU, tools=[("Bash", {"command": line})]))

    def test_a_cd_kept_from_an_earlier_call_is_read_from_the_transcript(self):
        path = os.path.join(self.r.root, "kept-cd.jsonl")
        with open(path, "w") as fh:
            fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": "сделай задачу целиком"}}) + "\n")
            for cwd, cmd in ((self.e, "cd %s" % self.lane), (self.lane, "git commit -am x")):
                fh.write(json.dumps({"type": "assistant", "cwd": cwd, "message": {"content": [
                    {"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}) + "\n")
        out = self.r.hook("stop_gate.py", {"session_id": "sa", "cwd": self.e, "hook_event_name": "Stop",
                                           "stop_hook_active": False, "last_assistant_message": RU,
                                           "transcript_path": path})
        self.assertIn(self.lane, json.loads(out)["reason"])

    def test_the_own_pattern_reads_the_whole_line_as_before(self):
        mine = repo(self.r, "mine")
        with_status(self.r, mine, deploy_cmd="make build && rsync")
        with_status(self.r, self.lane, deploy_cmd="rsync", gates={"status": False})
        edit(self.r, mine, "sa", os.path.join(self.lane, "b.php"))           # an earlier turn in the lane
        line = "cd %s && make build && rsync -a dist prod:/srv" % mine
        reason = self.r.stop(mine, "sa", RU, tools=[("Bash", {"command": line})])
        self.assertIn("was not updated", reason)
        self.assertNotIn(self.lane, reason)

    def test_a_script_of_the_sessions_own_tree_is_never_another_repositorys_deploy(self):
        mine = repo(self.r, "mine")                                          # no status, no environments
        edit(self.r, mine, "sa", os.path.join(self.lane, "b.php"))
        line = "cd %s && ./deploy.sh staging" % mine
        self.assertEqual(self.r.stop(mine, "sa", RU, tools=[("Bash", {"command": line})]), "")
        ran(self.r, mine, "sa", line)
        self.assertFalse(os.path.exists(os.path.join(self.r.main, ".git", "follow-through", "deploys.json")))

    def test_a_deploy_in_another_tree_with_the_same_pattern_still_asks_here(self):
        mine = repo(self.r, "mine")
        with_status(self.r, mine)
        line = "cd %s && ./deploy.sh staging" % self.lane
        reason = self.r.stop(mine, "sa", RU, tools=[("Bash", {"command": line})])
        self.assertIn("- This turn committed or deployed, and", reason)          # the session's own, as in 0.3.1
        self.assertIn(self.lane, reason)                                       # and the lane it ran in

    def test_a_deploy_run_in_the_sessions_own_tree_is_its_own(self):
        mine = os.path.join(self.r.root, "mine")
        subprocess.run(["git", "init", "-q", mine], check=True)
        with_status(self.r, mine)                                           # the same deploy_cmd as the lane's
        edit(self.r, mine, "sa", os.path.join(self.lane, "b.php"))           # an earlier turn in the lane
        tools = [("Edit", {"file_path": os.path.join(mine, "docs/ai/status.md")}),
                 ("Bash", {"command": "cd %s && ./deploy.sh staging" % mine})]
        self.assertEqual(self.r.stop(mine, "sa", RU, tools=tools), "")
        ran(self.r, mine, "sa", "cd %s && ./deploy.sh staging" % mine)
        self.assertTrue(os.path.exists(os.path.join(mine, ".git", "follow-through", "deploys.json")))
        self.assertFalse(os.path.exists(os.path.join(self.r.main, ".git", "follow-through", "deploys.json")))

    def test_push_from_an_empty_folder_asks_for_the_mirror(self):
        sh(self.lane, "add", "docs/ai/status.md"); sh(self.lane, "commit", "-qm", "status")
        sh(self.lane, "push", "-q", "origin", "HEAD:development"); sh(self.lane, "fetch", "-q", "origin")
        line = "cd %s && git push origin HEAD:development 2>&1 | tail -8" % self.lane
        reason = self.r.stop(self.e, "sa", RU, tools=[("Bash", {"command": line})])
        self.assertIn("--ref origin/development", reason)
        self.assertIn(self.lane, reason)

    def test_an_ssh_deploy_finds_the_lane_the_session_worked_in_before(self):
        edit(self.r, self.e, "sa", os.path.join(self.lane, "bootstrap.php"))       # an earlier turn
        reason = self.r.stop(self.e, "sa", RU, tools=[("Bash", {"command": "ssh deploy@host 'cd /srv && ./deploy.sh staging'"})])
        self.assertIn("was not updated", reason)
        self.assertIn(self.lane, reason)

    def test_an_ssh_deploy_names_no_repository_on_its_own(self):
        line = "ssh deploy@host 'cd /srv && ./deploy.sh staging'"
        self.assertEqual(self.r.stop(self.e, "sa", RU, tools=[("Bash", {"command": line})]), "")


class Registry(unittest.TestCase):
    """FT41-AC3: a session working in a lane from outside is registered there, and taken out at its end."""

    def setUp(self):
        self.r = Repo()
        self.lane = self.r.worktree("lane", "origin/development")
        self.e = outside(self.r)

    def test_an_edit_from_outside_meets_the_lanes_session(self):
        self.r.start(self.lane, "sb", "Промокоды")
        self.assertEqual(self.r.edit(self.lane, "sb", "a.txt"), "")
        path = os.path.join(self.lane, "a.txt")
        decision, reason = edit(self.r, self.e, "sa", path)
        self.assertEqual(decision, "deny")
        self.assertIn("Промокоды", reason)
        self.assertIn(self.lane, reason)
        decision, reason = edit(self.r, self.e, "sa", path)              # the same tree is acknowledged …
        self.assertEqual(decision, "deny")
        self.assertIn("being edited", reason)                           # … the same file is not, yet
        self.assertEqual(edit(self.r, self.e, "sa", path), ("", ""))
        me = registry(self.r, "sa")
        self.assertEqual(me["cwd"], self.lane)
        self.assertEqual(me["opened_in"], os.path.realpath(self.e))
        self.assertIn("a.txt", me["files"])

    def test_a_shared_folder_is_met_on_the_first_edit_wherever_the_file_is(self):
        self.r.start(self.lane, "sb")
        self.r.start(self.lane, "sa")
        notes = os.path.join(self.r.root, "notes", "plan.md")                    # outside git, as in wave 35
        decision, reason = edit(self.r, self.lane, "sa", notes)
        self.assertEqual(decision, "deny")
        self.assertIn("works in this same tree", reason)
        self.assertEqual(edit(self.r, self.lane, "sa", notes), ("", ""))

    def test_the_lanes_session_sees_the_one_from_outside(self):
        self.r.start(self.lane, "sb")
        path = os.path.join(self.lane, "b.txt")
        self.assertEqual(edit(self.r, self.e, "sa", path)[0], "deny")       # the lane is sb's tree
        self.assertEqual(edit(self.r, self.e, "sa", path), ("", ""))
        decision, reason = edit(self.r, self.lane, "sb", path)              # sa works in sb's tree now …
        self.assertEqual(decision, "deny")
        self.assertIn("sa (opened in empty-folder)", reason)
        decision, reason = edit(self.r, self.lane, "sb", path)              # … and edited b.txt there
        self.assertIn("b.txt is being edited by another live session", reason)

    def test_a_command_that_changes_the_lane_registers_and_reading_does_not(self):
        ran(self.r, self.e, "sr", "cd %s && git status && git log -3" % self.lane)
        self.assertEqual(registry(self.r, "sr"), {})
        ran(self.r, self.e, "sa", "cd %s && ./vendor/bin/sail artisan migrate" % self.lane)
        self.assertEqual(registry(self.r, "sa")["cwd"], self.lane)
        ran(self.r, self.e, "sc", "cd %s && git status && git commit -am x" % self.lane)   # a read before the change
        self.assertEqual(registry(self.r, "sc")["cwd"], self.lane)

    def test_session_end_takes_it_out_of_the_lanes_registry(self):
        edit(self.r, self.e, "sa", os.path.join(self.lane, "a.txt"))
        self.assertTrue(registry(self.r, "sa"))
        self.r.hook("session_end.py", {"session_id": "sa", "cwd": self.e, "hook_event_name": "SessionEnd"})
        self.assertEqual(registry(self.r, "sa"), {})
        self.assertFalse(os.path.exists(os.path.join(self.r.home, ".claude", "follow-through", "outside", "sa.jsonl")))

    def test_a_deploy_from_the_lane_is_recorded_with_the_lanes_commit(self):
        with_status(self.r, self.lane)
        ran(self.r, self.e, "sa", "cd %s && ./deploy.sh staging" % self.lane)
        deploys = jload(os.path.join(self.r.main, ".git", "follow-through", "deploys.json"))
        self.assertEqual(deploys["staging"]["commit"], sh(self.lane, "rev-parse", "HEAD"))

    def test_done_while_the_base_moved_under_the_lanes_files_blocks(self):
        edit(self.r, self.e, "sa", os.path.join(self.lane, "a.txt"))
        commit(self.r.main, "a.txt", "changed elsewhere\n", "a sibling changes a.txt")
        sh(self.r.main, "push", "-q", "origin", "development")
        sh(self.lane, "fetch", "-q", "origin")
        reason = self.r.stop(self.e, "sa", "Готово, всё работает. " + RU)
        self.assertIn("Rebase", reason)
        self.assertIn(self.lane, reason)


if __name__ == "__main__":
    unittest.main()
