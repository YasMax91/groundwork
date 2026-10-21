# Spec: Wave 36 — parallel sessions stop tripping over each other (groundwork v0.46.0 + follow-through v0.3.0)

- Type: defect wave across both plugins plus local infrastructure → **L2**.
- Author: Max Yastremskyi (YasMax91).
- Source: the author, 2026-10-06: *«Сессии постоянно друг об друга спотыкаются и из-за этого происходит
  задержки. Проверь и дай решение»*.
- Evidence, read on 2026-10-06 for the window 2026-10-05 12:00 – 2026-10-06 08:00: follow-through's
  `triggers.log` (35 lines), the transcripts of 14 sessions, the otaje memory directory (38 entries),
  `docker stats`, `vm.swapusage`, and the shared MySQL's settings.
- Decisions taken with the author on 2026-10-06: lanes without background workers and stopped when their
  last session closes · tune the shared MySQL and restart it at an idle moment · mirror rendered from the
  integration branch, `merge=union` for `docs/ai/status.md` in otaje · otaje memory reviewed after the fixes.
- Status: **implemented** (2026-10-06).

## What was found

| # | Delay | Evidence | Cause |
|---|---|---|---|
| D1 | Gates judged another session's tree | otaje memory `hooks-read-main-checkout-checkpoint` (98 lines of workarounds): «task is in Discovery mode» refusing edits in a worktree; OpenAPI and handoff gates blocking on files other sessions pushed; agents fast-forwarding the main checkout, which auto mode refused | every groundwork hook resolved `.groundwork.json` / `.claude/groundwork/…` against the process directory — the directory the session was opened in, not the payload's `cwd` (0 of 20 bash hooks read `cwd`) |
| D2 | False overlap stops | 9 of 9 `lane_overlap` denies were `.claude/groundwork/task-state.md` | the same relative path in another worktree is a different, git-ignored file |
| D3 | Permission prompts on reads | `ls -la .claude/ 2>&1 …; cat .groundwork.json 2>/dev/null` asked | "mentions the file and contains `>`" counted as a write |
| D4 | Mirror churn and rollback | 6 mirror blocks; a lagging lane's render rolled the page back; the publish refused by the auto-mode classifier; status reads with `2>/dev/null` counted as edits | the mirror was required after every edit of a lane's own copy |
| D5 | Lanes negotiating rows («её A6, моя A7») | transcripts | two lanes appending to one table conflict on merge |
| D6 | Swap | 7.9 of 9.2 GB swap, 24 GB host, Docker VM allowed 16 GB, 6 lanes up (34 containers), Horizon ≈ 440 MiB each | `lane.py up` started every service and nothing stopped a lane |
| D7 | Slow suites on one server | agents splitting suites, waiting «until the shared DB is stable for two minutes» | `innodb_flush_log_at_trx_commit=1` and the binary log on: two fsyncs per commit |
| D8 | Lane gaps | memory `worktree-lane-py-up`: test DB empty — migrate it by hand; `AWS_URL` pointing at the main MinIO | `migrate --env=testing` migrates the dev DB in otaje; port-bearing URLs not rewritten; `auth.json` (private packages) not copied |

| D9 | Product rules blocked as estimates | otaje memory `estimate-docs-flags-day-counts`: «30 days since the last visit» (sign-in lifetime) blocked; agents hyphenate «30-day» to slip past | `estimate-docs.py` treated every «N days» in a changed doc as an estimate |
| D10 | Two lanes took the same row ID («A7») | otaje memory `status-mirror-publish-race` | IDs were picked from each lane's own copy |

## Changes

- **GW36-AC1** `hooks/in-cwd.sh`: every `hooks.json` command runs through it; it reads the payload, `cd`s
  into `cwd`, and hands the payload on. Suite `in-cwd` reproduces D1 (Discovery checkpoint in main,
  Implementation in the worktree): without the wrapper deny, with it allow, main still guarded.
- **FT36-AC1** overlap skips `.claude/**` and git-ignored paths, and they are no longer recorded.
- **FT36-AC2** `lanes.shell_writes(cmd, target)`: a write only when the target of `>`/`>>`, `tee`, `sed -i`,
  `mv`/`cp` destination, `rm`, or a heredoc `open(…,'w')`/`write_text` is the file; `/dev/null` and `2>&1`
  never count. Used by the config guard and the status check (13 of 13 cases).
- **FT36-AC3** the status gate asks for a status edit on a commit or deploy only (a push or merge carries
  an edit already made); the mirror is asked for only from the session whose turn pushed, only when the
  status committed on the integration branch differs from the one last published (recorded by
  PostToolUse on the Artifact publish in `<git-common-dir>/follow-through/mirror.json`), and
  `render_status.py --ref origin/development` renders from that branch.
- **otaje** `.gitattributes`: `docs/ai/status.md merge=union` (90b6485); proven with two branches
  appending a row each — merged without a conflict.
