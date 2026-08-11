#!/usr/bin/env bash
# Groundwork plugin :: executable proof for agent-contract.sh (W17-AC5..AC9).
#
# The grounding protocol's central rule — never guess; every claim carries a source or is marked
# UNKNOWN — was enforced only by the agent's own prompt. This hook makes the engine enforce it, so
# the cases that matter are: a contract-breaking return is blocked exactly once, a conforming one is
# untouched, and the re-entry after a block never blocks again.
# Run: bash hooks/tests/agent-contract.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/agent-contract.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() { mkdir -p "$1/.claude/groundwork"; printf '%s\n' "${2:-\{ \"runner\": \"host\" \}}" > "$1/.groundwork.json"; }

run() { # dir agent_type message [active]
  local payload
  payload="$(jq -nc --arg t "$2" --arg m "$3" --argjson a "${4:-false}" \
    '{session_id:"s1", agent_id:"a1", hook_event_name:"SubagentStop", agent_type:$t, stop_hook_active:$a, last_assistant_message:$m}')"
  ( cd "$1" && printf '%s' "$payload" | bash "$HOOK" 2>/dev/null )
}

blocks() { # name dir type msg [active]
  local out; out="$(run "$2" "$3" "$4" "${5:-false}")"
  if [ "$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)" = "block" ]; then
    pass=$((pass+1)); printf '  ok   %-40s [blocked]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-40s want a block, got "%s"\n' "$1" "$out"; fi
}

allows() { # name dir type msg [active]
  local out; out="$(run "$2" "$3" "$4" "${5:-false}")"
  if [ "$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)" = "block" ]; then
    fail=$((fail+1)); printf '  FAIL %-40s want it allowed, got "%s"\n' "$1" "$out"
  else pass=$((pass+1)); printf '  ok   %-40s [allowed]\n' "$1"; fi
}

eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-40s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-40s want "%s", got "%s"\n' "$1" "$2" "$3"; fi }

R="groundwork:grounded-researcher"
V="groundwork:adversarial-verifier"

echo "agent-contract:"

# --- the researcher must cite or say UNKNOWN ---
d="$ROOT/r"; proj "$d"
blocks "researcher: no source at all"      "$d" "$R" "The provider supports partial refunds and webhooks are retried five times."
allows "researcher: cites a URL"           "$d" "$R" "Supported — see https://docs.example.com/refunds ('partial refunds are supported')."
allows "researcher: marks UNKNOWN"         "$d" "$R" "Retry count: UNKNOWN — the official docs do not state it."
allows "researcher: lowercase unknown"     "$d" "$R" "Retry policy is unknown; no official source states it."
allows "researcher: cites a doc path"      "$d" "$R" "Confirmed in docs/api/refunds.md — the endpoint accepts a partial amount."

# --- the verifier must return a verdict ---
blocks "verifier: no verdict"              "$d" "$V" "The claim looks reasonable and the code seems fine to me."
allows "verifier: CONFIRMED"               "$d" "$V" "CONFIRMED — OrderService.php:88 performs the guard before the transition."
allows "verifier: REFUTED"                 "$d" "$V" "REFUTED — no authorization check exists on the write path."
allows "verifier: UNCERTAIN"               "$d" "$V" "UNCERTAIN — the evidence available does not settle it."

# --- the loop guard: never block the message a block asked for ---
allows "re-entry never blocks"             "$d" "$R" "Still no source here." "true"

# --- agents outside the contract are none of this hook's business ---
allows "other agent type untouched"        "$d" "Explore" "Found three files."
allows "impact-mapper untouched"           "$d" "groundwork:impact-mapper" "Order.php is consumed by six callers."

# --- inert outside a Groundwork project, and behind its toggle ---
d="$ROOT/o1"; mkdir -p "$d"
allows "no .groundwork.json"               "$d" "$R" "No source anywhere."
d="$ROOT/o2"; proj "$d" '{ "gates": { "agent_contract": false } }'
allows "toggle off"                        "$d" "$R" "No source anywhere."
d="$ROOT/o3"; proj "$d" '{ "gates": { "agent_contract": true } }'
blocks "toggle explicitly on"              "$d" "$R" "No source anywhere."

# --- robustness ---
d="$ROOT/x"; proj "$d"
( cd "$d" && printf '%s' 'not json' | bash "$HOOK" >/dev/null 2>&1 ); eq "malformed stdin exits 0" "0" "$?"
( cd "$d" && printf '%s' '{"hook_event_name":"SubagentStop"}' | bash "$HOOK" >/dev/null 2>&1 ); eq "missing fields exit 0" "0" "$?"
allows "empty message"                     "$d" "$R" ""
( cd "$d" && printf '%s' "$(jq -nc '{agent_type:"groundwork:grounded-researcher", last_assistant_message:"no source"}')" | bash "$HOOK" >/dev/null 2>&1 )
eq     "blocking still exits 0"            "0" "$?"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
