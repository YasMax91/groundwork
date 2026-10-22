#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/lane.py and hooks/lane-guard.py (GW35-AC1, AC2).
# Docker is not required: with no reachable database server lane.py reports it and still writes the
# lane's .env, which is what the guard and the isolation depend on. Run: bash hooks/tests/lane.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT

eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-44s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-44s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }
val() { sed -n "s/^$2=//p" "$1" | head -1; }
guard() { # dir command -> deny | allow
  local out
  out="$(jq -nc --arg c "$1" --arg cmd "$2" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}' | python3 "$HOOKS/lane-guard.py")"
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then echo deny; else echo allow; fi
}

echo "lane:"

M="$ROOT/shop"; mkdir -p "$M"
( cd "$M" && git init -q && git config user.email t@t && git config user.name t
  printf '{}\n' > .groundwork.json
  cat > docker-compose.yml <<'YML'
services:
    laravel.test:
        container_name: "${COMPOSE_PROJECT_NAME:-app}_app"
    minio:
        ports:
            - '${FORWARD_MINIO_PORT:-9000}:9000'
YML
  git add -A && git commit -qm init )
cat > "$M/.env" <<'ENV'
APP_NAME=Shop
APP_URL=http://shop.localhost
APP_SLUG=shop
APP_DOMAIN=shop.localhost
SANCTUM_STATEFUL_DOMAINS=shop.localhost,localhost
COMPOSE_PROJECT_NAME=shop
DB_CONNECTION=mysql
DB_HOST=no-such-db-host
DB_DATABASE=shop
DB_USERNAME=sail
FORWARD_MINIO_PORT=9000
AWS_URL=http://localhost:9000/shop
AWS_ENDPOINT=http://minio:9000
ENV
printf 'APP_URL=http://shop.localhost\nCOMPOSE_PROJECT_NAME=shop\nDB_DATABASE=shop_test\n' > "$M/.env.testing"
printf '{"http-basic":{"backpackforlaravel.com":{"username":"u","password":"p"}}}\n' > "$M/auth.json"
cat > "$M/phpunit.xml" <<'XML'
<phpunit><php>
    <env name="APP_ENV" value="testing" force="true"/>
    <env name="DB_DATABASE" value="shop_test" force="true"/>
</php></phpunit>
XML
( cd "$M" && git add phpunit.xml && git commit -qm phpunit )
( cd "$M" && git worktree add -q "$M/.claude/worktrees/cranky-germain-b9e464" -b claude/cranky )
W="$M/.claude/worktrees/cranky-germain-b9e464"

# --- GW35-AC2: an unprovisioned lane cannot reach the main stack --------------------------------
eq "guard: no .env in lane"           deny  "$(guard "$W" './vendor/bin/sail artisan test')"
cp "$M/.env" "$W/.env"
eq "guard: lane copies main stack"    deny  "$(guard "$W" './vendor/bin/sail artisan test')"
eq "guard: non-runner command"        allow "$(guard "$W" 'git status')"
eq "guard: lane.py itself"            allow "$(guard "$W" "python3 $HOOKS/lane.py up")"
eq "guard: main checkout is its own"  allow "$(guard "$M" './vendor/bin/sail artisan test')"
rm "$W/.env"

