#!/usr/bin/env bash
# Groundwork plugin :: executable proof for test-gate.sh (W11-AC2, AC6, AC7).
# The gate must serialise the suite across parallel sessions without ever inventing a red:
# a busy test DB is an environment problem, a failing suite is a defect. Only the second blocks.
# Run: bash hooks/tests/test-gate.sh
set -uo pipefail

GATE="$(cd "$(dirname "$0")/.." && pwd)/test-gate.sh"
[ -f "$GATE" ] || { echo "gate not found: $GATE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

expect() { # name want dir
  local name="$1" want="$2" dir="$3" got
  ( cd "$dir" && bash "$GATE" >/dev/null 2>&1 ); got=$?
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf '  ok   %-30s (exit %s)\n' "$name" "$got"
  else fail=$((fail+1)); printf '  FAIL %-30s (want %s, got %s)\n' "$name" "$want" "$got"; fi
}

# fixture <dir> <json-gates> — a git repo with one uncommitted PHP change
fixture() {
  local d="$1"
  mkdir -p "$d/app"
  printf '%s\n' "$2" > "$d/.groundwork.json"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && printf '<?php\n' > seed.txt && git add -A && git commit -qm init )
  printf '<?php\nclass A {}\n' > "$d/app/A.php"      # uncommitted PHP -> the gate fires
}
stub() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\nexit %s\n' "${2:-0}" > "$1"; chmod +x "$1"; }

echo "test-gate:"

# --- passing suite -> allow; failing suite -> block (baseline, must not regress) ---
d="$ROOT/t1"; fixture "$d" '{ "runner": "host", "commands": { "test": "./ok.sh" } }'; stub "$d/ok.sh" 0
expect "green suite allows"        0 "$d"
d="$ROOT/t2"; fixture "$d" '{ "runner": "host", "commands": { "test": "./bad.sh" } }'; stub "$d/bad.sh" 1
expect "red suite blocks"          2 "$d"

# --- W11-AC2: runner:host without Sail must still RUN (previously skipped silently) ---
d="$ROOT/t3"; fixture "$d" '{ "runner": "host", "commands": { "test": "./bad.sh" } }'; stub "$d/bad.sh" 1
expect "host runs without sail"    2 "$d"          # proves it did not skip to exit 0
d="$ROOT/t4"; fixture "$d" '{ "runner": "sail", "commands": { "test": "./vendor/bin/sail artisan test" } }'
expect "sail missing skips"        0 "$d"          # unchanged bootstrap fail-open

# --- W11-AC6: a lock held by another session -> wait, then allow with a reason (never red) ---
d="$ROOT/t5"; fixture "$d" '{ "runner": "host", "commands": { "test": "./bad.sh" },
  "gates": { "test_db_lock": true, "test_lock_wait_seconds": 1 } }'; stub "$d/bad.sh" 1
mkdir -p "$d/.claude/groundwork/locks/test-db"                 # someone else holds it, fresh
expect "busy lock reports, no red" 1 "$d"

# --- the lock is released after a run, so a second run is not blocked by the first ---
d="$ROOT/t6"; fixture "$d" '{ "runner": "host", "commands": { "test": "./ok.sh" },
  "gates": { "test_db_lock": true, "test_lock_wait_seconds": 1 } }'; stub "$d/ok.sh" 0
expect "first run allows"          0 "$d"
expect "second run not stuck"      0 "$d"
if [ ! -d "$d/.claude/groundwork/locks/test-db" ]; then
  pass=$((pass+1)); printf '  ok   %-30s [released]\n' "lock released on exit"
else
  fail=$((fail+1)); printf '  FAIL %-30s lock dir still present\n' "lock released on exit"
fi

# --- a stale lock (an interrupted session) is taken over, not honored forever ---
d="$ROOT/t7"; fixture "$d" '{ "runner": "host", "commands": { "test": "./bad.sh" },
  "gates": { "test_db_lock": true, "test_lock_wait_seconds": 1 } }'; stub "$d/bad.sh" 1
