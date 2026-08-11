#!/usr/bin/env bash
# Groundwork plugin :: Stop hook — a verification claim must carry its denominator.
#
# The other four Stop gates check the repository. This one checks what the agent SAID: a claim
# like "I checked it selectively" satisfies the Definition of Done's "state what stayed unverified"
# literally, while telling the reader nothing about whether that was eight of nine or one of nine.
#
# WARN-ONLY in v0.24.0 (W14-AC7). It never blocks and never re-enters the model — a regex over
# natural language will have false positives, and every trigger is logged so the rate can be read
# before a later wave turns blocking on. `additionalContext` is deliberately NOT used: the spike
# in docs/specs/wave-14-coverage-and-silent-decisions.md showed it continues the turn, which is a
# soft block, not a warning.
set -uo pipefail

# --- The four lists this gate is made of. Tune them here; the logic below never changes. ---
#
# Latin and Cyrillic are matched separately on purpose. `grep -i` folds ASCII reliably, but its
# case folding for non-ASCII depends on the locale the hook happens to inherit — so the Cyrillic
# patterns spell their first letters as classes and are matched case-sensitively.

# A hedge about how thoroughly something was checked.
GW_CLAIM_MARKERS_EN='selective(ly)?|spot.?check(ed)?|superficial(ly)?|cursor(y|ily)|should work|probably (fine|works|ok)|briefly (checked|tested|reviewed|verified)|quick look'
GW_CLAIM_MARKERS_RU='[Вв]ыборочн|[Пп]оверхностн|[Бб]егло|[Вв]скользь|[Чч]астично провер|вроде бы работает|[Дд]олжно работать'

# Evidence that the same message already answers "out of how many?" — a fraction, an enumerated
# gap, or the honest third form ("no verification was performed"). Any of these means silence.
GW_CLAIM_DENOM_EN='[0-9]+[[:space:]]*(of|/)[[:space:]]*[0-9]+|not covered|uncovered|stayed unverified|not verified|not run|no verification|out of scope'
GW_CLAIM_DENOM_RU='[0-9]+[[:space:]]*из[[:space:]]*[0-9]+|[Нн]е покрыт|[Нн]епокрыт|осталось непровер|[Нн]е провер|[Пп]роверки не было|[Нн]е прогонял'

# First match of an ASCII pattern (case-insensitive) or a Cyrillic one (case-sensitive).
gw_claim_match() { # pattern_en pattern_ru text
  local m
  m="$(printf '%s' "$3" | grep -oiE "$1" | head -1 || true)"
  [ -n "$m" ] || m="$(printf '%s' "$3" | grep -oE "$2" | head -1 || true)"
  printf '%s' "$m"
}

# Inert outside a Groundwork project, and inert without jq — same contract as every other hook.
[ -f .groundwork.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Opt-out. Absent key means on.
[ "$(jq -r '.gates.coverage_claim' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# The loop guard (W14-AC6). Present and true means this Stop is a re-entry after a continuation;
# warning again would fire on the very message the previous notice asked for.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || printf 'false')" = "true" ] && exit 0

msg="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
[ -n "$msg" ] || exit 0

marker="$(gw_claim_match "$GW_CLAIM_MARKERS_EN" "$GW_CLAIM_MARKERS_RU" "$msg")"
[ -n "$marker" ] || exit 0

# The marker alone is not the fault — it is often the honest word. The fault is the marker with
# no fraction and no gap list anywhere in the same message.
[ -n "$(gw_claim_match "$GW_CLAIM_DENOM_EN" "$GW_CLAIM_DENOM_RU" "$msg")" ] && exit 0

# Log the trigger. This file is the evidence that decides whether blocking is ever enabled, so a
# failure to write it must never cost the notice.
log=".claude/groundwork/coverage-claims.log"
{
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" \
    "$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')" \
    "$marker" \
    "$(printf '%s' "$msg" | tr '\n\t' '  ' | cut -c1-160)" >> "$log"
} 2>/dev/null || true

jq -nc --arg marker "$marker" '{
  systemMessage: ("groundwork: «" + $marker + "» — a verification claim with no denominator. "
    + "State covered/total against a named set (impact-map consumers, routes, acceptance-criterion IDs, changed files) "
    + "and list what was not covered — or say plainly that no verification was performed. "
    + "Never estimate the fraction. Warning only: nothing is blocked.")
}' 2>/dev/null || true

exit 0