# --- GW35-AC1: lane.py up rewrites the identity of the lane ---------------------------------------
( cd "$W" && python3 "$HOOKS/lane.py" up > "$ROOT/up.log" 2>&1 )
eq "lane .env project"     "shop_crankyb9e4"                 "$(val "$W/.env" COMPOSE_PROJECT_NAME)"
eq "lane .env slug"        "shop-crankyb9e4"                 "$(val "$W/.env" APP_SLUG)"
eq "lane .env domain"      "shop-crankyb9e4.localhost"       "$(val "$W/.env" APP_DOMAIN)"
eq "lane .env url"         "http://shop-crankyb9e4.localhost" "$(val "$W/.env" APP_URL)"
eq "lane .env database"    "shop_crankyb9e4"                 "$(val "$W/.env" DB_DATABASE)"
eq "lane .env sanctum"     "shop-crankyb9e4.localhost,localhost" "$(val "$W/.env" SANCTUM_STATEFUL_DOMAINS)"
eq "lane .env app name kept" "Shop"                          "$(val "$W/.env" APP_NAME)"
p="$(val "$W/.env" FORWARD_MINIO_PORT)"
[ -n "$p" ] && [ "$p" != "9000" ]; eq "lane published port moved" 0 $?
eq "lane AWS_URL follows the moved port" "http://localhost:$(val "$W/.env" FORWARD_MINIO_PORT)/shop" "$(val "$W/.env" AWS_URL)"
eq "lane AWS_ENDPOINT keeps the container port" "http://minio:9000" "$(val "$W/.env" AWS_ENDPOINT)"
[ -f "$W/auth.json" ]; eq "auth.json copied to the lane" 0 $?
eq "lane .env.testing db"  "shop_test_crankyb9e4"            "$(val "$W/.env.testing" DB_DATABASE)"
eq "lane .env.testing project" "shop_crankyb9e4"             "$(val "$W/.env.testing" COMPOSE_PROJECT_NAME)"
grep -q 'database server not reachable' "$ROOT/up.log"; eq "unreachable DB is reported" 0 $?
[ -f "$W/.claude/lane.json" ]; eq "lane.json written" 0 $?
eq "lane phpunit.xml test db" 'value="shop_test_crankyb9e4"' "$(grep -o 'name="DB_DATABASE" value="[^"]*"' "$W/phpunit.xml" | grep -o 'value="[^"]*"')"
eq "phpunit.xml skip-worktree" "S" "$(git -C "$W" ls-files -v phpunit.xml | cut -c1)"
eq "lane tree stays clean"   "" "$(git -C "$W" status --porcelain --untracked-files=no)"
grep -q '.claude/lane.json' "$M/.git/info/exclude"; eq "lane.json excluded from git" 0 $?
eq "main phpunit.xml untouched" 'value="shop_test"' "$(grep -o 'name="DB_DATABASE" value="[^"]*"' "$M/phpunit.xml" | grep -o 'value="[^"]*"')"
eq "main .env untouched"   "shop"                            "$(val "$M/.env" COMPOSE_PROJECT_NAME)"
eq "guard: provisioned lane" allow "$(guard "$W" './vendor/bin/sail artisan test')"

# --- the main checkout is never a lane, and down never stops the main stack ---------------------
( cd "$M" && python3 "$HOOKS/lane.py" up > "$ROOT/main.log" 2>&1 ); c=$?
[ "$c" -ne 0 ] && grep -q 'main checkout' "$ROOT/main.log"; eq "up refuses the main checkout" 0 $?
cp "$M/.env" "$W/.env"
( cd "$W" && python3 "$HOOKS/lane.py" down > "$ROOT/down.log" 2>&1 ); c=$?
[ "$c" -ne 0 ] && grep -q 'MAIN stack' "$ROOT/down.log"; eq "down refuses the main stack" 0 $?

# --- a project without .env.testing names its test database only in phpunit.xml (2026-10-06) ------
C="$ROOT/cafe"; mkdir -p "$C"
( cd "$C" && git init -q && git config user.email t@t && git config user.name t
  printf '{}\n' > .groundwork.json
  printf 'services:\n    laravel.test:\n        image: x\n' > docker-compose.yml
  printf '<phpunit><php>\n    <env name="DB_DATABASE" value="cafe_testing" force="true"/>\n</php></phpunit>\n' > phpunit.xml
  git add -A && git commit -qm init
  git worktree add -q "$C/.claude/worktrees/sleepy-hopper-a1b2c3" -b claude/sleepy )
printf 'APP_URL=http://cafe.localhost\nCOMPOSE_PROJECT_NAME=cafe\nDB_HOST=no-such-db-host\nDB_DATABASE=cafe\n' > "$C/.env"
CW="$C/.claude/worktrees/sleepy-hopper-a1b2c3"
( cd "$CW" && python3 "$HOOKS/lane.py" up > "$ROOT/cafe.log" 2>&1 )
eq "no .env.testing: lane test db from phpunit.xml" 'value="cafe_testing_sleepya1b2"' \
  "$(grep -o 'name="DB_DATABASE" value="[^"]*"' "$CW/phpunit.xml" | grep -o 'value="[^"]*"')"
grep -q 'named after phpunit.xml' "$ROOT/cafe.log"; eq "…and says where the name came from" 0 $?
[ ! -f "$CW/.env.testing" ]; eq "…without inventing a .env.testing" 0 $?

# --- a lane whose stack never started is not ready (2026-10-21) -----------------------------------
grep -q 'lane NOT ready: shop-crankyb9e4.localhost (no vendor/bin/sail' "$ROOT/up.log"; eq "no sail: lane NOT ready" 0 $?
grep -q 'lane ready' "$ROOT/up.log"; eq "…and never lane ready" 1 $?

