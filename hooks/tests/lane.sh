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
ENV
printf 'APP_URL=http://shop.localhost\nCOMPOSE_PROJECT_NAME=shop\nDB_DATABASE=shop_test\n' > "$M/.env.testing"
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

# --- opt-out -------------------------------------------------------------------------------------
printf '{"gates":{"lane_guard":false}}\n' > "$W/.groundwork.json"
eq "guard: opt-out"        allow "$(guard "$W" './vendor/bin/sail artisan test')"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
