#!/usr/bin/env bash
# Groundwork plugin :: UserPromptSubmit hook — the protocol engages on the task, not on session start.
#
# v0.23.0 put "a task described in chat enters through start-task, no command needed" into the
# SessionStart context, because the author states tasks as prose. SessionStart fires once: in a long
# session the tenth task is stated far behind that line in context. This says it again at the moment
# a task is actually stated.
#
# Never blocks. Fires at most once while the checkpoint has no mode — a reminder that repeats is
# noise, and the mode appearing is the signal that it worked.
set -uo pipefail

# Shared resolvers; fail-safe, exactly like the gates.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_mode >/dev/null 2>&1 || gw_mode() { return 0; }

# Verbs that state work to be done, in both languages the author writes in.
GW_TASK_VERBS_RU='[Сс]делай|[Дд]обавь|[Пп]очини|[Ии]справь|[Пп]ерепиши|[Рр]еализуй|[Дд]оработай|[Уу]бери|[Пп]еренеси|[Сс]оздай|[Нн]апиши|[Пп]оменяй|[Ии]змени|[Нн]ужно чтобы|[Нн]адо чтобы|[Дд]авай сделаем'
GW_TASK_VERBS_EN='\badd\b|\bfix\b|\bimplement\b|\bcreate\b|\brefactor\b|\bremove\b|\bmigrate\b|\bchange\b|\bbuild\b|\bmake\b'
# An opening that means a question about the codebase, not an instruction to change it.
GW_QUESTION_OPENERS='^[[:space:]]*([Чч]то|[Кк]ак|[Пп]очему|[Зз]ачем|[Кк]акой|[Кк]акие|[Гг]де|[Кк]огда|[Мм]ожно ли|what|how|why|where|when|which|is |are |does |did |can i)'

[ -f .groundwork.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ "$(jq -r '.gates.task_intent' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null || true)"
session="$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null || printf 'unknown')"
[ -n "$prompt" ] || exit 0

marker=".claude/groundwork/.task-intent-fired"

# A mode means the protocol is already engaged. Nothing to say — and the reminder resets, so the next
# task stated after this one gets it again.
if [ -n "$(gw_mode 2>/dev/null || true)" ]; then
  rm -f "$marker" 2>/dev/null || true
  exit 0
fi

# An explicit command is the user driving the protocol himself.
case "$prompt" in /*) exit 0 ;; esac

# Word count rather than character count: the prompt is bilingual and `${#var}` counts bytes, which
# would put a three-word Russian thank-you over any byte threshold.
[ "$(printf '%s' "$prompt" | wc -w | tr -d ' ')" -ge 5 ] 2>/dev/null || exit 0

# A question about the code is not a task statement.
printf '%s' "$prompt" | grep -qiE "$GW_QUESTION_OPENERS" && exit 0

# Does it state work to be done?
printf '%s' "$prompt" | grep -qE "$GW_TASK_VERBS_RU" || printf '%s' "$prompt" | grep -qiE "$GW_TASK_VERBS_EN" || exit 0

# Once per session while the mode is still unset: if the first reminder did not land, repeating it
# every prompt only trains the reader to ignore it.
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$session" ] && exit 0
{ mkdir -p "$(dirname "$marker")" 2>/dev/null || true; printf '%s' "$session" > "$marker"; } 2>/dev/null || true

jq -nc '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("groundwork: this reads like a task statement and the checkpoint has no mode set. "
      + "Per the AI-SDD process a task described in chat enters through the start-task flow with no command from the user: "
      + "classify the level, map the blast radius, run the interview at the level'"'"'s calibration (money, permissions, "
      + "client-visible behaviour and external integrations each carry a round of their own from L2 up), show the cost of "
      + "silence, and get the plan approved before any production edit. If this is L0/L1, say so and proceed — the process "
      + "scales down, it does not switch off.")
  }
}' 2>/dev/null || true

exit 0
