#!/usr/bin/env bash
# Groundwork plugin :: executable proof for trim-output.sh (wave 19).
# This hook rewrites what the agent sees, so its fail-safe promises are the whole point:
# opt-in only, never trim a failure, never trim what it cannot positively locate.
# Run: bash hooks/tests/trim-output.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/trim-output.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

conf() { printf '{ "runner": "sail", "gates": { "trim_tool_output": %s } }\n' "$2" > "$1/.groundwork.json"; }
run()  { ( cd "$1" && printf '%s' "$2" | bash "$HOOK" 2>/dev/null ); }

payload() { # $1 = command, $2 = tool output text -> PostToolUse stdin
  jq -nc --arg c "$1" --arg o "$2" '{tool_name:"Bash",tool_input:{command:$c},tool_response:$o}'
}
long_pass() { # 40 lines that only ever say "passed"
  local i=1; while [ "$i" -le 39 ]; do printf '  PASS  Tests\\Feature\\Case%s\n' "$i"; i=$((i+1)); done
  printf 'Tests:    39 passed (78 assertions)\n'
}

trims() { # name dir stdin
  local out; out="$(run "$2" "$3")"
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.updatedToolOutput' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %-26s (trimmed)\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %-26s want a trim, got: %s\n' "$1" "$out"
  fi
}
untouched() { # name dir stdin
  local out; out="$(run "$2" "$3")"
  if [ -z "$out" ]; then pass=$((pass+1)); printf '  ok   %-26s (passed through)\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-26s want no change, got: %s\n' "$1" "$out"; fi
}

d="$ROOT/on";  mkdir -p "$d"; conf "$d" true
d_off="$ROOT/off"; mkdir -p "$d_off"; conf "$d_off" false
d_bare="$ROOT/bare"; mkdir -p "$d_bare"   # no .groundwork.json at all

PASSING="$(long_pass)"
FAILING="$(long_pass; printf 'FAILED  Tests\\Feature\\Broken > it works\n')"

# The one case where trimming is allowed at all.
trims     "opt-in + noisy + passing" "$d" "$(payload 'sail artisan test' "$PASSING")"

# Everything else must leave the output alone.
untouched "opt-out"                  "$d_off"  "$(payload 'sail artisan test' "$PASSING")"
untouched "no groundwork project"    "$d_bare" "$(payload 'sail artisan test' "$PASSING")"
untouched "a failure is never hidden" "$d"     "$(payload 'sail artisan test' "$FAILING")"
untouched "unknown command"          "$d"      "$(payload 'ls -la app' "$PASSING")"
untouched "short output"             "$d"      "$(payload 'sail artisan test' 'Tests: 2 passed')"
untouched "output field not found"   "$d"      '{"tool_name":"Bash","tool_input":{"command":"sail artisan test"},"unknown_field":"PASS"}'
untouched "empty stdin"              "$d"      ''

# A trim must keep the tail — the summary line is the reason to look at the output at all.
out="$(run "$d" "$(payload 'sail artisan test' "$PASSING")" | jq -r '.hookSpecificOutput.updatedToolOutput' 2>/dev/null)"
if printf '%s' "$out" | grep -q '39 passed' && printf '%s' "$out" | grep -q 'trimmed'; then
  pass=$((pass+1)); printf '  ok   %-26s (tail + marker kept)\n' "trim keeps the summary"
else
  fail=$((fail+1)); printf '  FAIL %-26s got: %s\n' "trim keeps the summary" "$out"
fi

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
