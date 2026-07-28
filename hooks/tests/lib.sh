#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/lib.sh (W11-AC1..AC5, AC8).
# The shared resolver decides which command every gate runs and whether the one hard
# mode-gate fires, so each function gets its cases here. Run: bash hooks/tests/lib.sh
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
[ -f "$LIB" ] || { echo "lib not found: $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

# shellcheck source=/dev/null
. "$LIB"

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

eq() { # name want got
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-30s [%s]\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %-30s want "%s", got "%s"\n' "$1" "$2" "$3"; fi
}

sdd() { printf '%s\n' "$2" > "$1/.groundwork.json"; }
fake_sail() { mkdir -p "$1/vendor/bin"; printf '#!/bin/sh\nexit 0\n' > "$1/vendor/bin/sail"; chmod +x "$1/vendor/bin/sail"; }
state() { mkdir -p "$1/.claude/groundwork"; printf '%s\n' "$2" > "$1/.claude/groundwork/task-state.md"; }

echo "lib:"

# --- command building: sail (default and explicit) vs host, per tool ---
d="$ROOT/r1"; mkdir -p "$d"; sdd "$d" '{ "runner": "sail" }'
eq "sail artisan"    './vendor/bin/sail artisan test'          "$( cd "$d" && gw_cmd artisan test )"
eq "sail composer"   './vendor/bin/sail composer analyse'      "$( cd "$d" && gw_cmd composer analyse )"
eq "sail pint"       './vendor/bin/sail pint'                  "$( cd "$d" && gw_cmd pint )"
d="$ROOT/r2"; mkdir -p "$d"; sdd "$d" '{ "runner": "host" }'
eq "host artisan php" 'php artisan test'                       "$( cd "$d" && gw_cmd artisan test )"
eq "host composer"    'composer analyse'                       "$( cd "$d" && gw_cmd composer analyse )"
eq "host pint path"   './vendor/bin/pint'                      "$( cd "$d" && gw_cmd pint )"
eq "host multiword"   'php artisan l5-swagger:generate'        "$( cd "$d" && gw_cmd artisan l5-swagger:generate )"
d="$ROOT/r3"; mkdir -p "$d"; sdd "$d" '{ "database": { "default": "mysql" } }'
eq "default is sail"  './vendor/bin/sail artisan test'         "$( cd "$d" && gw_cmd artisan test )"
d="$ROOT/r4"; mkdir -p "$d"   # no config at all
eq "no config sail"   './vendor/bin/sail artisan test'         "$( cd "$d" && gw_cmd artisan test )"

# --- runner readiness: host is always ready; sail needs the binary ---
d="$ROOT/r5"; mkdir -p "$d"; sdd "$d" '{ "runner": "host" }'
( cd "$d" && gw_runner_ready ); eq "ready host (no sail)" 0 $?
d="$ROOT/r6"; mkdir -p "$d"; sdd "$d" '{ "runner": "sail" }'
( cd "$d" && gw_runner_ready ); eq "ready sail missing"   1 $?
fake_sail "$d"
( cd "$d" && gw_runner_ready ); eq "ready sail present"   0 $?

# --- mode canon: valid values, emphasis stripping, garbage rejection ---
d="$ROOT/m1"; mkdir -p "$d"; state "$d" '# Task: x
- Mode: Discovery'
eq "mode plain"          'Discovery'      "$( cd "$d" && gw_mode )"
d="$ROOT/m2"; mkdir -p "$d"; state "$d" '- Mode: **Discovery**'
eq "mode emphasised"     'Discovery'      "$( cd "$d" && gw_mode )"
d="$ROOT/m3"; mkdir -p "$d"; state "$d" '- Mode: **COMMITTED**'
eq "mode garbage empty"  ''               "$( cd "$d" && gw_mode )"
d="$ROOT/m4"; mkdir -p "$d"; state "$d" '- Mode: implementation'
eq "mode case-insens"    'Implementation' "$( cd "$d" && gw_mode )"
d="$ROOT/m5"; mkdir -p "$d"; state "$d" '- Mode: Discovery | Plan | Review'
eq "mode template line"  'Discovery'      "$( cd "$d" && gw_mode )"
d="$ROOT/m6"; mkdir -p "$d"; state "$d" '- Mode: `Review`'
eq "mode backticks"      'Review'         "$( cd "$d" && gw_mode )"
d="$ROOT/m7"; mkdir -p "$d"   # no checkpoint at all
eq "mode no checkpoint"  ''               "$( cd "$d" && gw_mode )"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
