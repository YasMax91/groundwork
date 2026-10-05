#!/usr/bin/env bash
# Groundwork plugin :: executable proof for plain-language.sh (W33-AC6..AC10).
#
# The gate reads text meant for a person, so its whole surface is wording. Four things must hold or
# it is worse than nothing: it corrects the model after a question and warns the user at Stop, it
# stays silent on the project's own vocabulary, it is inert outside a Groundwork project, and it
# never refuses anything.
# Run: bash hooks/tests/plain-language.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/plain-language.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() { # dir [body]
  mkdir -p "$1/.claude/groundwork"
  printf '%s\n' "${2:-\{ \"database\": { \"default\": \"mysql\" } \}}" > "$1/.groundwork.json"
}

ask_payload() { # question-text -> a PostToolUse payload carrying it in every field the reader sees
  jq -nc --arg t "$1" '{
    session_id:"t-1", hook_event_name:"PostToolUse", tool_name:"AskUserQuestion",
    tool_input:{questions:[{question:$t, header:"Выбор", options:[
      {label:"Первый", description:$t}, {label:"Второй", description:"второй вариант"}]}]}
  }'
}

stop_payload() { # message [stop_hook_active]
  jq -nc --arg m "$1" --argjson a "${2:-false}" \
    '{session_id:"t-1", hook_event_name:"Stop", stop_hook_active:$a, last_assistant_message:$m}'
}

run() { ( cd "$1" && printf '%s' "$2" | bash "$HOOK" 2>/dev/null ); }

corrects() { # name dir payload — expects additionalContext back to the model
  local out; out="$(run "$2" "$3")"
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext // empty' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %-40s [corrected]\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %-40s want additionalContext, got "%s"\n' "$1" "$out"
  fi
}

warns() { # name dir payload — expects a systemMessage to the user
  local out; out="$(run "$2" "$3")"
  if printf '%s' "$out" | jq -e '.decision == "block" and (.reason // "") != ""' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %-40s [blocked]\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %-40s want a block decision, got "%s"\n' "$1" "$out"
  fi
}

silent() { # name dir payload — expects no output at all
  local out; out="$(run "$2" "$3")"
  if [ -z "$out" ]; then
    pass=$((pass+1)); printf '  ok   %-40s [silent]\n' "$1"
  else
    fail=$((fail+1)); printf '  FAIL %-40s want silence, got "%s"\n' "$1" "$out"
  fi
}

exits_zero() { # name dir payload
  ( cd "$2" && printf '%s' "$3" | bash "$HOOK" >/dev/null 2>&1 ); local c=$?
  if [ "$c" -eq 0 ]; then pass=$((pass+1)); printf '  ok   %-40s [exit 0]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-40s want exit 0, got %s\n' "$1" "$c"; fi
}

never_refuses() { # name dir payload — no blocking field may appear on any path
  local out; out="$(run "$2" "$3")"
  if printf '%s' "$out" | jq -e '(.decision // empty), (.hookSpecificOutput.permissionDecision // empty)' >/dev/null 2>&1; then
    fail=$((fail+1)); printf '  FAIL %-40s a blocking field appeared: "%s"\n' "$1" "$out"
  else
    pass=$((pass+1)); printf '  ok   %-40s [no blocking field]\n' "$1"
  fi
}

# A long, clean report: no internal term, and it closes on the ask line.
CLEAN_LONG="Экспорт заказов готов. Клиент нажимает «Выгрузить», файл приходит на почту в течение минуты, потому что сборка ушла в фоновую очередь (job ExportOrders, очередь reports). Проверил на 50 тысячах строк: раньше запрос отваливался по таймауту на 30 секундах, теперь отдаёт 202 сразу и письмо приходит через 40 секунд. Финансовые колонки скрыты для ролей без доступа к деньгам (hide_financial), это закрыто тестом. Миграций нет, деплой обычный. От тебя — проверить письмо на своём ящике и сказать, годится ли формат."
# The same length, same content, without the closing line.
NO_ASK="${CLEAN_LONG% От тебя*}"

echo "plain-language:"

# --- AC6: the question's own text reaches the model as a correction ---
d="$ROOT/q1"; proj "$d"
corrects "question: blast radius"    "$d" "$(ask_payload 'Стоит ли расширять blast radius на соседние модули?')"
corrects "question: цена молчания"   "$d" "$(ask_payload 'Фиксируем цену молчания по этому решению?')"
corrects "question: level L2"        "$d" "$(ask_payload 'Задача классифицирована как L2 — продолжаем?')"
corrects "question: EARS"            "$d" "$(ask_payload 'Записать критерий в форме EARS?')"
silent   "question: plain wording"   "$d" "$(ask_payload 'Файл приходит на почту или скачивается по ссылке?')"

# --- AC10: the project's own vocabulary is not the plugin's ---
silent "question: domain identifiers" "$d" "$(ask_payload 'Скрывать суммы для ролей без hide_financial на /api/orders (код 2406)?')"
silent "stop: domain identifiers"     "$d" "$(stop_payload "$CLEAN_LONG")"

# --- AC7: the last message, at Stop ---
warns  "stop: internal term"          "$d" "$(stop_payload 'Собрал карту влияния и закрыл слайс. От тебя — одобрить.')"
warns  "stop: red list in English"    "$d" "$(stop_payload 'The red list is written and the first test fails as expected. From you — approve the plan before I build it.')"
warns  "stop: long, no ask line"      "$d" "$(stop_payload "$NO_ASK")"
silent "stop: clean with ask line"    "$d" "$(stop_payload "$CLEAN_LONG")"
silent "stop: short acknowledgement"  "$d" "$(stop_payload 'Готово, тесты зелёные.')"
warns  "stop: ask line but jargon"    "$d" "$(stop_payload 'Acceptance criteria зафиксированы. От тебя — одобрить план.')"

# --- AC8: inert where it must be ---
d2="$ROOT/none"; mkdir -p "$d2"    # no .groundwork.json
silent "inert: not a groundwork project" "$d2" "$(stop_payload 'Слайс закрыт.')"
d3="$ROOT/off"; proj "$d3" '{ "gates": { "plain_language": false } }'
silent "inert: opt-out"              "$d3" "$(stop_payload 'Слайс закрыт.')"
silent "inert: stop re-entry"        "$d"  "$(stop_payload 'Слайс закрыт.' true)"
silent "inert: empty payload"        "$d"  ""
silent "inert: no assistant message" "$d"  "$(jq -nc '{session_id:"t-1", hook_event_name:"Stop", stop_hook_active:false}')"
silent "inert: other tool"           "$d"  "$(jq -nc '{session_id:"t-1", hook_event_name:"PostToolUse", tool_name:"Edit", tool_input:{old_string:"blast radius"}}')"

# --- GW34-AC1: Stop blocks through the JSON verdict (exit 0); a question is never refused ---
exits_zero    "exit 0 on a block"          "$d" "$(stop_payload 'Слайс закрыт.')"
warns         "Stop verdict is a block"    "$d" "$(stop_payload 'Слайс закрыт.')"
never_refuses "no blocking field on a question" "$d" "$(ask_payload 'Задача L3 — продолжаем?')"

# --- the log is the evidence for a later wave ---
if [ -s "$d/.claude/groundwork/plain-language.log" ]; then
  pass=$((pass+1)); printf '  ok   %-40s [%s lines]\n' "log written" "$(wc -l < "$d/.claude/groundwork/plain-language.log" | tr -d ' ')"
else
  fail=$((fail+1)); printf '  FAIL %-40s the log is empty\n' "log written"
fi

printf '\n  %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