# --- the stack: Docker's address pools used up, and public/storage on a fresh lane (2026-10-21) ----
# Docker and Sail are stand-ins: they answer what lane.py asks, from files in $FAKE, and log what it ran.
FAKE="$ROOT/fake"; mkdir -p "$FAKE" "$ROOT/bin"
cat > "$ROOT/bin/docker" <<'SH'
#!/usr/bin/env bash
F="$LANE_FAKE"; echo "docker $*" >> "$F/docker.log"
case "$1" in
  inspect) [ "${4:-}" = "deli-db" ] ;;                     # inspect --type container <name>: the external DB server
  exec) if [ "$2" = "-i" ]; then case "$(cat)" in *"COUNT(*)"*) echo 0 ;; esac; fi ;;
  info) echo null ;;                                        # no default-address-pools of its own
  compose)
    case "$2" in
      config) if [ "${3:-}" = "--services" ]; then printf 'laravel.test\nhorizon\n'; echo 'level=warning msg="obsolete"' >&2
              else cat "$F/config.json"; fi ;;
      ps) if [[ "$*" == *--format* ]] && [ -f "$F/up.$(basename "$PWD")" ]; then echo "$(basename "$PWD")_app"; fi ;;
    esac ;;
  network)                                                  # $F/nets: name <TAB> Compose project <TAB> subnets
    case "$2" in
      ls) cut -f1 "$F/nets" ;;
      inspect) cat "$F/nets" ;;
    esac ;;
  ps) if [ "${2:-}" = "-a" ]; then cat "$F/containers"; else grep -v '^exited' "$F/containers" || true; fi ;;
esac
SH
D="$ROOT/deli"; mkdir -p "$D"
( cd "$D" && git init -q && git config user.email t@t && git config user.name t
  printf '{"commands":{"openapi_generate":"./vendor/bin/sail artisan l5-swagger:generate"}}\n' > .groundwork.json
  printf '/vendor\n/public/storage\n/storage/api-docs\n.env\n' > .gitignore
  mkdir -p public storage/app/public docs && printf '<?php\n' > public/index.php && printf '*\n!.gitignore\n' > storage/app/public/.gitignore
  printf '{"committed": true}\n' > docs/openapi.json
  printf 'services:\n    laravel.test:\n        image: sail-8.4/app\n        networks: [sail, traefik]\nnetworks:\n    sail:\n        driver: bridge\n    traefik:\n        external: true\n        name: traefik-network\n' > docker-compose.yml
  git add -A && git commit -qm init
  git worktree add -q "$D/.claude/worktrees/brave-curie-c0ffee" -b claude/brave
  git worktree add -q "$D/.claude/worktrees/calm-noether-d00d" -b claude/calm
  git worktree add -q "$D/.claude/worktrees/eager-sails-e1e1" -b claude/eager )
printf 'APP_URL=http://deli.localhost\nCOMPOSE_PROJECT_NAME=deli\nDB_CONNECTION=mysql\nDB_HOST=deli-db\nDB_DATABASE=deli\nDB_USERNAME=sail\n' > "$D/.env"
mkdir -p "$D/vendor/bin"; cat > "$D/vendor/bin/sail" <<'SH'
#!/usr/bin/env bash
F="$LANE_FAKE"; echo "sail $*" >> "$F/sail.$(basename "$PWD")"
case "$1 ${2:-}" in
  "up -d")
    if [ -f "$F/pools-used-up" ] && ! { grep -q '^COMPOSE_FILE=.*\.claude/lane-compose\.yml' .env && grep -qs '"subnet"' .claude/lane-compose.yml; }; then
      echo 'failed to create network x_sail: Error response from daemon: all predefined address pools have been fully subnetted' >&2; exit 1
    fi
    if [ -f "$F/port-taken" ]; then echo 'Error response from daemon: ports are not available: listen tcp 0.0.0.0:80' >&2; exit 1; fi
    touch "$F/up.$(basename "$PWD")" ;;
  "artisan storage:link")
    if [ -f "$F/no-symfony-filesystem" ]; then echo 'RuntimeException  To enable support for relative links, please install the symfony/filesystem package.'; exit 1; fi
    ln -s ../storage/app/public/ public/storage && echo 'INFO  The [public/storage] link has been connected to [storage/app/public].' ;;
  "artisan l5-swagger:generate")
    if [ -f "$F/generator-fails" ]; then echo 'Required @OA\Info() not found'; exit 1; fi
    [ -f "$F/generator-rewrites-tracked" ] && printf '{"regenerated": true}\n' > docs/openapi.json
    [ -f "$F/generator-writes-committed" ] && printf '{"committed": true}\n' > docs/openapi.json
    mkdir -p storage/api-docs && printf '{"openapi": "3.0.0"}\n' > storage/api-docs/api-docs.json && echo 'Regenerating docs default' ;;
