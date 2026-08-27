#!/usr/bin/env bash
# Groundwork plugin :: executable proof for session-start.sh.
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
if [ -z "$(ctx "$d")" ]; then pass=$((pass+1)); printf '  ok   %-34s\n' "non-Groundwork project stays silent"
else fail=$((fail+1)); printf '  FAIL %-34s expected no output\n' "non-Groundwork project stays silent"; fi

d="$ROOT/off"; mkdir -p "$d/.claude/groundwork"
printf '{ "memory": { "session_context": false } }\n' > "$d/.groundwork.json"
printf '# Task: x\n- Mode: Implementation\n' > "$d/.claude/groundwork/task-state.md"
if [ -z "$(ctx "$d")" ]; then pass=$((pass+1)); printf '  ok   %-34s\n' "session_context=false opts out"
else fail=$((fail+1)); printf '  FAIL %-34s expected no output\n' "session_context=false opts out"; fi

# --- wave 27: the framework support window ------------------------------------------------------
lock() { # dir version
  mkdir -p "$1"; printf '{ "runner": "sail" }\n' > "$1/.groundwork.json"
  printf '{"packages":[{"name":"laravel/framework","version":"%s"}]}\n' "$2" > "$1/composer.lock"
}
d="$ROOT/eol12"; lock "$d" "v12.31.1"
has   "L12 is past bug fixes"        "$d" "left its bug-fix window on 2026-08-13"
d="$ROOT/eol13"; lock "$d" "v13.2.0"
hasnt "L13 is current, no notice"    "$d" "bug-fix window"
d="$ROOT/eol-unknown"; lock "$d" "v99.0.0"
hasnt "unknown major stays silent"   "$d" "bug-fix window"
d="$ROOT/eol-nolock"; mkdir -p "$d"; printf '{ "runner": "sail" }\n' > "$d/.groundwork.json"
hasnt "no composer.lock, no guess"   "$d" "bug-fix window"
d="$ROOT/eol-broken"; mkdir -p "$d"; printf '{ "runner": "sail" }\n' > "$d/.groundwork.json"
printf 'not json at all\n' > "$d/composer.lock"
hasnt "unreadable lock stays silent" "$d" "bug-fix window"
valid_json "output stays valid JSON" "$d"


printf '\n  passed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
