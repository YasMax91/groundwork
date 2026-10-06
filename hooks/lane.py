#!/usr/bin/env python3
"""Groundwork plugin :: a lane — one worktree, its own Docker stack, its own databases (wave 35, GW35-AC1).

    python3 lane.py up [--refresh-data] [--full]   provision this worktree as an isolated lane
                                          (--full also starts horizon / scheduler / queue workers)
    python3 lane.py status                print what this lane uses
    python3 lane.py down [--purge]        stop the lane's stack; --purge also drops its databases

Why: a worktree that inherits the main checkout's `.env` runs `sail` inside the MAIN stack (whose volume
is the main checkout — another session's code), writes the shared dev database, and races the shared
test database. The 2026-10-05 audit found 4 of 26 otaje worktrees pointing at the main stack and 9 at
the main dev DB. A lane gets:

  * `.env` from the main checkout with COMPOSE_PROJECT_NAME / APP_SLUG / domain / DB_DATABASE of its own,
    free ports for anything the compose file publishes; `.env.testing` likewise;
  * `vendor/` and `node_modules/` cloned from the main checkout (copy-on-write on APFS);
  * its dev database CLONED from the main checkout's, its test database empty — on the same server when
    the project uses an external one (shared-mysql), or in its own DB container otherwise;
  * the stack started, the lane's migrations applied to the clone, and `.claude/lane.json` written so
    sibling sessions (follow-through) know which containers are this lane's.

Every step prints what it did; a step that cannot run says why and the lane continues where it can.
"""

import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys

LANE_FILE = os.path.join(".claude", "lane.json")
BACKGROUND = re.compile(r"^(horizon|scheduler|schedule|queue|queue-worker|worker|cron)$")


def say(msg):
    print("lane: " + msg, flush=True)


def run(cmd, cwd=None, timeout=900, env=None, input_text=None, shell=False):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout,
                           env=env, input=input_text, shell=shell)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except Exception as exc:  # noqa: BLE001
        return 1, str(exc)


def git(cwd, *args):
    code, out = run(["git", "-C", cwd] + list(args), timeout=20)
    return out.strip() if code == 0 else ""


