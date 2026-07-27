#!/usr/bin/env bash
# RaDevs plugin :: executable proof for statusline.sh (W5-AC1..AC3).
# Builds throwaway fixtures and asserts the rendered line. Run: bash hooks/tests/statusline.sh
set -uo pipefail

SL="$(cd "$(dirname "$0")/.." && pwd)/statusline.sh"
[ -f "$SL" ] || { echo "statusline not found: $SL"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

run() { ( cd "$1" && printf '%s' "${2:-}" | bash "$SL" 2>/dev/null ); }

contains() { # name dir substr
  local out; out="$(run "$2")"
  if printf '%s' "$out" | grep -q -- "$3"; then pass=$((pass+1)); printf '  ok   %-24s [%s]\n' "$1" "$out"
  else fail=$((fail+1)); printf '  FAIL %-24s want "%s", got "%s"\n' "$1" "$3" "$out"; fi
}
empty() { # name dir
  local out; out="$(run "$2")"
  if [ -z "$out" ]; then pass=$((pass+1)); printf '  ok   %-24s [empty]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-24s want empty, got "%s"\n' "$1" "$out"; fi
}

# AC1: full project with a task-state checkpoint renders the state
d="$ROOT/ac1"; mkdir -p "$d/.claude/groundwork"
printf '{ "database": { "default": "pgsql" }, "ui": { "statusline": true } }\n' > "$d/.groundwork.json"
printf '# Task: x\n- Mode: Implementation\n- Level: L3\n- Spec: docs/specs/orders.md\n' > "$d/.claude/groundwork/task-state.md"
contains "AC1 mode"   "$d" "Implementation"
contains "AC1 engine" "$d" "pgsql"
contains "AC1 spec"   "$d" "spec:orders.md"

# AC2: no .groundwork.json -> empty; ui.statusline false -> empty
d="$ROOT/ac2a"; mkdir -p "$d"
empty "AC2 no config" "$d"
d="$ROOT/ac2b"; mkdir -p "$d"; printf '{ "ui": { "statusline": false } }\n' > "$d/.groundwork.json"
empty "AC2 toggle off" "$d"

# AC3: project but no task-state -> still renders, never errors
d="$ROOT/ac3"; mkdir -p "$d"; printf '{ "database": { "default": "mysql" } }\n' > "$d/.groundwork.json"
contains "AC3 no taskstate" "$d" "RaDevs"
contains "AC3 mysql"        "$d" "mysql"

# W11-AC4/AC5: only a canonical Mode renders; Markdown emphasis is stripped, garbage is not shown
d="$ROOT/w11a"; mkdir -p "$d/.claude/groundwork"
printf '{ "ui": { "statusline": true } }\n' > "$d/.groundwork.json"
printf '# Task: x\n- Mode: **Review**\n' > "$d/.claude/groundwork/task-state.md"
contains "W11 emphasised mode" "$d" "Review"
printf '# Task: x\n- Mode: **COMMITTED**\n' > "$d/.claude/groundwork/task-state.md"
out="$(run "$d")"
if printf '%s' "$out" | grep -q "COMMITTED"; then
  fail=$((fail+1)); printf '  FAIL %-24s garbage mode leaked: "%s"\n' "W11 garbage not shown" "$out"
else
  pass=$((pass+1)); printf '  ok   %-24s [%s]\n' "W11 garbage not shown" "$out"
fi

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
