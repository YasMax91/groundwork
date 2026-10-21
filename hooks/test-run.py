#!/usr/bin/env python3
"""Groundwork plugin :: the one way to run tests the gates will accept (wave 38).

    test-run.py --close            the change's close tests that have not passed on this exact code yet
    test-run.py --for-push [REF]   exactly what the push check still needs for REF (default HEAD)
    test-run.py --whole            the whole suite on the working tree

Start --for-push and --whole with `run_in_background: true` and wait for the notification: a whole run of
otaje (5944 tests on 2026-10-20) no longer fits one 10-minute Bash call. Agents used to cut it by hand into
3-5 folder chunks, which nothing recorded, and then asked the owner to record the pass by hand (15 such
questions in two weeks). This runner cuts the suite itself — chunks of at most ~8 minutes by recorded
duration, or one `commands.test_full` run (parallel) — re-runs once the files that failed only because the
database connection dropped (`SQLSTATE[HY000] [2002]` / `[2006]`: shared-mysql restarts under load), and
records what passed by the exact code (gw_tests). It holds the test-database lock for the whole run, so a
Stop gate in the same lane waits instead of wiping the run's fixtures.

Exit: 0 green and recorded · 2 tests failed · 1 could not run (environment, lock, the tree is not REF).
"""

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gw_tests as gw  # noqa: E402

HOOKS = os.path.dirname(os.path.abspath(__file__))
CONN = re.compile(r"SQLSTATE\[HY000\] \[(2002|2006)\]|MySQL server has gone away|Connection refused")
ENV = re.compile(r"is not defined|Could not open input file|command not found|No such container|Cannot connect|"
                 r"Is the docker daemon running|permission denied while trying to connect")
CHUNK_SECONDS = 480


def say(msg):
    print(msg, flush=True)


def base_cmd(cfg):
    cmds = cfg.get("commands") or {}
    if cmds.get("test"):
        return cmds["test"]
    return "php artisan test" if str(cfg.get("runner") or "").strip().lower() == "host" else "./vendor/bin/sail artisan test"


def selectable(cmd):
    return bool(re.search(r"artisan test|phpunit|/pest( |$)|paratest", cmd))


# --------------------------------------------------------------------------------------------- lock ---

class Lock:
    """The same lock test-gate.sh takes: `<git-common-dir>/groundwork/locks/test-db-<test database>`."""

    def __init__(self, top, label):
        db = ""
        try:
            m = re.search(r'name="DB_DATABASE"[^>]*value="([^"]*)"', open(os.path.join(top, "phpunit.xml"), encoding="utf-8").read())
            db = m.group(1) if m else ""
        except Exception:
            pass
        if not db:
            try:
                for line in open(os.path.join(top, ".env.testing"), encoding="utf-8"):
                    if re.match(r"\s*DB_DATABASE\s*=", line):
                        db = line.split("=", 1)[1].strip().strip("\"' ")
                        break
            except Exception:
                pass
        db = re.sub(r"[^A-Za-z0-9_.-]", "_", db or "default")
        common = gw.common_dir(top)
        self.path = os.path.join(common, "groundwork", "locks", "test-db-" + db) if common else ""
        self.owner = "run-%d" % os.getpid()
        self.label = label
        self.held = False

    def acquire(self, wait=900, stale=1800):
        if not self.path:
            return True
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
        except Exception:
            return True                # cannot manage locks here: run unlocked, never stall
        waited = 0
        while True:
            try:
                os.mkdir(self.path)
                for name, text in (("owner", self.owner), ("label", self.label)):
                    with open(os.path.join(self.path, name), "w") as fh:
                        fh.write(text + "\n")
                self.held = True
                return True
            except FileExistsError:
                try:
                    gone = self.owner_is_gone()
                    if time.time() - os.path.getmtime(self.path) > stale or gone:
                        if gone:
                            say("took over the test-database lock of a run that no longer exists")
                        self.clean_orphans()
                        shutil.rmtree(self.path, ignore_errors=True)
                        continue
                except Exception:
                    pass
                if waited >= wait:
                    return False
                time.sleep(2)
                waited += 2
            except Exception:
                return True            # cannot manage locks here: run unlocked, never stall

    def owner_is_gone(self):
        """The holder died without releasing — a session restarted mid-run (otaje, 2026-10-21: the host-side
        runner was killed, the suite went on inside the container, and the lock would have held for 30 min)."""
        try:
            pid = int(re.sub(r"\D", "", open(os.path.join(self.path, "owner")).read()) or "0")
        except Exception:
            return False
        if pid <= 0:
            return False
        try:
            os.kill(pid, 0)
            return False
        except ProcessLookupError:
            return True
        except Exception:
            return False

    def clean_orphans(self):
        """Under Sail the dead holder's PHP processes outlive it inside the container: stop them first."""
        sail = os.path.join(os.getcwd(), "vendor", "bin", "sail")
        if not os.path.isfile(sail):
            return
        svc = "laravel.test"
        try:
            for line in open(os.path.join(os.getcwd(), ".env"), encoding="utf-8"):
                if line.startswith("APP_SERVICE="):
                    svc = line.split("=", 1)[1].strip().strip("\"'") or svc
        except Exception:
            pass
        subprocess.run([sail, "exec", "-T", svc, "pkill", "-f", "artisan test|vendor/bin/phpunit|vendor/bin/pest|paratest"],
                       capture_output=True, timeout=60)

    def busy_with(self):
        try:
            return open(os.path.join(self.path, "label")).read().strip()
        except Exception:
            return "another session"

    def release(self):
        if self.held:
            try:
                if open(os.path.join(self.path, "owner")).read().strip() == self.owner:
                    shutil.rmtree(self.path, ignore_errors=True)
            except Exception:
                pass


