#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/estimate-docs.py (GW34-AC2).
# Run: bash hooks/tests/estimate-docs.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/estimate-docs.py"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() { mkdir -p "$1/docs/ai/client"; printf '{}\n' > "$1/.groundwork.json"; }
# transcript: one user message, then an assistant Write of each given path
transcript() { # dir path...
  local d="$1"; shift
  { jq -nc '{type:"user",message:{role:"user",content:"оцени задачу"}}'
    for p in "$@"; do jq -nc --arg p "$p" '{type:"assistant",message:{content:[{type:"tool_use",name:"Write",input:{file_path:$p}}]}}'; done
  } > "$d/t.jsonl"
}
run() { # dir msg [active]
  local payload
  payload="$(jq -nc --arg c "$1" --arg m "$2" --argjson a "${3:-false}" \
    '{session_id:"t", cwd:$c, stop_hook_active:$a, last_assistant_message:$m, transcript_path:($c+"/t.jsonl")}')"
  ( cd "$1" && printf '%s' "$payload" | python3 "$HOOK" 2>/dev/null )
}
blocks() { # name dir msg [want_substr]
  local out; out="$(run "$2" "$3")"
  if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1 && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -qF -- "$4"; }; then
    pass=$((pass+1)); printf '  ok   %-44s [blocked]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-44s want a block%s, got "%s"\n' "$1" "${4:+ naming $4}" "$out"; fi
}
silent() { # name dir msg [active]
  local out; out="$(run "$2" "$3" "${4:-false}")"
  if [ -z "$out" ]; then pass=$((pass+1)); printf '  ok   %-44s [silent]\n' "$1"
  else fail=$((fail+1)); printf '  FAIL %-44s want silence, got "%s"\n' "$1" "$out"; fi
}

echo "estimate-docs:"

d="$ROOT/a"; proj "$d"; printf '# Оценка\n\nМодуль платежей: 3 человеко-дня.\n' > "$d/docs/ai/client/est.md"
transcript "$d" "$d/docs/ai/client/est.md"
blocks "person-days in a changed doc" "$d" "Готово." "человеко-дня"

d="$ROOT/b"; proj "$d"; printf '# Оценка\n\nКаталог: 5 дней.\n' > "$d/docs/ai/client/est.md"
transcript "$d" "$d/docs/ai/client/est.md"
blocks "days with no wait named" "$d" "Готово." "дней"

d="$ROOT/c"; proj "$d"; printf '# Оценка\n\nОдобрение шаблонов Meta: ожидание 2-3 дня.\nКод: 40 мин.\n' > "$d/docs/ai/client/est.md"
transcript "$d" "$d/docs/ai/client/est.md"
silent "days for a named wait pass" "$d" "Готово."

d="$ROOT/d"; proj "$d"; printf '| Задача | Часы |\n|---|---|\n| A | 2 |\n| B | 3.5 |\n| **Итого** | **7** |\n' > "$d/docs/ai/client/est.md"
transcript "$d" "$d/docs/ai/client/est.md"
blocks "total that does not add up" "$d" "Готово." "add up to 5.5"

d="$ROOT/e"; proj "$d"; printf '| Задача | Часы |\n|---|---|\n| A | 2 |\n| B | 1:30 |\n| Итого | 3:30 |\n' > "$d/docs/ai/client/est.md"
transcript "$d" "$d/docs/ai/client/est.md"
silent "H:MM total that adds up" "$d" "Готово."

d="$ROOT/f"; proj "$d"; printf '# Оценка\n\nМодуль: 3 человеко-дня.\n' > "$d/docs/ai/client/est.md"
transcript "$d"   # the doc exists but was not touched this turn
silent "untouched doc is not scanned" "$d" "Готово."

d="$ROOT/g"; proj "$d"; transcript "$d"
blocks "outbound block with person-hours" "$d" $'Текст:\n\n```outbound CEO\nНа это уйдёт 12 человеко-часов.\n```\nОт тебя: переслать.' "человеко-часов"
silent "re-entry is silent" "$d" $'```outbound CEO\nНа это уйдёт 12 человеко-часов.\n```' true

d="$ROOT/h"; mkdir -p "$d/docs"; printf 'Модуль: 3 человеко-дня.\n' > "$d/docs/x.md"; transcript "$d" "$d/docs/x.md"
silent "inert outside a Groundwork project" "$d" "Готово."

d="$ROOT/i"; proj "$d"; printf '{"gates":{"estimate_claim":false}}\n' > "$d/.groundwork.json"
printf 'Модуль: 3 человеко-дня.\n' > "$d/docs/ai/client/est.md"; transcript "$d" "$d/docs/ai/client/est.md"
silent "opt-out honoured" "$d" "Готово."

out="$(printf 'garbage' | python3 "$HOOK" 2>/dev/null)"; code=$?
if [ -z "$out" ] && [ "$code" -eq 0 ]; then pass=$((pass+1)); printf '  ok   %-44s [silent]\n' "malformed input"
else fail=$((fail+1)); printf '  FAIL %-44s got "%s" (exit %s)\n' "malformed input" "$out" "$code"; fi

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
