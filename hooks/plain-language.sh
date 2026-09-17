#!/usr/bin/env bash
# Groundwork plugin :: the wording gate — the reader must be able to parse what he is asked.
#
# Every other gate checks the repository, or the honesty of a claim. This one checks whether the text
# reaching the owner is in his language: the plugin's own vocabulary kept out of chat, and a closing
# line naming what he is expected to do. The rule is guidelines/plain-language.md; this catches the
# cases where it was forgotten.
#
# Two events, one script:
#   PostToolUse (AskUserQuestion) — the question has already been asked, so nothing is blocked. The
#     correction reaches the model through `additionalContext` and lands on the next round, the plan,
#     and the closing report.
#   Stop — the last assistant message is read the way coverage-claim.sh reads it, and the notice goes
#     to the user through `systemMessage`. `additionalContext` is deliberately NOT used on Stop: the
#     spike in docs/specs/wave-14-coverage-and-silent-decisions.md showed it continues the turn, which
#     is a soft block, not a warning.
#
# WARN-ONLY (v0.42.0, W33-AC9). It never refuses, and every trigger is logged to
# .claude/groundwork/plain-language.log so the rate can be read before a later wave tightens it.
set -uo pipefail

# --- The lists this gate is made of. Tune them here; the logic below never changes. ---
#
# Latin and Cyrillic are matched separately, for the reason coverage-claim.sh gives: `grep -i` folds
# ASCII reliably, while its folding of non-ASCII depends on the locale the hook inherits.

# The plugin's internal vocabulary. The project's own words — a field name, an error code, an
# endpoint, a domain term from AGENTS.md — are deliberately absent: those belong in chat, after the
# meaning (W33-AC10).
GW_PL_TERMS_EN='blast radius|cost of silence|red list|frontier|impact map|EARS|Definition of Done|acceptance criteri[ao]|conformance review|slice ledger|denominator'
# Russian inflects, so each pattern is an invariant stem plus `[^ ]*` — a space is ASCII, which keeps
# the match byte-safe whatever locale the hook inherits.
GW_PL_TERMS_RU='[Рр]адиус[^ ]* поражения|[Цц]ен[^ ]* молчания|[Кк]расн[^ ]* списк[^ ]*|[Кк]арт[^ ]* влияния|[Кк]ритери[^ ]* приёмки|[Фф]ронтир[^ ]*|[Сс]лайс[^ ]*|[Чч]ек-?поинт[^ ]*|[Зз]наменател[^ ]*'
# The task level, which is pure plugin machinery: "Классификация: L2" says nothing to the reader.
GW_PL_LEVEL='(^|[^A-Za-z0-9_])L[0-4]([^A-Za-z0-9_]|$)'

# The closing line that names what the reader does now.
GW_PL_ASK_EN='from you|your call|waiting on you|nothing needed|no action needed|i continue|over to you'
GW_PL_ASK_RU='[Оо]т тебя|[Оо]т вас|[Жж]ду (ответа|решения|одобрения|твоего|вашего)|ничего не нужно|ничего не требуется|работаю дальше|[Тт]воё решение|[Вв]аше решение'

# A short message is an acknowledgement, not a report; the ask line is due on the ones that carry work.
GW_PL_ASK_MIN_CHARS=400

# First match of an ASCII pattern (case-insensitive) or a Cyrillic one (case-sensitive).
gw_pl_match() { # pattern_en pattern_ru text
  local m
  m="$(printf '%s' "$3" | grep -oiE "$1" | head -1 || true)"
  [ -n "$m" ] || m="$(printf '%s' "$3" | grep -oE "$2" | head -1 || true)"
  printf '%s' "$m"
}

# What the term is called when the reader is on the other end (the table in plain-language.md).
gw_pl_spelling() { # term -> chat spelling
  local t; t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    *"blast radius"*|*"impact map"*|*"поражения"*|*"влияния"*) printf 'what else this touches — «что ещё это заденет»' ;;
    *"cost of silence"*|*"молчания"*)                          printf 'what I decided for you — «что я решил за тебя»' ;;
    *"red list"*|*"красн"*)                                    printf 'the tests that must fail first — «тесты, которые должны сначала упасть»' ;;
    *"frontier"*|*"фронтир"*)                                  printf 'the questions that can be answered now — «что уже можно решить»' ;;
    *"acceptance criteri"*|*"критери"*|*"ears"*)               printf 'how we will know it is finished — «как поймём, что готово», written as a sentence' ;;
    *"definition of done"*)                                    printf 'what counts as finished — «когда задача считается сделанной»' ;;
    *"conformance review"*)                                    printf 'a check that what was built matches what we agreed' ;;
    *"slice"*|*"слайс"*)                                       printf 'a step of the work — «шаг работы»' ;;
    *"поинт"*)                                                 printf 'my notes on this task — «мои заметки по задаче»' ;;
    *"denominator"*|*"знаменател"*)                            printf 'the count, spelled out — «5 из 7»' ;;
    l[0-4]*|*" l"[0-4]*)                                                     printf 'how big this is, in words — a typo · an ordinary feature · a risky change' ;;
    *)                                                                       printf 'the reader’s words for it — see the table in guidelines/plain-language.md' ;;
  esac
}

