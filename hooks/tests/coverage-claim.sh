#!/usr/bin/env bash
# Groundwork plugin :: executable proof for coverage-claim.sh (W14-AC5..AC8).
#
# The gate reads what the agent SAID, which no other hook does, so its whole surface is
# the last assistant message. Three things must hold or the gate is worse than nothing:
# it warns and never blocks in v0.24.0, it stays silent when the claim already carries a
# denominator, and it is inert outside a Groundwork project.
# Run: bash hooks/tests/coverage-claim.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/coverage-claim.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

# A Groundwork project fixture. $1 = dir, $2 = .groundwork.json body (default: minimal).
proj() {
  mkdir -p "$1/.claude/groundwork"
  printf '%s\n' "${2:-\{ \"database\": { \"default\": \"mysql\" } \}}" > "$1/.groundwork.json"
}

# Feed the hook a Stop payload. $1 = dir, $2 = last_assistant_message, $3 = stop_hook_active.
run() {
  local d="$1" msg="$2" active="${3:-false}" payload
  payload="$(jq -nc --arg m "$msg" --argjson a "$active" \
    '{session_id:"t-1", hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}')"
  ( cd "$d" && printf '%s' "$payload" | bash "$HOOK" 2>/dev/null )
}

exit_of() { # dir msg [active] -> exit code, and it must always be 0 in this release
  local d="$1" msg="$2" active="${3:-false}" payload
  payload="$(jq -nc --arg m "$msg" --argjson a "$active" \
    '{session_id:"t-1", hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}')"
  ( cd "$d" && printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1 ); printf '%s' $?
}

warns() { # name dir msg [active] — expects a systemMessage on stdout
  local out; out="$(run "$2" "$3" "${4:-false}")"
  if printf '%s' "$out" | jq -e '.systemMessage // empty' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %-38s [warned]\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %-38s want a systemMessage, got "%s"\n' "$1" "$out"
  fi
}

silent() { # name dir msg [active] — expects no systemMessage
  local out; out="$(run "$2" "$3" "${4:-false}")"
  if printf '%s' "$out" | jq -e '.systemMessage // empty' >/dev/null 2>&1; then
    fail=$((fail+1)); printf '  FAIL %-38s want silence, got "%s"\n' "$1" "$out"
  else
    pass=$((pass+1)); printf '  ok   %-38s [silent]\n' "$1"
  fi
}

eq() { # name want got
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-38s [%s]\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %-38s want "%s", got "%s"\n' "$1" "$2" "$3"; fi
}

log_lines() { local f="$1/.claude/groundwork/coverage-claims.log"; [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || printf '0'; }

echo "coverage-claim:"

# --- W14-AC5: a partiality marker with no denominator warns, in both languages ---
d="$ROOT/w1"; proj "$d"
warns  "en marker, no denominator"  "$d" "I checked it selectively and everything looks fine."
d="$ROOT/w2"; proj "$d"
warns  "ru marker, no denominator"  "$d" "Проверил выборочно, всё работает."
d="$ROOT/w3"; proj "$d"
warns  "ru superficial"             "$d" "Я только поверхностно прошёлся по эндпоинтам."
d="$ROOT/w4"; proj "$d"
warns  "en hedge should work"       "$d" "The endpoint should work now."

# --- W14-AC1/AC2 satisfied in the message => silence (the gate is about the missing half) ---
d="$ROOT/s1"; proj "$d"
silent "marker + en fraction"       "$d" "I checked it selectively: 7 of 7 endpoints on the impact map."
d="$ROOT/s2"; proj "$d"
silent "marker + ru fraction"       "$d" "Проверил выборочно: 3 из 12, остальные 9 перечислены ниже."
d="$ROOT/s3"; proj "$d"
silent "marker + slash fraction"    "$d" "Spot-checked the consumers (5/5 from the impact map)."
d="$ROOT/s4"; proj "$d"
silent "marker + uncovered list"    "$d" "I went over it superficially. Not covered: the export job, the notification."
d="$ROOT/s5"; proj "$d"
silent "marker + ru uncovered"      "$d" "Прошёлся поверхностно. Не покрыт экспорт и уведомления."
d="$ROOT/s6"; proj "$d"
silent "third form: no verification" "$d" "Проверки не было — я ничего не запускал."
d="$ROOT/s7"; proj "$d"
silent "third form en"              "$d" "No verification was performed; this was a docs-only change."
d="$ROOT/s8"; proj "$d"
silent "clean message, no marker"   "$d" "Added the FormRequest and its tests. All 14 tests pass."

# --- W14-AC6: the loop guard ---
d="$ROOT/g1"; proj "$d"
silent "stop_hook_active true"      "$d" "I checked it selectively." "true"
eq     "AC6 no log while re-entrant" "0" "$(log_lines "$d")"

# --- W14-AC7: never blocks, and logs one line per trigger ---
d="$ROOT/l1"; proj "$d"
eq     "AC7 exit 0 on a warning"    "0" "$(exit_of "$d" "Проверил выборочно.")"
eq     "AC7 one log line"           "1" "$(log_lines "$d")"
run "$d" "I checked it selectively." >/dev/null
eq     "AC7 two log lines"          "2" "$(log_lines "$d")"
d="$ROOT/l2"; proj "$d"
run "$d" "Added tests. 14 of 14 pass." >/dev/null
eq     "AC7 clean message logs none" "0" "$(log_lines "$d")"

# --- W14-AC8: inert outside a Groundwork project, and behind its toggle ---
d="$ROOT/o1"; mkdir -p "$d"          # no .groundwork.json at all
silent "no .groundwork.json"        "$d" "Проверил выборочно."
eq     "AC8 exit 0 without config"  "0" "$(exit_of "$d" "Проверил выборочно.")"
d="$ROOT/o2"; proj "$d" '{ "gates": { "coverage_claim": false } }'
silent "toggle off"                 "$d" "Проверил выборочно."
eq     "AC8 no log when off"        "0" "$(log_lines "$d")"
d="$ROOT/o3"; proj "$d" '{ "gates": { "coverage_claim": true } }'
warns  "toggle explicitly on"       "$d" "Проверил выборочно."

# --- robustness: the payload is not always what we expect ---
d="$ROOT/r1"; proj "$d"
( cd "$d" && printf '%s' 'not json at all' | bash "$HOOK" >/dev/null 2>&1 ); eq "malformed stdin exits 0" "0" "$?"
d="$ROOT/r2"; proj "$d"
( cd "$d" && printf '%s' '{"hook_event_name":"Stop"}' | bash "$HOOK" >/dev/null 2>&1 ); eq "missing message exits 0" "0" "$?"
d="$ROOT/r3"; proj "$d"
silent "empty message"              "$d" ""

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
