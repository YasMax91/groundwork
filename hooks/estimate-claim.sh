#!/usr/bin/env bash
# Groundwork plugin :: Stop hook — an estimate in hours must name the slow thing.
#
# Wave 18. The unit rule ("the agent's active minutes, not a developer's day") has existed since
# v0.22.0 and did not change the number, because nothing ever checked what the agent actually said.
# This checks it, against the ledger the same wave introduced.
#
# The fault is never "hours". It is **unexplained hours**: a duration the size of a human work day
# with no slow thing named beside it — no external API to establish, no sandbox probe, no migration
# over a large table, no wait on a person — and no measured median behind it.
#
# WARN-ONLY in v0.28.0 (W18-AC12), for the same reason `coverage-claim` was in v0.24.0: a regex over
# natural language will have false positives, and the log is what decides whether blocking is ever
# turned on. `additionalContext` is deliberately NOT used — it continues the turn, which is a soft
# block rather than a warning.
set -uo pipefail

# --- The four lists this gate is made of. Tune them here; the logic below never changes. ---
#
# Latin and Cyrillic are matched separately on purpose: `grep -i` folds ASCII reliably, but its case
# folding for non-ASCII depends on the locale the hook happens to inherit.

# A duration the size of a human work day, in an estimating shape.
GW_EST_MARKERS_EN='[0-9]+([.,][0-9]+)?[[:space:]]*-?[[:space:]]*([0-9]+([.,][0-9]+)?)?[[:space:]]*(h|hr|hrs|hour|hours)\b|[0-9]+[[:space:]]*(-[[:space:]]*[0-9]+[[:space:]]*)?(day|days|week|weeks)\b|man-(day|hour)|person-(day|hour)|half a day|a full day'
GW_EST_MARKERS_RU='[0-9]+([.,][0-9]+)?[[:space:]]*(-[[:space:]]*[0-9]+[[:space:]]*)?(час|ч\.)|[0-9]+[[:space:]]*(-[[:space:]]*[0-9]+[[:space:]]*)?(дн[яей]|день|недел)|человеко-'

# Evidence in the same message that the number is accounted for: a named slow cause, a separate
# human-time line, a measured median, or a duration reported as an actual rather than a promise.
GW_EST_EXCUSE_EN='external API|third.party|provider|sandbox|probe|official docs|waiting on|wait on|human time|your time|review and accept|large table|backfill|median|n=[0-9]|measured|actually took|it took|elapsed'
GW_EST_EXCUSE_RU='[Вв]нешн|[Пп]ровайдер|[Пп]есочниц|[Оо]фициальн|[Оо]жидани|[Жж]дат|[Тт]во[её] время|[Чч]еловеческое время|[Пп]ринять и проверить|[Бб]ольш(ая|ой) таблиц|медиан|[Ии]змерен|[Пп]о факту|[Зз]аняло|[Фф]актическ'

# First match of an ASCII pattern (case-insensitive) or a Cyrillic one (case-sensitive).
gw_est_match() { # pattern_en pattern_ru text
  local m
  m="$(printf '%s' "$3" | grep -oiE "$1" | head -1 || true)"
  [ -n "$m" ] || m="$(printf '%s' "$3" | grep -oE "$2" | head -1 || true)"
  printf '%s' "$m"
}

# Inert outside a Groundwork project and without jq — same contract as every other hook.
[ -f .groundwork.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Opt-out. Absent key means on. Compared as a string, because jq's `//` treats `false` as absent.
[ "$(jq -r '.gates.estimate_claim' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# The loop guard: this Stop is a re-entry after a continuation, and warning again would fire on the
# very message the previous notice asked for.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || printf 'false')" = "true" ] && exit 0

msg="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
[ -n "$msg" ] || exit 0

marker="$(gw_est_match "$GW_EST_MARKERS_EN" "$GW_EST_MARKERS_RU" "$msg")"
[ -n "$marker" ] || exit 0

# The marker alone is not the fault — an hour with its cause named is a correct estimate.
[ -n "$(gw_est_match "$GW_EST_EXCUSE_EN" "$GW_EST_EXCUSE_RU" "$msg")" ] && exit 0

# The measured answer, so the notice carries a number rather than a scolding. Best-effort: a missing
# ledger costs the median, never the notice.
median="$(bash "$(cd "$(dirname "$0")" 2>/dev/null && pwd)/estimate-ledger.sh" --report 2>/dev/null | sed -n '3p' | sed -E 's/^[[:space:]]+//' || true)"

# Log the trigger. This file is the evidence that decides whether blocking is ever enabled, so a
# failure to write it must never cost the notice.
log=".claude/groundwork/estimate-claims.log"
{
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" \
    "$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')" \
    "$marker" \
    "$(printf '%s' "$msg" | tr '\n\t' '  ' | cut -c1-160)" >> "$log"
} 2>/dev/null || true

jq -nc --arg marker "$marker" --arg median "$median" '{
  systemMessage: ("groundwork: «" + $marker + "» — an estimate the size of a human work day with no slow thing named beside it. "
    + "State the number in the agent'"'"'s active minutes and quote the ledger median with its sample size "
    + "(hooks/estimate-ledger.sh --report), or name what is genuinely slow on the same line — an external API to establish, "
    + "a sandbox probe, a migration over a large table, a wait on a person. Human time is its own line and is never added in."
    + (if $median != "" then "\nMeasured here: " + $median else "" end)
    + "\nWarning only: nothing is blocked.")
}' 2>/dev/null || true

exit 0