# ---------------------------------------------------------------------------------------------- runs ---

class Runner:
    def __init__(self, top, cfg):
        self.top, self.cfg, self.n = top, cfg, 0
        self.cmd = base_cmd(cfg)

    def _junit(self):
        d = os.path.join(self.top, "storage", "framework", "testing")
        if not os.path.isdir(d):
            return ""
        self.n += 1
        return os.path.join("storage", "framework", "testing", "gw-junit-%d-%d.xml" % (os.getpid(), self.n))

    def once(self, cmd, files):
        """(exit status, output, per-file JUnit results)."""
        j = self._junit()
        argv = shlex.split(cmd) + (["--log-junit=" + j] if j else []) + list(files)
        try:
            r = subprocess.run(argv, cwd=self.top, capture_output=True, text=True)
            status, out = r.returncode, (r.stdout or "") + (r.stderr or "")
        except FileNotFoundError as e:
            status, out = 127, str(e)
        results = {}
        if j:
            path = os.path.join(self.top, j)
            results = gw.junit_results(path, self.top)
            if results:
                gw.record_durations({f: v["time"] for f, v in results.items()}, self.top)
            try:
                os.unlink(path)
            except Exception:
                pass
        return status, out, results

    def environment_problem(self, status, out):
        ran = re.search(r"Tests:|PHPUnit|Failures:|assertions|OK \(|FAIL|PASS", out)
        return status == 127 or (bool(ENV.search(out)) and not ran)

    def chunk(self, files):
        known = gw.durations(self.top)
        chunks, cur, spent = [], [], 0.0
        for f in files:
            cost = float(known.get(f, 1.5))
            if cur and (spent + cost > CHUNK_SECONDS or len(cur) >= 400):
                chunks.append(cur)
                cur, spent = [], 0.0
            cur.append(f)
            spent += cost
        return chunks + ([cur] if cur else [])

    def run_set(self, cmd, files, label):
        """Run `files` in chunks; (env_problem, passed, failed)."""
        passed, failed = [], []
        chunks = self.chunk(files) if files else [[]]
        for i, ch in enumerate(chunks, 1):
            say("%s: part %d of %d, %s" % (label, i, len(chunks), ("%d files" % len(ch)) if ch else "the whole suite"))
            t0 = time.time()
            status, out, res = self.once(cmd, ch)
            if self.environment_problem(status, out):
                say(out[-1500:])
                return True, passed, failed
            line = ([l.strip() for l in out.splitlines() if "Tests:" in l] or ["(no summary)"])[-1]
            say("  %s — %ds" % (line, time.time() - t0))
            members = ch or sorted(res)
            if status == 0:
                passed += members
                continue
            bad = [f for f in members if res.get(f, {}).get("failed")]
            if bad and all(CONN.search(m) for f in bad for m in res[f]["messages"]):
                say("  %d files failed only because the database connection dropped — re-running them once" % len(bad))
                time.sleep(float(os.environ.get("GW_RETRY_PAUSE", "20")))     # let a restarting MySQL come back
                status2, out2, res2 = self.once(self.cmd, bad)
                if status2 == 0:
                    passed += members
                    continue
                res.update(res2)
                out = out2
            good = [f for f in members if f in res and not res[f]["failed"]]
            passed += good
            failed += [f for f in members if f not in good] or ["(the run, exit %d)" % status]
            say("\n".join(out.splitlines()[-30:]))
        return False, passed, failed


def guard(top, cmd):
    """lane-guard's verdict on running `cmd` here (a lane that is not provisioned must not hit the main stack)."""
    try:
        r = subprocess.run([sys.executable, os.path.join(HOOKS, "lane-guard.py")], capture_output=True, text=True, timeout=60,
                           input=json.dumps({"tool_name": "Bash", "cwd": top, "tool_input": {"command": cmd}}))
        out = json.loads(r.stdout or "{}").get("hookSpecificOutput") or {}
        return out.get("permissionDecisionReason") if out.get("permissionDecision") == "deny" else ""
    except Exception:
        return ""


