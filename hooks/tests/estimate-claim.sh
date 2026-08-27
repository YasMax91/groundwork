#!/usr/bin/env bash
# Groundwork plugin :: executable proof for estimate-claim.sh (W18-AC10..AC13).
#
# The gate reads what the agent SAID. Three things must hold or it is worse than nothing: it warns
# on a human-work-day-sized number with nothing slow named beside it, it stays silent when the cause
# IS named or the number rests on the ledger, and it never blocks in v0.28.0.
# Run: bash hooks/tests/estimate-claim.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/estimate-claim.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() {
  mkdir -p "$1/.claude/groundwork"
  printf '%s\n' "${2:-\{ \"database\": { \"default\": \"mysql\" } \}}" > "$1/.groundwork.json"
}

run() { # dir msg [stop_hook_active]
  local d="$1" msg="$2" active="${3:-false}" payload
  payload="$(jq -nc --arg m "$msg" --argjson a "$active" \
    '{session_id:"t-1", hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}')"
  ( cd "$d" && printf '%s' "$payload" | bash "$HOOK" 2>/dev/null )
}

exit_of() {
  local d="$1" msg="$2" active="${3:-false}" payload
  payload="$(jq -nc --arg m "$msg" --argjson a "$active" \
    '{session_id:"t-1", hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}')"
  ( cd "$d" && printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1 ); printf '%s' $?
}

warns() {
  local out; out="$(run "$2" "$3" "${4:-false}")"
  if printf '%s' "$out" | jq -e '.systemMessage // empty' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %-42s [warned]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-42s want a systemMessage, got "%s"\n' "$1" "$out"; fi
}

silent() {
  local out; out="$(run "$2" "$3" "${4:-false}")"
  if printf '%s' "$out" | jq -e '.systemMessage // empty' >/dev/null 2>&1; then
    fail=$((fail+1)); printf '  FAIL %-42s want silence, got "%s"\n' "$1" "$out"
  else pass=$((pass+1)); printf '  ok   %-42s [silent]\n' "$1"; fi
}

eq() {
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-42s [%s]\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %-42s want "%s", got "%s"\n' "$1" "$2" "$3"; fi
}

log_lines() { local f="$1/.claude/groundwork/estimate-claims.log"; [ -f "$f" ] && wc -l < "$f" | tr -d ' ' || printf '0'; }

echo "estimate-claim:"

# --- AC10: a human-work-day-sized number with nothing slow named ------------------------------
d="$ROOT/w1"; proj "$d"; warns "en hours, bare"        "$d" "Building the CRUD endpoints will take about 6 hours."
d="$ROOT/w2"; proj "$d"; warns "ru hours, bare"        "$d" "На этот CRUD уйдёт примерно 6 часов."
d="$ROOT/w3"; proj "$d"; warns "en days"               "$d" "I would budget 2 days for this feature."
d="$ROOT/w4"; proj "$d"; warns "ru days"               "$d" "Думаю, 3 дня на реализацию."
d="$ROOT/w5"; proj "$d"; warns "man-day"               "$d" "Roughly one man-day of work."
d="$ROOT/w6"; proj "$d"; warns "en range in hours"     "$d" "Somewhere between 4-8 hours."
d="$ROOT/w7"; proj "$d"; warns "ru человеко-"          "$d" "Оценка: 8 человеко-часов."

# --- AC10: silence when the slow thing IS named, or the number rests on the ledger ------------
d="$ROOT/s1"; proj "$d"
silent "en hours + external API"  "$d" "About 3 hours, and the reason is the external API: its docs have to be established against a sandbox probe first."
d="$ROOT/s2"; proj "$d"
silent "ru hours + внешний API"   "$d" "Часа три, и это внешний API: надо поднять песочницу и проверить, что провайдер реально возвращает."
d="$ROOT/s3"; proj "$d"
silent "hours + ledger median"    "$d" "Estimate 2 hours; ledger median=14 min over n=76 windows, and this task is four such blocks plus a migration over a large table."
d="$ROOT/s4"; proj "$d"
silent "human time line"          "$d" "Development: 25 active minutes. Your time: 2 hours to register the provider account and issue the keys."
d="$ROOT/s5"; proj "$d"
silent "reported actual"          "$d" "It took 2 hours of wall clock in the end, 31 active minutes of that."
d="$ROOT/s6"; proj "$d"
silent "minutes only"             "$d" "About 25 active minutes for the endpoint, its tests and the OpenAPI."
d="$ROOT/s7"; proj "$d"
silent "no duration at all"       "$d" "Done: the filter is implemented and the suite is green."

# --- AC11: the loop guard --------------------------------------------------------------------
d="$ROOT/g1"; proj "$d"
silent "stop_hook_active=true"    "$d" "This will take about 6 hours." true

# --- AC12: never blocks, and every trigger is logged ------------------------------------------
d="$ROOT/l1"; proj "$d"
eq "AC12 exit 0 when warning"  "0" "$(exit_of "$d" "About 6 hours of work.")"
eq "AC12 logged once"          "1" "$(log_lines "$d")"
run "$d" "Another one: 2 days." >/dev/null
eq "AC12 logged twice"         "2" "$(log_lines "$d")"
d="$ROOT/l2"; proj "$d"
eq "AC12 exit 0 when silent"   "0" "$(exit_of "$d" "About 25 active minutes.")"
eq "AC12 no log when silent"   "0" "$(log_lines "$d")"

# --- AC13: inert without config and under the opt-out -----------------------------------------
d="$ROOT/n1"; mkdir -p "$d/.claude/groundwork"        # no .groundwork.json
silent "no config: silent"        "$d" "About 6 hours of work."
eq "no config: exit 0" "0" "$(exit_of "$d" "About 6 hours of work.")"
d="$ROOT/n2"; proj "$d" '{ "gates": { "estimate_claim": false } }'
silent "opt-out: silent"          "$d" "About 6 hours of work."
eq "opt-out: no log" "0" "$(log_lines "$d")"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
