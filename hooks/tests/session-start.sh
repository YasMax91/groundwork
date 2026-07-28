#!/usr/bin/env bash
# RaDevs plugin :: executable proof for session-start.sh.
# The checkpoint is the expensive part of the injection (~1k tokens), so it is paid for only while
# a task is actually running. These tests pin both directions. Run: bash hooks/tests/session-start.sh
set -uo pipefail

SS="$(cd "$(dirname "$0")/.." && pwd)/session-start.sh"
[ -f "$SS" ] || { echo "session-start not found: $SS"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

ctx() { ( cd "$1" && printf '{}' | bash "$SS" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' ); }

has() { # name dir substr
  local out; out="$(ctx "$2")"
  if printf '%s' "$out" | grep -q -- "$3"; then pass=$((pass+1)); printf '  ok   %-34s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-34s want "%s" in:\n%s\n' "$1" "$3" "$out"; fi
}
hasnt() { # name dir substr
  local out; out="$(ctx "$2")"
  if printf '%s' "$out" | grep -q -- "$3"; then fail=$((fail+1)); printf '  FAIL %-34s did not want "%s"\n' "$1" "$3"
  else pass=$((pass+1)); printf '  ok   %-34s\n' "$1"; fi
}
valid_json() { # name dir
  if ( cd "$2" && printf '{}' | bash "$SS" 2>/dev/null | jq -e . >/dev/null 2>&1 ); then
    pass=$((pass+1)); printf '  ok   %-34s\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-34s output is not valid JSON\n' "$1"; fi
}

mk() { # dir mode-line -> project fixture with a fat checkpoint
  mkdir -p "$1/.claude/groundwork"
  printf '{ "database": { "default": "mysql" } }\n' > "$1/.groundwork.json"
  { printf '# Task: probe task\n\n- %s\n' "$2"
    i=0; while [ "$i" -lt 40 ]; do printf -- '- decision %s: a long recorded line that costs tokens on every session start\n' "$i"; i=$((i+1)); done
  } > "$1/.claude/groundwork/task-state.md"
}

# An active mode injects the checkpoint in full — resuming a running task must not get cheaper.
d="$ROOT/active"; mk "$d" "Mode: Implementation | Level: L2"
has        "active mode injects checkpoint" "$d" "Active task checkpoint"
has        "active mode carries the body"   "$d" "decision 39"
valid_json "active mode emits valid JSON"   "$d"

# A finished checkpoint costs one pointer line instead of the whole file.
d="$ROOT/done"; mk "$d" "Mode: **DONE — committed abc1234 on \`development\`**"
has        "finished checkpoint is a pointer" "$d" "not in an active mode"
hasnt      "finished checkpoint drops body"   "$d" "decision 39"
has        "pointer keeps the task title"     "$d" "probe task"
valid_json "finished checkpoint valid JSON"   "$d"

# Every other guarantee the hook already made stays intact.
d="$ROOT/none"; mkdir -p "$d"
if [ -z "$(ctx "$d")" ]; then pass=$((pass+1)); printf '  ok   %-34s\n' "non-RaDevs project stays silent"
else fail=$((fail+1)); printf '  FAIL %-34s expected no output\n' "non-RaDevs project stays silent"; fi

d="$ROOT/off"; mkdir -p "$d/.claude/groundwork"
printf '{ "memory": { "session_context": false } }\n' > "$d/.groundwork.json"
printf '# Task: x\n- Mode: Implementation\n' > "$d/.claude/groundwork/task-state.md"
if [ -z "$(ctx "$d")" ]; then pass=$((pass+1)); printf '  ok   %-34s\n' "session_context=false opts out"
else fail=$((fail+1)); printf '  FAIL %-34s expected no output\n' "session_context=false opts out"; fi

printf '\n  passed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