mkdir -p "$d/.claude/groundwork/locks/test-db"
touch -t 200001010000 "$d/.claude/groundwork/locks/test-db"     # ancient -> stale
expect "stale lock taken over"     2 "$d"          # ran the suite, which is red

# --- W11-AC7: the lock is opt-out ---
d="$ROOT/t8"; fixture "$d" '{ "runner": "host", "commands": { "test": "./bad.sh" },
  "gates": { "test_db_lock": false } }'; stub "$d/bad.sh" 1
mkdir -p "$d/.claude/groundwork/locks/test-db"                 # held, but locking is disabled
expect "lock disabled ignores it"  2 "$d"

# --- W11-AC12: PHP inside a BRAND-NEW untracked directory must still trigger the gate.
# Without `-uall`, git reports "?? app/Services/" and never the .php inside, so the gate skipped.
d="$ROOT/t10"; mkdir -p "$d"
printf '{ "runner": "host", "commands": { "test": "./bad.sh" } }\n' > "$d/.groundwork.json"
( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'x\n' > a.txt && git add -A && git commit -qm init )
stub "$d/bad.sh" 1
mkdir -p "$d/app/Services"; printf '<?php\nclass FooService {}\n' > "$d/app/Services/FooService.php"
expect "new dir php detected"      2 "$d"

# --- REGRESSION GUARD: an explicit commands.* override must win over the runner's availability.
# A sail-runner project without the Sail binary that deliberately points the gate elsewhere must
# still run it (this is the workaround projects used before runner: host was honored).
d="$ROOT/t11"; fixture "$d" '{ "runner": "sail", "commands": { "test": "./bad.sh" } }'; stub "$d/bad.sh" 1
expect "override beats runner"     2 "$d"

# --- the lock must not spin when it cannot be managed: unwritable lock parent -> run unlocked ---
d="$ROOT/t12"; fixture "$d" '{ "runner": "host", "commands": { "test": "./bad.sh" },
  "gates": { "test_db_lock": true, "test_lock_wait_seconds": 2 } }'; stub "$d/bad.sh" 1
mkdir -p "$d/.claude/groundwork/locks"; chmod 500 "$d/.claude/groundwork/locks"
start=$(date +%s); ( cd "$d" && bash "$GATE" >/dev/null 2>&1 ); got=$?; elapsed=$(( $(date +%s) - start ))
chmod 700 "$d/.claude/groundwork/locks"
if [ "$got" = 2 ] && [ "$elapsed" -lt 10 ]; then
  pass=$((pass+1)); printf '  ok   %-30s (exit %s, %ss — no spin)\n' "unlockable runs unlocked" "$got" "$elapsed"
else
  fail=$((fail+1)); printf '  FAIL %-30s (want exit 2 fast, got %s in %ss)\n' "unlockable runs unlocked" "$got" "$elapsed"
fi

# --- a lock owned by ANOTHER live session must survive our exit (no cross-session deletion) ---
d="$ROOT/t13"; fixture "$d" '{ "runner": "host", "commands": { "test": "./ok.sh" },
  "gates": { "test_db_lock": true, "test_lock_wait_seconds": 1 } }'; stub "$d/ok.sh" 0
mkdir -p "$d/.claude/groundwork/locks/test-db"; printf 'someone-else\n' > "$d/.claude/groundwork/locks/test-db/owner"
( cd "$d" && bash "$GATE" >/dev/null 2>&1 )
if [ -d "$d/.claude/groundwork/locks/test-db" ] && grep -q 'someone-else' "$d/.claude/groundwork/locks/test-db/owner" 2>/dev/null; then
  pass=$((pass+1)); printf '  ok   %-30s [foreign lock intact]\n' "never deletes foreign lock"
else
  fail=$((fail+1)); printf '  FAIL %-30s foreign lock was removed\n' "never deletes foreign lock"
fi

# --- unrelated: no PHP changed -> silent no-op ---
d="$ROOT/t9"; mkdir -p "$d"; printf '{ "runner": "host" }\n' > "$d/.groundwork.json"
( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'x\n' > a.txt && git add -A && git commit -qm init )
expect "no php change no-op"       0 "$d"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