def read_env(path):
    data, lines = {}, []
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except Exception:
        return data, lines
    for line in lines:
        m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*(.*)$", line)
        if m:
            data[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return data, lines


def write_env(path, lines, updates):
    seen, out = set(), []
    for line in lines:
        m = re.match(r"^\s*([A-Z0-9_]+)\s*=", line)
        if m and m.group(1) in updates:
            out.append("%s=%s" % (m.group(1), updates[m.group(1)]))
            seen.add(m.group(1))
        else:
            out.append(line)
    for k, v in updates.items():
        if k not in seen:
            out.append("%s=%s" % (k, v))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")


def lane_slug(worktree):
    words = [w for w in re.split(r"[^A-Za-z0-9]+", os.path.basename(worktree).lower()) if w]
    if not words:
        return "lane" + secrets.token_hex(2)
    slug = words[0][:6] + (words[-1][:4] if len(words) > 1 else "")
    return re.sub(r"[^a-z0-9]", "", slug)[:12]


def free_port(start):
    for port in range(start, start + 400):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", port)) != 0:
                return port
    return start


def published_port_vars(compose_text):
    """Env vars used on the host side of a `ports:` mapping."""
    out, in_ports = set(), False
    for line in compose_text.splitlines():
        stripped = line.strip()
        if stripped.startswith("ports:"):
            in_ports = True
            continue
        if in_ports and not stripped.startswith("-"):
            in_ports = False
        if in_ports:
            m = re.search(r"\$\{([A-Z0-9_]+)(?::-[^}]*)?\}\s*:", stripped)
            if m:
                out.add(m.group(1))
    return out


def fixed_container_names(compose_text):
    return [m.group(1) for m in re.finditer(r"container_name:\s*['\"]?([^'\"\s$]+)['\"]?\s*$", compose_text, re.M)]


def container_exists(name):
    code, _ = run(["docker", "inspect", "--type", "container", name], timeout=10)
    return code == 0


def mysql_in(container, sql):
    """Run SQL as root inside the DB container. The SQL goes through stdin: inside `sh -c "…"` the
    backticks around a database name are command substitution, and the statement silently does nothing."""
    code, out = run(["docker", "exec", "-i", container, "sh", "-c", 'mysql -N -s -uroot -p"$MYSQL_ROOT_PASSWORD"'],
                    timeout=120, input_text=sql + ";\n")
    lines = [l for l in out.splitlines() if not l.startswith("mysql: [Warning]")]
    return code, "\n".join(lines)


def compose_container(cwd, service, env):
    code, out = run(["docker", "compose", "ps", "-q", service], cwd=cwd, env=env, timeout=30)
    cid = out.strip().splitlines()[0] if code == 0 and out.strip() else ""
    if not cid:
        return ""
    code, out = run(["docker", "inspect", "--format", "{{.Name}}", cid], timeout=10)
    return out.strip().lstrip("/") if code == 0 else ""


def contexts(cwd):
    common = git(cwd, "rev-parse", "--path-format=absolute", "--git-common-dir")
    gitdir = git(cwd, "rev-parse", "--path-format=absolute", "--git-dir")
    top = git(cwd, "rev-parse", "--show-toplevel")
    if not common or not top:
        sys.exit("lane: not inside a git repository")
    main = os.path.dirname(common)
    if os.path.realpath(gitdir) == os.path.realpath(common):
        sys.exit("lane: this is the main checkout, not a worktree — a lane is a worktree (EnterWorktree first)")
    return top, main


def env_for(cwd):
    env = dict(os.environ)
    env.setdefault("WWWUSER", str(os.getuid()))
    env.setdefault("WWWGROUP", str(os.getgid()))
    return env


def pin_phpunit(lane, test_db):
    """Point the lane's working copy of phpunit.xml at its own test DB (skip-worktree, never committed)."""
    phpunit = os.path.join(lane, "phpunit.xml")
    if test_db and os.path.isfile(phpunit):
        try:
            xml = open(phpunit, encoding="utf-8").read()
            new_xml, n = re.subn(r'(<(?:env|server)\s+name="DB_DATABASE"\s+value=")[^"]*(")', r"\g<1>%s\g<2>" % test_db, xml)
            if n:
                run(["git", "-C", lane, "update-index", "--no-skip-worktree", "phpunit.xml"], timeout=20)
                with open(phpunit, "w", encoding="utf-8") as fh:
                    fh.write(new_xml)
                run(["git", "-C", lane, "update-index", "--skip-worktree", "phpunit.xml"], timeout=20)
                say("phpunit.xml points at %s in this lane only (skip-worktree — never committed; "
                    "before a rebase that touches it: lane.py down, rebase, lane.py up)" % test_db)
        except Exception as exc:  # noqa: BLE001
            say("phpunit.xml not adjusted: %s — tests may still use the shared test database" % exc)



def up(refresh_data=False, full=False):
    lane, main = contexts(os.getcwd())
    slug = lane_slug(lane)
    main_env, main_lines = read_env(os.path.join(main, ".env"))
    if not main_env:
        sys.exit("lane: the main checkout has no .env to start from (%s)" % main)
    compose_path = next((os.path.join(lane, f) for f in ("docker-compose.yml", "compose.yaml", "compose.yml")
                         if os.path.isfile(os.path.join(lane, f))), "")
    compose = open(compose_path, encoding="utf-8").read() if compose_path else ""

    fixed = fixed_container_names(compose)
    if fixed:
        say("WARNING: the compose file hard-codes container_name %s — a second stack of this project cannot run "
            "beside the first. Change them to \"${COMPOSE_PROJECT_NAME}_<service>\"; this lane continues, the stack "
            "start will fail until then." % ", ".join(fixed))

    project = main_env.get("COMPOSE_PROJECT_NAME") or re.sub(r"[^a-z0-9]", "", os.path.basename(main).lower())
    app_slug = main_env.get("APP_SLUG") or project.replace("_", "-")
    main_url = main_env.get("APP_URL", "")
    main_host = re.sub(r"^https?://", "", main_url).split("/")[0].split(":")[0]
    main_domain = main_env.get("APP_DOMAIN") or main_host
    lane_domain = "%s-%s.localhost" % (app_slug, slug)
    db = main_env.get("DB_DATABASE", "")

    updates = {"COMPOSE_PROJECT_NAME": "%s_%s" % (project, slug)}
    if "APP_SLUG" in main_env:
        updates["APP_SLUG"] = "%s-%s" % (app_slug, slug)
    if "APP_DOMAIN" in main_env:
        updates["APP_DOMAIN"] = lane_domain
    if main_url:
        scheme = "https" if main_url.startswith("https") else "http"
        updates["APP_URL"] = "%s://%s" % (scheme, lane_domain)
    if db:
        updates["DB_DATABASE"] = "%s_%s" % (db, slug)
    # A re-run keeps the ports this lane already owns: its own running containers hold them, so a fresh
    # probe would see them taken and move the lane to new ports under its own feet.
    lane_env, _ = read_env(os.path.join(lane, ".env"))
    base = 20000 + (int.from_bytes(slug.encode(), "little") % 2000) * 10
    taken = set()
    for i, var in enumerate(sorted(published_port_vars(compose))):
        kept = lane_env.get(var)
        if kept and kept != main_env.get(var) and kept.isdigit() and int(kept) not in taken:
            updates[var] = kept
        else:
            port = free_port(base + i * 7)
            while port in taken:
                port = free_port(port + 1)
            updates[var] = str(port)
        taken.add(int(updates[var]))
    defaults = dict(re.findall(r"\$\{([A-Z0-9_]+):-([0-9]+)\}", compose))   # ${MINIO_PORT:-9000}
    moved = {}
    for v in published_port_vars(compose):
        old_port = main_env.get(v) or defaults.get(v)
        if v in updates and old_port and old_port != updates[v]:
            moved[old_port] = updates[v]
    for k, v in main_env.items():   # every other value that names the main domain or a moved port follows the lane
        if k in updates:
            continue
        nv = v.replace(main_domain, lane_domain) if main_domain else v
        for old_port, new_port in moved.items():   # AWS_URL=http://localhost:9000/… must follow MINIO_PORT
            # host-side addresses only: inside the Compose network `minio:9000` keeps its container port
            nv = re.sub(r"((?:localhost|127\.0\.0\.1|0\.0\.0\.0|%s):)%s(?=\b|/)" % (re.escape(lane_domain), re.escape(old_port)),
                        r"\g<1>%s" % new_port, nv)
        if nv != v:
            updates[k] = nv
    write_env(os.path.join(lane, ".env"), main_lines, updates)
    say(".env written — project %s, %s, database %s" % (updates["COMPOSE_PROJECT_NAME"], lane_domain,
                                                          updates.get("DB_DATABASE", "—")))

    test_env, test_lines = read_env(os.path.join(main, ".env.testing"))
    test_db = ""
    if test_env:
        test_db = "%s_%s" % (test_env.get("DB_DATABASE", db + "_test"), slug)
        tu = {k: v for k, v in updates.items() if k in test_env and k != "DB_DATABASE"}
        tu["DB_DATABASE"] = test_db
        write_env(os.path.join(lane, ".env.testing"), test_lines, tu)
        say(".env.testing written — test database %s" % test_db)

    # phpunit.xml usually forces DB_DATABASE (6 of 10 projects on 2026-10-05; otaje with force="true"),
    # which beats .env.testing — so without this every lane still runs on the one shared test database.
    # The lane's working copy points at its own test DB and is marked skip-worktree, so the change can
    # never be committed; `lane.py down` restores the file.
    pin_phpunit(lane, test_db)

    # Private package credentials (Backpack Pro, Nova …) are git-ignored: without them a lane cannot
    # `composer install` the moment its composer.lock differs from the main checkout's.
    for f in ("auth.json",):
        src, dst = os.path.join(main, f), os.path.join(lane, f)
        if os.path.isfile(src) and not os.path.exists(dst):
            shutil.copy2(src, dst)
            say("%s copied from the main checkout" % f)

    for d in ("vendor", "node_modules"):
        src, dst = os.path.join(main, d), os.path.join(lane, d)
        if os.path.isdir(src) and not os.path.exists(dst):
            code, _ = run(["cp", "-cR", src, dst], timeout=600)
            if code != 0:
                code, _ = run(["cp", "-R", src, dst], timeout=1200)
            say("%s cloned from the main checkout%s" % (d, "" if code == 0 else " — FAILED, run composer/npm install"))

    env = env_for(lane)
    services = []
    sail = os.path.join(lane, "vendor", "bin", "sail")
    if os.path.isfile(sail):
        # Background workers are left out unless asked for: tests run the queue synchronously, and six lanes
        # each idling a Horizon (~440 MiB) and a scheduler put the host into swap (7.9 of 9.2 GB, 2026-10-06).
        code, out = run(["docker", "compose", "config", "--services"], cwd=lane, env=env, timeout=60)
        services = [l.strip() for l in out.splitlines() if l.strip()] if code == 0 else []
        workers = [x for x in services if BACKGROUND.search(x)]
        wanted = services if (full or not workers) else [x for x in services if x not in workers]
        code, out = run([sail, "up", "-d"] + ([] if wanted == services else wanted), cwd=lane, env=env, timeout=900)
        say("stack %s%s" % ("started" if code == 0 else "did NOT start:\n" + out[-1500:],
                            "" if wanted == services else " without %s (lane.py up --full starts them)" % ", ".join(workers)))
    else:
        say("no vendor/bin/sail — stack not started")

    db_host = main_env.get("DB_HOST", "")
    external = bool(db_host) and container_exists(db_host)
    src_server = db_host if external else compose_container(main, db_host or "mysql", dict(env, COMPOSE_PROJECT_NAME=project))
    dst_server = db_host if external else compose_container(lane, db_host or "mysql", env)
    connection = main_env.get("DB_CONNECTION", "mysql")
    if connection not in ("mysql", "mariadb"):
        say("database clone is MySQL/MariaDB only — %s: the lane database was not cloned; create and migrate it yourself" % connection)
    elif not src_server or not dst_server:
        say("database server not reachable (source %s, lane %s) — databases not provisioned" % (src_server or "?", dst_server or "?"))
    else:
        user = main_env.get("DB_USERNAME", "")
        for name in [n for n in (updates.get("DB_DATABASE"), test_db) if n]:
            code, out = mysql_in(dst_server, "CREATE DATABASE IF NOT EXISTS `%s`" % name)
            if code != 0:
                say("could not create database %s on %s: %s" % (name, dst_server, out[-300:]))
                continue
            if user and user != "root":
                code, out = mysql_in(dst_server, "GRANT ALL PRIVILEGES ON `%s`.* TO '%s'@'%%'" % (name, user))
                if code != 0:
                    say("could not grant %s on %s: %s" % (user, name, out[-300:]))
        lane_db = updates.get("DB_DATABASE")
        code, out = mysql_in(dst_server, "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='%s'" % lane_db)
        empty = code == 0 and (out.strip().splitlines() or ["?"])[-1].strip() == "0"
        if lane_db and db and (empty or refresh_data):
            pipe = ('docker exec %s sh -c \'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --triggers %s\' '
                    '| docker exec -i %s sh -c \'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" %s\'' % (src_server, db, dst_server, lane_db))
            code, out = run(pipe, shell=True, timeout=1800)
            say("dev database %s cloned from %s%s" % (lane_db, db, "" if code == 0 else " — FAILED:\n" + out[-800:]))
        else:
            say("dev database %s already has data — kept (use --refresh-data to re-clone)" % lane_db)
        if os.path.isfile(sail):
            code, out = run([sail, "artisan", "migrate", "--force"], cwd=lane, env=env, timeout=600)
            say("this branch's migrations on the lane database: %s" % ("applied" if code == 0 else "FAILED:\n" + out[-800:]))
            # Tests that do not refresh the database (unit tests reading a migrated schema) rely on a test
            # DB that already has the tables — the shared one always did, a new lane's would not.
            if test_db:
                # `artisan migrate --env=testing` is not enough: where `.env` wins over `.env.testing` it
                # migrates the DEV database (otaje, verified 2026-09-18). The connection is named explicitly.
                app = read_env(os.path.join(lane, ".env"))[0].get("APP_SERVICE") or (
                    "laravel.test" if "laravel.test" in services else next((x for x in services if "app" in x), "laravel.test"))
                code, out = run(["docker", "compose", "exec", "-T", "-e", "DB_DATABASE=%s" % test_db, app,
                                 "php", "artisan", "migrate", "--force"], cwd=lane, env=env, timeout=600)
                c2, n = mysql_in(dst_server, "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='%s'" % test_db)
                tables = (n.strip().splitlines() or ["?"])[-1].strip()
                say("test database %s migrated: %s" % (test_db, ("yes, %s tables" % tables) if code == 0 and tables not in ("0", "?")
                                                       else "FAILED (%s tables):\n%s" % (tables, out[-800:])))

    code, out = run(["docker", "compose", "ps", "--format", "{{.Name}}"], cwd=lane, env=env, timeout=30)
    containers = [l.strip() for l in out.splitlines() if l.strip()] if code == 0 else []
    os.makedirs(os.path.join(lane, ".claude"), exist_ok=True)
    exclude = os.path.join(git(lane, "rev-parse", "--path-format=absolute", "--git-common-dir"), "info", "exclude")
    try:
        os.makedirs(os.path.dirname(exclude), exist_ok=True)
        current = open(exclude, encoding="utf-8").read() if os.path.isfile(exclude) else ""
        if ".claude/lane.json" not in current:
            with open(exclude, "a", encoding="utf-8") as fh:
                fh.write("\n# groundwork lanes — local to each worktree, never committed\n.claude/lane.json\n")
    except Exception:
        pass
    with open(os.path.join(lane, LANE_FILE), "w", encoding="utf-8") as fh:
        json.dump({"compose_project": updates["COMPOSE_PROJECT_NAME"], "domain": lane_domain,
                   "databases": [n for n in (updates.get("DB_DATABASE"), test_db) if n],
                   "db_server": dst_server, "containers": containers,
                   "ports": [updates[v] for v in sorted(published_port_vars(compose)) if v in updates]}, fh, indent=2)
    say("lane ready: %s · containers: %s" % (lane_domain, ", ".join(containers) or "none"))


def status():
    lane, _ = contexts(os.getcwd())
    try:
        print(open(os.path.join(lane, LANE_FILE), encoding="utf-8").read())
    except Exception:
        say("not provisioned — run: python3 lane.py up")


def down(purge=False):
    lane, _ = contexts(os.getcwd())
    try:
        info = json.load(open(os.path.join(lane, LANE_FILE), encoding="utf-8"))
    except Exception:
        info = {}
    env_vals, _ = read_env(os.path.join(lane, ".env"))
    main_env, _ = read_env(os.path.join(os.path.dirname(git(lane, "rev-parse", "--path-format=absolute", "--git-common-dir")), ".env"))
    if env_vals.get("COMPOSE_PROJECT_NAME") and env_vals.get("COMPOSE_PROJECT_NAME") == main_env.get("COMPOSE_PROJECT_NAME"):
        sys.exit("lane: this worktree's .env points at the MAIN stack — refusing to stop it")
    # Only a purge gives phpunit.xml back: a stopped lane may be restarted with a plain `sail up`, and its
    # tests must still land on the lane's own database.
    if purge and git(lane, "ls-files", "-v", "phpunit.xml").startswith("S"):
        run(["git", "-C", lane, "update-index", "--no-skip-worktree", "phpunit.xml"], timeout=20)
        run(["git", "-C", lane, "checkout", "--", "phpunit.xml"], timeout=20)
        say("phpunit.xml restored to the committed version")
    sail = os.path.join(lane, "vendor", "bin", "sail")
    if os.path.isfile(sail):
        # --purge also removes the lane's volumes; the name check above guarantees they are the lane's own.
        code, out = run([sail, "down"] + (["-v"] if purge else []), cwd=lane, env=env_for(lane), timeout=300)
        say("stack %s" % ("stopped" if code == 0 else "not stopped: " + out[-400:]))
    if purge and info.get("db_server"):
        for name in info.get("databases", []):
            if name and name != main_env.get("DB_DATABASE"):
                mysql_in(info["db_server"], "DROP DATABASE IF EXISTS `%s`" % name)
                say("dropped %s" % name)


if __name__ == "__main__":
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "up":
        up(refresh_data="--refresh-data" in args, full="--full" in args)
    elif cmd == "down":
        down(purge="--purge" in args)
    else:
        status()
