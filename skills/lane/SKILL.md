---
description: Provision this worktree as an isolated lane — its own Docker stack, domain, dev database (cloned from the main checkout) and test database — so parallel sessions of a Laravel+Sail project never run each other's code or share data. Use when starting work in a worktree, when lane-guard denies a sail command, when the user opens several sessions on one project, or when a lane needs fresh data (--refresh-data).
---

# Lane

A lane is one worktree with everything it runs on: a Compose project of its own, `<app>-<lane>.localhost`
through the shared Traefik, a dev database cloned from the main checkout's, an empty test database,
`vendor/` and `node_modules/` cloned copy-on-write. Two lanes never touch each other's containers or
data; the main checkout keeps the main stack.

`lane-guard` refuses any `sail …` from a worktree whose `.env` still points at the main stack or the main
dev database — that is how a lane ended up testing another session's code (otaje, 2026-09).

## Steps

1. **Be in a worktree.** In the main checkout, enter one first (`EnterWorktree`). follow-through moves an
   empty new lane to the freshest integration branch on its first start.
2. **Provision:** `python3 "${CLAUDE_SKILL_DIR}/../../hooks/lane.py" up`. Read its output line by line and
   report it — stack started or not, database cloned or not, migrations applied or not. A step that
   failed is named, never smoothed over.
   - It refuses to run in the main checkout.
   - A compose file with a hard-coded `container_name` cannot run twice; the script says which, and the
     fix is `${COMPOSE_PROJECT_NAME}_<service>` in that file — propose it as its own change.
   - Postgres projects get no clone (named in the output); create and migrate the lane DB with the
     runner.
3. **Open the lane** at the domain the script printed and log in with the project's `dev_login`.
4. **Fresh data on request:** `lane.py up --refresh-data` re-clones the dev database from the main
   checkout and re-applies this branch's migrations.
5. **When the lane's work is merged:** `lane.py down` stops its stack. `lane.py down --purge` also drops
   its databases — a permission prompt asks first.

`lane.py status` prints what the lane uses (`.claude/lane.json`): Compose project, domain, databases,
containers. Sibling sessions read the same file, so stopping a lane's container from another session
asks the user first.