esac
SH
chmod +x "$ROOT/bin/docker" "$D/vendor/bin/sail"
printf '{"networks":{"sail":{"name":"x_sail","driver":"bridge","ipam":{}},"traefik":{"name":"traefik-network","external":true,"ipam":{}}}}\n' > "$FAKE/config.json"
# By hand (no project), idle, held by stopped containers only, live, and other lanes on subnets of their own —
# 10.213.0.0/17 and .128.0/18, so a new lane subnet can only come from 10.213.192.0/18.
BASE_NETS=$'bridge\t\t172.17.0.0/16 \nhost\t\t\nnone\t\t\ntraefik-network\t\t172.31.0.0/16 '
BASE_NETS+=$'\ncafe_old_default\tcafe_old\t192.168.16.0/20 \nshop_gone_sail\tshop_gone\t172.21.0.0/16 '
BASE_NETS+=$'\notaje_sweet_sail\totaje_sweet\t172.26.0.0/16 \notaje_sail\totaje\t192.168.128.0/20 '
BASE_NETS+=$'\nlanes_own_sail\tlanes_own\t10.213.0.0/17 \nlanes_more_sail\tlanes_more\t10.213.128.0/18 fd00::/64 '
nets() { printf '%s\n' "$BASE_NETS" "$@" > "$FAKE/nets"; }   # extra lines -> $FAKE/nets
nets $'deli_bravec0ff_sail\tdeli_bravec0ff\t172.28.0.0/16 '
printf 'running\totaje_sail,proxy_net\nexited\totaje_sweet_sail\nrunning\tdb_net\n' > "$FAKE/containers"
lane_up() { # worktree log [args] -> exit status of lane.py up
  local wt="$1" log="$2"; shift 2
  ( cd "$wt" && PATH="$ROOT/bin:$PATH" LANE_FAKE="$FAKE" python3 "$HOOKS/lane.py" up "$@" > "$log" 2>&1 )
}
lane_subnet() { # worktree -> the subnet its .claude/lane-compose.yml gives the sail network
  python3 -c 'import json,sys; print(json.loads("".join(l for l in open(sys.argv[1]) if not l.startswith("#")))["networks"]["sail"]["ipam"]["config"][0]["subnet"])' \
    "$1/.claude/lane-compose.yml" 2>&1
}
in_free_range() { python3 -c 'import ipaddress,sys; sys.exit(0 if ipaddress.ip_network(sys.argv[1]).subnet_of(ipaddress.ip_network("10.213.192.0/18")) else 1)' "$1" 2>/dev/null; }
DW="$D/.claude/worktrees/brave-curie-c0ffee"; DL="$FAKE/sail.brave-curie-c0ffee"

touch "$FAKE/pools-used-up"
lane_up "$DW" "$ROOT/deli1.log"; eq "pools used up: up exits 1"               1 $?
grep -q 'no address range left for a new network' "$ROOT/deli1.log"; eq "…says what happened" 0 $?
eq "…names the networks no container uses" "docker network rm cafe_old_default shop_gone_sail" \
  "$(grep -o 'docker network rm .*' "$ROOT/deli1.log")"
