#!/usr/bin/env bash
# Groundwork plugin :: executable proof for task-intent.sh (W17-AC1..AC4).
#
# v0.23.0 put "a task described in chat enters through start-task" into the SessionStart context.
# SessionStart fires once; a long session states many tasks, and by the tenth the reminder is far
# behind in context. This hook says it again at the moment a task is actually stated — and, because
# a reminder that repeats is worse than none, exactly once until the mode changes.
# Run: bash hooks/tests/task-intent.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/task-intent.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() { mkdir -p "$1/.claude/groundwork"; printf '%s\n' "${2:-\{ \"runner\": \"host\" \}}" > "$1/.groundwork.json"; }
mode() { mkdir -p "$1/.claude/groundwork"; printf '# Task: x\n- Mode: %s\n' "$2" > "$1/.claude/groundwork/task-state.md"; }

run() { # dir prompt [session]
  local payload
  payload="$(jq -nc --arg p "$2" --arg s "${3:-sess-1}" \
    '{session_id:$s, hook_event_name:"UserPromptSubmit", prompt:$p, permission_mode:"default"}')"
  ( cd "$1" && printf '%s' "$payload" | bash "$HOOK" 2>/dev/null )
}

fires() { # name dir prompt [session]
  local out; out="$(run "$2" "$3" "${4:-sess-1}")"
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext // empty' >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %-42s [fired]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-42s want context, got "%s"\n' "$1" "$out"; fi
}

quiet() { # name dir prompt [session]
  local out; out="$(run "$2" "$3" "${4:-sess-1}")"
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext // empty' >/dev/null 2>&1; then
    fail=$((fail+1)); printf '  FAIL %-42s want silence, got "%s"\n' "$1" "$out"
  else pass=$((pass+1)); printf '  ok   %-42s [quiet]\n' "$1"; fi
}

eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-42s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-42s want "%s", got "%s"\n' "$1" "$2" "$3"; fi }

echo "task-intent:"

# --- a task stated in prose, in either language, with no mode set ---
d="$ROOT/t1"; proj "$d"
fires "ru: сделай отчёт по заказам"  "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром по станции"
d="$ROOT/t2"; proj "$d"
fires "ru: нужно чтобы..."           "$d" "Нужно чтобы менеджер видел суммы только по своим заказам, а не по всем"
d="$ROOT/t3"; proj "$d"
fires "en: add an endpoint"          "$d" "Add an endpoint that returns the vendor balance for a given month"
d="$ROOT/t4"; proj "$d"
fires "ru: почини баг"               "$d" "Почини баг с датой вылета — она сдвигается на день при экспорте"

# --- but never twice in the same session while the mode has not moved ---
d="$ROOT/t5"; proj "$d"
fires "first statement fires"        "$d" "Добавь фильтр по станции в отчёт по заказам" "sess-A"
quiet "second statement is silent"   "$d" "Добавь ещё и фильтр по дате в тот же отчёт"  "sess-A"

# --- a mode means the protocol is already engaged; and it resets the reminder ---
d="$ROOT/t6"; proj "$d"; mode "$d" "Implementation"
quiet "mode set: stays out of the way" "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром"
d="$ROOT/t7"; proj "$d"
fires "fires before a mode exists"   "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром" "sess-B"
mode "$d" "Discovery"
quiet "goes quiet once mode appears" "$d" "И ещё добавь туда фильтр по станции"                "sess-B"

# --- things that are not a task statement ---
d="$ROOT/q"; proj "$d"
quiet "a question"                   "$d" "Что такое hide_financial в этом проекте и где он используется?"
quiet "a short reply"                "$d" "да, давай"
quiet "an explicit slash command"    "$d" "/groundwork:start-task добавь фильтр по станции в отчёт"
quiet "thanks"                       "$d" "спасибо, всё работает"
quiet "a status question"            "$d" "What is the current state of the branch?"

# --- inert outside a Groundwork project, and behind its toggle ---
d="$ROOT/o1"; mkdir -p "$d"
quiet "no .groundwork.json"          "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром"
d="$ROOT/o2"; proj "$d" '{ "gates": { "task_intent": false } }'
quiet "toggle off"                   "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром"
d="$ROOT/o3"; proj "$d" '{ "gates": { "task_intent": true } }'
fires "toggle explicitly on"         "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром"

# --- never blocks, never breaks ---
d="$ROOT/x"; proj "$d"
( cd "$d" && printf '%s' 'not json' | bash "$HOOK" >/dev/null 2>&1 ); eq "malformed stdin exits 0" "0" "$?"
( cd "$d" && printf '%s' '{"hook_event_name":"UserPromptSubmit"}' | bash "$HOOK" >/dev/null 2>&1 ); eq "missing prompt exits 0" "0" "$?"
out="$(run "$d" "Сделай отчёт по заказам за прошлый месяц с фильтром" "sess-Z")"
eq "never returns a block" "" "$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