# Inert outside a Groundwork project, and inert without jq — same contract as every other hook.
[ -f .groundwork.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Opt-out. Absent key means on.
[ "$(jq -r '.gates.plain_language' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

event="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null || true)"

# Log the trigger. The file is the evidence that decides whether this ever tightens, so failing to
# write it must never cost the notice.
gw_pl_log() { # event marker text
  local log=".claude/groundwork/plain-language.log"
  {
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" \
      "$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')" \
      "$1" "$2" "$(printf '%s' "$3" | tr '\n\t' '  ' | cut -c1-160)" >> "$log"
  } 2>/dev/null || true
}

case "$event" in
  PostToolUse)
    [ "$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)" = "AskUserQuestion" ] || exit 0

    # Everything the reader actually sees: the question, its chip, and every option.
    text="$(printf '%s' "$payload" | jq -r '
      [ .tool_input.questions[]? | .question // empty, .header // empty,
        ( .options[]? | .label // empty, .description // empty ) ] | join(" ")' 2>/dev/null || true)"
    [ -n "$text" ] || text="$(printf '%s' "$payload" | jq -r '.tool_input | tostring' 2>/dev/null || true)"
    [ -n "$text" ] || exit 0

    marker="$(gw_pl_match "$GW_PL_TERMS_EN" "$GW_PL_TERMS_RU" "$text")"
    [ -n "$marker" ] || marker="$(printf '%s' "$text" | grep -oE "$GW_PL_LEVEL" | head -1 | tr -d ' ' || true)"
    [ -n "$marker" ] || exit 0

    gw_pl_log "question" "$marker" "$text"

    jq -nc --arg marker "$marker" --arg spelling "$(gw_pl_spelling "$marker")" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: ("groundwork plain-language: the question you just asked carries «" + $marker
          + "», which is the plugin’s vocabulary, not the reader’s. In chat it is called: " + $spelling
          + ". Use his words from here on — the next round, the plan, and the closing report — and keep "
          + "the project’s own identifiers (field names, error codes, endpoints) after the meaning, not "
          + "instead of it. Rule: guidelines/plain-language.md. Nothing was blocked.")
      }
    }' 2>/dev/null || true
    exit 0
    ;;

  *)
    # Stop. The loop guard, verbatim from coverage-claim.sh: a re-entry after a continuation would
    # warn about the very message the previous notice asked for.
    [ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || printf 'false')" = "true" ] && exit 0

    msg="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
    [ -n "$msg" ] || exit 0

    marker="$(gw_pl_match "$GW_PL_TERMS_EN" "$GW_PL_TERMS_RU" "$msg")"
    [ -n "$marker" ] || marker="$(printf '%s' "$msg" | grep -oE "$GW_PL_LEVEL" | head -1 | tr -d ' ' || true)"

    ask=""
    if [ "${#msg}" -ge "$GW_PL_ASK_MIN_CHARS" ]; then
      ask="$(gw_pl_match "$GW_PL_ASK_EN" "$GW_PL_ASK_RU" "$msg")"
    fi

    # Silent when the vocabulary is clean and either the ask line is there or the message is short.
    if [ -z "$marker" ]; then
      [ "${#msg}" -lt "$GW_PL_ASK_MIN_CHARS" ] && exit 0
      [ -n "$ask" ] && exit 0
    fi

    if [ -n "$marker" ]; then
      gw_pl_log "message" "$marker" "$msg"
      jq -nc --arg marker "$marker" --arg spelling "$(gw_pl_spelling "$marker")" '{
        systemMessage: ("groundwork: «" + $marker + "» — the plugin’s vocabulary reached the reader. "
          + "In chat it is called: " + $spelling + ". Identifiers from the project itself stay, after "
          + "the meaning. Warning only: nothing is blocked.")
      }' 2>/dev/null || true
      exit 0
    fi

    gw_pl_log "message" "no-ask-line" "$msg"
    jq -nc '{
      systemMessage: ("groundwork: this message ends without saying what the reader does now. "
        + "One last line: answer these questions · approve the plan · run this on your machine · "
        + "nothing, I continue. Warning only: nothing is blocked.")
    }' 2>/dev/null || true
    exit 0
    ;;
esac