grep -q "ONLY with the owner's consent" "$ROOT/deli1.log"; eq "…removing them is the owner's call" 0 $?
grep -q 'stopped containers only.*otaje_sweet$' "$ROOT/deli1.log"; eq "…names the stack held by stopped containers" 0 $?
grep -q 'traefik-network' "$ROOT/deli1.log"; eq "…never a network made by hand" 1 $?
grep -q 'lanes_own_sail' "$ROOT/deli1.log"; eq "…never one outside the pools" 1 $?
grep -q 'lane.py up --own-subnet' "$ROOT/deli1.log"; eq "…offers a subnet of its own" 0 $?
grep -q 'migrations: not run — the stack is not up' "$ROOT/deli1.log"; eq "…no migrations on a stack that is down" 0 $?
grep -q 'artisan migrate' "$DL"; eq "…so no 'Sail is not running'" 1 $?
grep -q 'storage:link' "$DL"; eq "…no storage link without a stack" 1 $?
grep -q 'l5-swagger' "$DL"; eq "…no OpenAPI document without a stack" 1 $?
grep -q 'lane NOT ready: deli-bravec0ff.localhost' "$ROOT/deli1.log"; eq "…ends on lane NOT ready" 0 $?
grep -q 'lane ready' "$ROOT/deli1.log"; eq "…never lane ready" 1 $?
[ ! -e "$DW/.claude/lane-compose.yml" ] && [ -z "$(val "$DW/.env" COMPOSE_FILE)" ]; eq "…no subnet of its own unasked" 0 $?
[ -f "$DW/.claude/lane.json" ]; eq "…lane.json still written" 0 $?