def whole(top, cfg, runner):
    full = (cfg.get("commands") or {}).get("test_full")
    if full:
        env, passed, failed = runner.run_set(full, [], "whole suite (%s)" % full)
        if env or (not passed and all(f.startswith("(") for f in failed)):
            # The parallel command never ran a test: a lane whose vendor/ was cloned before brianium/paratest
            # was added (otaje, 2026-10-21) gets "requires brianium/paratest". The serial parts still prove it.
            say("commands.test_full did not run any test — running the whole suite in serial parts instead")
            full = None
    if not full:
        files = gw.suite_files(top)
        env, passed, failed = runner.run_set(runner.cmd, files, "whole suite, %d files" % len(files))
    if env:
        return 1, "NOT RECORDED: the test command could not run (environment) — nothing was verified"
    if failed:
        return 2, "NOT RECORDED: %d failed — %s" % (len(failed), ", ".join(failed[:8]))
    tree = gw.worktree_tree(top)
    gw.record_whole(tree, cwd=top)
    return 0, "RECORDED %s (the whole suite is green on this code)" % tree


def files_mode(top, runner, files, label):
    tree = gw.worktree_tree(top)
    if not selectable(runner.cmd):
        return 1, "NOT RECORDED: commands.test (%s) cannot take file paths — run --whole" % runner.cmd
    env, passed, failed = runner.run_set(runner.cmd, files, label)
    gw.record_files(tree, [f for f in passed if not f.startswith("(")], top)
    if env:
        return 1, "NOT RECORDED: the test command could not run (environment) — nothing was verified"
    if failed:
        return 2, "NOT RECORDED: %d failed — %s" % (len(failed), ", ".join(failed[:8]))
    return 0, "RECORDED %d files green on %s" % (len(passed), tree)


def main():
    args = sys.argv[1:]
    top = gw.toplevel() or os.getcwd()
    if not os.path.isfile(os.path.join(top, ".groundwork.json")):
        say("not a Groundwork project (no .groundwork.json) — nothing to do")
        return 1
    cfg = gw.config(top)
    runner = Runner(top, cfg)
    denied = guard(top, runner.cmd)
    if denied:
        say(denied)
        return 1

    if "--for-push" in args:
        i = args.index("--for-push")
        ref = args[i + 1] if i + 1 < len(args) and not args[i + 1].startswith("-") else "HEAD"
        tree, wt = gw.ref_tree(ref, top), gw.worktree_tree(top)
        if not tree or tree != wt:
            say("the working tree is not %s — commit or stash first, then run this again" % ref)
            return 1
        need = gw.requirement(tree, cfg, top)
        if need["ok"]:
            if need["kind"] == "files":
                gw.record_verified(tree, need["root_time"], need["base"], "delta", top)
            say("RECORDED %s — nothing more to run for the push" % tree)
            return 0
        mode = "whole" if need["kind"] == "whole" else "files"
        say("needed: " + need["reason"])
    elif "--whole" in args:
        mode = "whole"
    else:
        sel = gw.select(gw.WorkingTree(top))
        green = gw.passed_files(gw.worktree_tree(top), top)
        todo = [t for t in sel["close"] if t not in green]
        if not todo:
            say("RECORDED — the %d close tests already passed on this code" % len(sel["close"]))
            return 0
        need, mode = {"files": todo}, "files"

    lock = Lock(top, "test-run.py %s, started %s UTC" % (" ".join(a for a in args if not a.isdigit()) or "--close",
                                                          time.strftime("%H:%M", time.gmtime())))
    wait = int(args[args.index("--lock-wait") + 1]) if "--lock-wait" in args and args.index("--lock-wait") + 1 < len(args) else 900
    if not lock.acquire(wait=wait):
        say("NOT RUN: the test database is busy — %s. Run this again when it frees up." % lock.busy_with())
        return 1
    try:
        if mode == "whole":
            code, verdict = whole(top, cfg, runner)
        else:
            code, verdict = files_mode(top, runner, need["files"], "%d tests" % len(need["files"]))
            if code == 0 and "--for-push" in args:
                tree = gw.worktree_tree(top)
                after = gw.requirement(tree, cfg, top)
                if after["ok"] and after["kind"] == "files":
                    gw.record_verified(tree, after["root_time"], after["base"], "delta", top)
                    verdict = "RECORDED %s — the push check is satisfied" % tree
                elif not after["ok"]:
                    code, verdict = 2, "NOT RECORDED: " + after.get("reason", "the push check is still not satisfied")
    finally:
        lock.release()
    say(verdict)
    return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(1)