- **GW36-AC2** `lane.py up` starts every service except `horizon|scheduler|schedule|queue|worker|cron`
  (`--full` starts them); `lane-idle.py` (SessionEnd) runs `docker compose -p <lane> stop` detached when no
  other live session (registry or `claude` process) is in the worktree; `down --purge` also removes the
  lane's volumes.
- **GW36-AC3** `lane.py up` migrates the test DB with `docker compose exec -e DB_DATABASE=<test db>` and
  reports the table count, copies `auth.json`; host-side URLs (`localhost`, `127.0.0.1`, the lane domain) follow a moved
  published port, container-side ones (`minio:9000`) do not.
- **GW36-AC4** `estimate-docs.py`: «N days» blocks only next to an estimate word on the line or in its
  section heading, and never on a lifetime, window, TTL, cookie or session line.
- **FT36-AC4** the status skill claims a new ID by pushing its row first; the mirror marks a duplicated ID.
- **GW36-AC5** `lane.py` started from an older cached version re-runs the newest one installed (a session ran 0.45.1 from a remembered path and brought Horizon back).
- **GW36-AC6** (v0.49.1, 2026-10-21) `lane.py up` links `public/storage` with `artisan storage:link --relative`
  once the stack is up, and from the host when artisan cannot (`--relative` needs symfony/filesystem). An otaje
  lane had none: Backpack's `/storage/basset/…` answered 403, so the admin opened without its styles and
  without `common.js`, which sets jQuery's CSRF header. Relative, because a link made in the container names
  `/var/www/html`, which the host does not have.
- **GW36-AC7** (v0.49.1, 2026-10-21) used-up address pools are named as such: on Docker Desktop 30 of 30 were
  taken (9 otaje lanes, the main stack, other projects; 16 networks without a container), `sail up` failed with
  «all predefined address pools have been fully subnetted», and `up` went on to «Sail is not running» on the
  migrations and still printed «lane ready … containers: none». Now it gives two ways out: the Compose
  networks on a range from Docker's pools that no container uses, running or stopped (`docker ps -a`;
  `network inspect` counts running ones only), named for the owner to remove — never a network made by hand
  such as `traefik-network`, never one on a subnet of its own (removing it frees no range), never removed by
  the script; or `--own-subnet`: a /24 of 10.213.0.0/16 per lane network in `.claude/lane-compose.yml`, named
  by `COMPOSE_FILE` (and `SAIL_FILES` where the project sets it — Sail's `-f` flags outrank `COMPOSE_FILE`) in
  the lane's `.env` and listed in `info/exclude`. The subnet is kept across runs unless another network took
  it while the lane's was gone (`down` removes it); then the lane moves to a free /24 and says so. A stack
  that did not start skips the migrations and ends on `lane NOT ready`, exit 1. `docker compose config
  --services` is read from stdout alone: a Compose warning on stderr had reached `sail up -d` as one more
  service whenever workers were left out.
- **docker-proxy** (e20472b, local repository): `--skip-log-bin`, `--innodb-flush-log-at-trx-commit=2`;
  restarted after three idle samples in a row.

## Verification

- groundwork: 26 of 26 suites green (new `in-cwd` 8 cases, `lane-idle` 6, `lane` 30); follow-through 69
  of 69.
- Shared MySQL, `docs/bench.sql`, two runs each: 3000 single-row commits 2430–3059 ms → 179–325 ms;
  200 DROP+CREATE 1954–2756 ms → 2288–2493 ms (DDL is bound by file creation, unchanged). 61 schemas
  present after the restart; the main otaje stack stayed up.
- Live probe lane on otaje: 3 containers instead of 5, provisioned in 30 s, test DB 84 tables, MinIO 200
  from inside the lane (`minio:9000`) and from the host (`localhost:<lane port>`); torn down to 0
  containers, 0 volumes, 0 databases.
- **v0.49.1:** `lane.sh` 82 of 82 (49 new cases on stand-in `docker` and `sail`; 27 of them fail on 0.49.0, one
  of those the Compose warning reaching `sail up -d`); all groundwork suites and follow-through 69 of 69 green.
  An adversarial review found a kept subnet reused unchecked, idle networks off the pools listed, and two
  behaviours no case held (the kept subnet, `ps -a`); fixed, and six mutations of `lane.py` — each fix undone,
  `-a` dropped — each fail at least one case. On Docker 29.5.2 / Compose 5.1.3 a throwaway lane started on
  172.18.0.0/16, moved to 10.213.114.0/24 with `--own-subnet` while running (Compose re-created the network and
  reconnected the container), kept its subnet on re-runs while its own network held it, went back to the pools
  when `.claude/lane-compose.yml` was deleted, and its `public/storage` resolved on the host; `git status` stayed
  clean. The diagnosis read against the real host: no idle Compose network, `otaje_sweeta204` held by stopped
  containers only, `traefik-network` not named. Not reproduced: the used-up pools themselves — the regex
  matches Docker's message as the otaje session reported it.
- Not measured: the memory saved on the host after the running lanes are restarted — they keep their
  current containers until their sessions close or `lane.py up` runs again.
