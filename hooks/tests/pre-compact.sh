#!/usr/bin/env bash
# Groundwork plugin :: executable proof for pre-compact.sh (wave 19).
# The breadcrumb it appends is what makes the checkpoint win over a thinned transcript after
# compaction — and it must never grow the file without bound. Run: bash hooks/tests/pre-compact.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/pre-compact.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

STATE=".claude/groundwork/task-state.md"
project() { # $1 = dir, $2 = memory.checkpoint value
  mkdir -p "$1/.claude/groundwork"
  printf '{ "runner": "sail", "memory": { "checkpoint": %s } }\n' "$2" > "$1/.groundwork.json"
  printf '# Task: orders\n- Mode: Implementation\n' > "$1/$STATE"
}
run() { ( cd "$1" && printf '%s' "${2:-}" | bash "$HOOK" >/dev/null 2>&1 ); }
marks() { # how many breadcrumbs the checkpoint carries (0 when the file or the line is absent)
  local n
  n="$(grep -c 'context compacted' "$1/$STATE" 2>/dev/null)" || n=0
  printf '%s' "${n:-0}"
}

check() { # name actual expected
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-30s (%s)\n' "$1" "$2"
  else fail=$((fail+1)); printf '  FAIL %-30s want %s, got %s\n' "$1" "$3" "$2"; fi
}

# The breadcrumb lands, and it carries the trigger that caused the compaction.
d="$ROOT/on"; project "$d" true
run "$d" '{"trigger":"manual"}'
check "breadcrumb written" "$(marks "$d")" "1"
if grep -q 'manual' "$d/$STATE"; then pass=$((pass+1)); printf '  ok   %-30s (trigger recorded)\n' "trigger in the line"
else fail=$((fail+1)); printf '  FAIL %-30s trigger missing\n' "trigger in the line"; fi

# Compacting twice in a row must not stack two identical lines.
run "$d" '{"trigger":"manual"}'
check "no unbounded growth" "$(marks "$d")" "1"

# A different trigger is a different event and is allowed to add its own line.
run "$d" '{"trigger":"auto"}'
check "new trigger appends" "$(marks "$d")" "2"

# Opt-out and the fail-safe paths: nothing is written, nothing is created.
d="$ROOT/off"; project "$d" false
run "$d" '{"trigger":"manual"}'
check "memory.checkpoint=false" "$(marks "$d")" "0"

d="$ROOT/bare"; mkdir -p "$d/.claude/groundwork"   # no .groundwork.json
printf '# Task: x\n- Mode: Spec\n' > "$d/$STATE"
run "$d" '{"trigger":"manual"}'
check "no groundwork project" "$(marks "$d")" "0"

d="$ROOT/nostate"; mkdir -p "$d"
printf '{ "runner": "sail" }\n' > "$d/.groundwork.json"
run "$d" '{"trigger":"manual"}'
if [ ! -f "$d/$STATE" ]; then pass=$((pass+1)); printf '  ok   %-30s (no checkpoint invented)\n' "missing checkpoint"
else fail=$((fail+1)); printf '  FAIL %-30s the hook created a checkpoint\n' "missing checkpoint"; fi

# Empty stdin is what a PreCompact with no payload looks like: still safe, trigger falls back.
d="$ROOT/empty"; project "$d" true
run "$d" ''
check "empty stdin still safe" "$(marks "$d")" "1"

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