lane_up "$DW" "$ROOT/deli2.log" --own-subnet; eq "--own-subnet: up exits 0"           0 $?
grep -q 'lane ready: deli-bravec0ff.localhost' "$ROOT/deli2.log"; eq "…lane ready" 0 $?
eq "…COMPOSE_FILE adds the lane's compose file" "docker-compose.yml:.claude/lane-compose.yml" "$(val "$DW/.env" COMPOSE_FILE)"
subnet="$(lane_subnet "$DW")"; in_free_range "$subnet"; eq "…a /24 no Docker network uses" 0 $?
grep -q traefik "$DW/.claude/lane-compose.yml"; eq "…external networks left alone" 1 $?
eq "…never committed" "" "$(git -C "$DW" status --porcelain --untracked-files=all)"
grep -q '^\.claude/lane-compose\.yml$' "$D/.git/info/exclude"; eq "…excluded from git" 0 $?
grep -q 'artisan migrate --force' "$DL"; eq "…migrations run once the stack is up" 0 $?
[ -L "$DW/public/storage" ] && [ -d "$DW/public/storage" ]; eq "storage: public/storage resolves on the host" 0 $?
case "$(readlink "$DW/public/storage")" in ../*) r=0 ;; *) r=1 ;; esac; eq "…a relative link" 0 $r
grep -q 'artisan storage:link --relative' "$DL"; eq "…made by artisan storage:link --relative" 0 $?
grep -q 'public/storage linked to storage/app/public, relative (artisan' "$ROOT/deli2.log"; eq "…and the step is printed" 0 $?
[ -f "$DW/storage/api-docs/api-docs.json" ]; eq "openapi: the lane has its document" 0 $?
grep -q 'OpenAPI document generated (./vendor/bin/sail artisan l5-swagger:generate)$' "$ROOT/deli2.log"; eq "…by commands.openapi_generate, printed" 0 $?

before="$(grep -v '^#' "$DW/.claude/lane-compose.yml")"
touch "$FAKE/generator-fails"
lane_up "$DW" "$ROOT/deli3.log"; eq "re-run: up exits 0"                      0 $?
grep -q 'OpenAPI document NOT generated' "$ROOT/deli3.log" && grep -q 'Required @OA.Info() not found' "$ROOT/deli3.log"
eq "openapi: a failed generation is shown" 0 $?
rm "$FAKE/generator-fails"
eq "re-run keeps the lane's subnet" "$before" "$(grep -v '^#' "$DW/.claude/lane-compose.yml")"
eq "re-run keeps COMPOSE_FILE" "docker-compose.yml:.claude/lane-compose.yml" "$(val "$DW/.env" COMPOSE_FILE)"
eq "re-run links storage only once" 1 "$(grep -c 'storage:link' "$DL")"
eq "compose's stderr never reaches sail up" "sail up -d laravel.test" "$(grep '^sail up' "$DL" | sort -u)"

# A subnet the lane holds stays, though a fresh choice would differ: its own network carries it, and that is not
# "taken". Once another network took it while the lane's was gone (`down` removes it), the lane moves off.
K=10.213.250.0/24; [ "$subnet" = "$K" ] && K=10.213.251.0/24
printf '{"networks": {"sail": {"ipam": {"config": [{"subnet": "%s"}]}}}}\n' "$K" > "$DW/.claude/lane-compose.yml"
nets $'deli_bravec0ff_sail\tdeli_bravec0ff\t'"$K "
lane_up "$DW" "$ROOT/deli3b.log"; eq "held subnet: up exits 0"                 0 $?
eq "…stays on its own network" "$K" "$(lane_subnet "$DW")"
nets $'intruder_sail\tintruder\t'"$K "
lane_up "$DW" "$ROOT/deli3c.log"; eq "held subnet taken by another: up exits 0" 0 $?
moved="$(lane_subnet "$DW")"; [ "$moved" != "$K" ] && in_free_range "$moved"; eq "…moves to a free /24" 0 $?
grep -q "sail moved off $K, which another network uses now" "$ROOT/deli3c.log"; eq "…and says so" 0 $?

rm "$FAKE/pools-used-up"; touch "$FAKE/no-symfony-filesystem" "$FAKE/generator-rewrites-tracked"
DW2="$D/.claude/worktrees/calm-noether-d00d"
lane_up "$DW2" "$ROOT/deli4.log"; eq "fresh lane: up exits 0"                 0 $?
eq "openapi: a committed file it rewrites is put back" "" "$(git -C "$DW2" status --porcelain --untracked-files=no)"
grep -q 'docs/openapi.json kept as it was — the command rewrote it' "$ROOT/deli4.log"; eq "…and says so" 0 $?
[ -L "$DW2/public/storage" ] && [ -d "$DW2/public/storage" ]; eq "storage: linked from the host when artisan cannot" 0 $?
grep -q 'relative, from the host — artisan storage:link --relative failed' "$ROOT/deli4.log"; eq "…and says so" 0 $?
[ -z "$(val "$DW2/.env" COMPOSE_FILE)" ] && [ ! -e "$DW2/.claude/lane-compose.yml" ]; eq "…no subnet of its own unasked" 0 $?
touch "$FAKE/port-taken"
lane_up "$DW2" "$ROOT/deli5.log"; eq "other start error: up exits 1"           1 $?
grep -q 'ports are not available' "$ROOT/deli5.log" && grep -q 'lane NOT ready' "$ROOT/deli5.log"; eq "…shows it and is NOT ready" 0 $?
grep -q 'address range' "$ROOT/deli5.log"; eq "…not taken for used-up pools" 1 $?
rm "$FAKE/port-taken"
printf '{"wip": true}\n' > "$DW2/docs/openapi.json"
lane_up "$DW2" "$ROOT/deli5b.log"; eq "openapi over work in progress: up exits 0" 0 $?
eq "…the lane's own edit survives" '{"wip": true}' "$(cat "$DW2/docs/openapi.json")"
rm "$FAKE/generator-rewrites-tracked"; touch "$FAKE/generator-writes-committed"   # no diff left to see it by
lane_up "$DW2" "$ROOT/deli5c.log"
eq "…even rewritten to the committed text" '{"wip": true}' "$(cat "$DW2/docs/openapi.json")"
git -C "$DW2" checkout -q -- docs/openapi.json; rm "$FAKE/generator-writes-committed"

# Sail turns SAIL_FILES into -f flags, which outrank COMPOSE_FILE: the lane's file joins them. This lane's
# .groundwork.json names no generate command, and l5-swagger is installed: its own command runs.
printf 'SAIL_FILES=docker-compose.yml\n' >> "$D/.env"
mkdir -p "$D/vendor/darkaonline/l5-swagger"
DW3="$D/.claude/worktrees/eager-sails-e1e1"; printf '{}\n' > "$DW3/.groundwork.json"
lane_up "$DW3" "$ROOT/deli6.log" --own-subnet; eq "SAIL_FILES: up exits 0"   0 $?
eq "…the lane's file joins SAIL_FILES" "docker-compose.yml:.claude/lane-compose.yml" "$(val "$DW3/.env" SAIL_FILES)"
eq "…and COMPOSE_FILE" "docker-compose.yml:.claude/lane-compose.yml" "$(val "$DW3/.env" COMPOSE_FILE)"
[ -f "$DW3/storage/api-docs/api-docs.json" ] && grep -q 'OpenAPI document generated (artisan l5-swagger:generate — no commands.openapi_generate)' "$ROOT/deli6.log"
eq "openapi: l5-swagger's own command without one" 0 $?

# --- opt-out -------------------------------------------------------------------------------------
printf '{"gates":{"lane_guard":false}}\n' > "$W/.groundwork.json"
eq "guard: opt-out"        allow "$(guard "$W" './vendor/bin/sail artisan test')"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
