#!/usr/bin/env bash
# RaDevs plugin :: executable proof for pre-tool-guard.sh.
# A denying hook can break the workflow, so each acceptance criterion (AC1..AC7 in
# docs/specs/wave-2-enforcement.md) gets a case here. Feeds crafted JSON on stdin to the
# guard inside a throwaway fixture and asserts the exit code (2 = deny, 0 = allow).
# No framework — plain bash. Run: bash hooks/tests/run.sh
set -uo pipefail

GUARD="$(cd "$(dirname "$0")/.." && pwd)/pre-tool-guard.sh"
[ -f "$GUARD" ] || { echo "guard not found: $GUARD"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# expect <name> <expected-exit> <fixture-dir> <json-stdin>
expect() {
  local name="$1" want="$2" dir="$3" json="$4" got
  ( cd "$dir" && printf '%s' "$json" | bash "$GUARD" >/dev/null 2>&1 )
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-22s (exit %s)\n' "$name" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-22s (want %s, got %s)\n' "$name" "$want" "$got"
  fi
}

sdd() { # write a .groundwork.json with the three gate toggles
  cat > "$1/.groundwork.json" <<JSON
{ "runner": "sail", "database": { "default": "mysql" },
  "gates": { "enforce_runner": $2, "lock_shipped_migrations": $3, "lock_edits_in_discovery": $4 } }
JSON
}
fake_sail() { mkdir -p "$1/vendor/bin"; printf '#!/bin/sh\nexit 0\n' > "$1/vendor/bin/sail"; chmod +x "$1/vendor/bin/sail"; }

# --- AC1: host php/composer/artisan denied when runner available + toggle on ---
d="$ROOT/ac1"; mkdir -p "$d"; sdd "$d" true true false; fake_sail "$d"
expect "AC1 runner_deny php"      2 "$d" '{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}'
expect "AC1 runner_deny composer" 2 "$d" '{"tool_name":"Bash","tool_input":{"command":"composer install"}}'
expect "AC1 runner_deny env-pref" 2 "$d" '{"tool_name":"Bash","tool_input":{"command":"APP_ENV=local artisan tinker"}}'

# --- AC4: already routed through the runner is allowed ---
expect "AC4 runner_allow sail"    0 "$d" '{"tool_name":"Bash","tool_input":{"command":"./vendor/bin/sail artisan test"}}'
expect "AC4 allow non-php cmd"    0 "$d" '{"tool_name":"Bash","tool_input":{"command":"ls -la app"}}'

# --- AC2: shipped (tracked) migration denied; new (untracked) one allowed ---
d="$ROOT/ac2"; mkdir -p "$d"; sdd "$d" true true false; fake_sail "$d"
( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
  && mkdir -p database/migrations && echo '<?php' > database/migrations/2024_01_01_000000_create_x.php \
  && git add -A && git commit -qm init )
echo '<?php' > "$d/database/migrations/2024_02_02_000000_new_y.php"   # untracked
expect "AC2 migration_lock"       2 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/database/migrations/2024_01_01_000000_create_x.php\"}}"
expect "AC2 new migration ok"     0 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/database/migrations/2024_02_02_000000_new_y.php\"}}"

# --- AC3: no .groundwork.json -> no-op; toggle off -> no-op ---
d="$ROOT/ac3a"; mkdir -p "$d"; fake_sail "$d"   # no .groundwork.json
expect "AC3 no_config no-op"      0 "$d" '{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}'
d="$ROOT/ac3b"; mkdir -p "$d"; sdd "$d" false true false; fake_sail "$d"
expect "AC3 toggle_off no-op"     0 "$d" '{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}'

# --- AC5: runner absent -> bootstrap fail-open ---
d="$ROOT/ac5"; mkdir -p "$d"; sdd "$d" true true false   # no fake sail
expect "AC5 bootstrap composer"   0 "$d" '{"tool_name":"Bash","tool_input":{"command":"composer install"}}'

# --- AC6: discovery edit-lock on -> deny app code; off -> allow ---
d="$ROOT/ac6"; mkdir -p "$d/app" "$d/.claude/groundwork"; printf '# Task: x\n- Mode: Discovery\n' > "$d/.claude/groundwork/task-state.md"
sdd "$d" true true true
expect "AC6 discovery_lock app"   2 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/app/Service.php\"}}"
expect "AC6 discovery allow docs" 0 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/docs/specs/plan.md\"}}"
sdd "$d" true true false
expect "AC6 lock_off allow app"   0 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/app/Service.php\"}}"

# --- AC7: malformed / empty stdin -> fail-open ---
d="$ROOT/ac7"; mkdir -p "$d"; sdd "$d" true true false; fake_sail "$d"
expect "AC7 malformed json"       0 "$d" '{not valid json'
expect "AC7 empty stdin"          0 "$d" ''

# --- W11-AC1: a project that declares runner:host may run host commands ---
sdd_host() { # write a .groundwork.json with runner:host and the gate toggles on
  cat > "$1/.groundwork.json" <<'JSON'
{ "runner": "host", "database": { "default": "mysql" },
  "gates": { "enforce_runner": true, "lock_shipped_migrations": true, "lock_edits_in_discovery": false } }
JSON
}
d="$ROOT/w11a"; mkdir -p "$d"; sdd_host "$d"; fake_sail "$d"   # sail present but runner is host
expect "W11 host php allowed"     0 "$d" '{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}'
expect "W11 host composer allowed" 0 "$d" '{"tool_name":"Bash","tool_input":{"command":"composer install"}}'
d="$ROOT/w11b"; mkdir -p "$d"; sdd "$d" true true false; fake_sail "$d"   # runner:sail still denies
expect "W11 sail still denies"    2 "$d" '{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}'

# --- W11-AC4/AC5: the discovery edit-lock keys on a CANONICAL mode only ---
d="$ROOT/w11c"; mkdir -p "$d/app" "$d/.claude/groundwork"; sdd "$d" true true true
printf '# Task: x\n- Mode: **Discovery**\n' > "$d/.claude/groundwork/task-state.md"
expect "W11 emphasised mode locks" 2 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/app/Service.php\"}}"
printf '# Task: x\n- Mode: **COMMITTED**\n' > "$d/.claude/groundwork/task-state.md"
expect "W11 garbage mode opens"    0 "$d" "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/app/Service.php\"}}"

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
