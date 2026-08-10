#!/usr/bin/env bash
# Groundwork plugin :: SessionStart hook.
# Cheaply re-inject project state at session start / resume / post-compact so the
# agent does not re-read the same files every time. Emits `additionalContext` JSON.
# Silent on non-Groundwork projects and on any error — it must never break a session.
set -uo pipefail

# Shared resolvers (canonical Mode); fail-safe fallback to the raw first word.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_mode >/dev/null 2>&1 || gw_mode() {
  grep -iE '^[[:space:]]*-?[[:space:]]*Mode:' "${1:-.claude/groundwork/task-state.md}" 2>/dev/null \
    | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | awk -F'|' '{print $1}' | awk '{print $1}'
}

# Only act in a Groundwork-initialized project.
[ -f .groundwork.json ] || exit 0
# Respect the opt-out toggle.
[ "$(jq -r '.memory.session_context' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

ctx=""
add() { ctx="${ctx}$1
"; }

# --- runner + DB engine (the contract the agent must honor) ---
runner="$(jq -r '.runner // "sail"' .groundwork.json 2>/dev/null || echo sail)"
engine="$(jq -r '.database.default // "mysql"' .groundwork.json 2>/dev/null || echo mysql)"
add "Groundwork workflow active. Runner: ${runner}. DB engine: ${engine} — code and tests target this engine, never SQLite."
# A task typed as plain prose is still a task: name the entry point, since the user is not
# expected to invoke the skill by hand.
add "A task described in chat enters through the 'start-task' skill — no command needed from the user: classify, map the blast radius, interview for the decisions that are his, then plan. Interview depth is the clarify protocol's calibration, and from L2 up the first round offers the unbounded interview as a choice."

# --- git state ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  dirty="$(git status --porcelain 2>/dev/null | head -20 || true)"
  if [ -n "$dirty" ]; then
    n="$(printf '%s\n' "$dirty" | grep -c . || true)"
    add "Git: on ${branch}, ${n} uncommitted path(s):"
    add "$(printf '%s\n' "$dirty" | sed 's/^/  /')"
  else
    add "Git: on ${branch}, working tree clean."
  fi
fi

# --- active task checkpoint (the working-memory file the skills maintain) ---
state=".claude/groundwork/task-state.md"
if [ -f "$state" ]; then
  # A checkpoint is worth ~1k tokens, so it is injected in full only while the task is actually
  # running. A finished or hand-edited one (`Mode: DONE — committed …`) yields no canonical mode:
  # point at the file instead of paying for it on every session that has nothing to resume.
  case "$(gw_mode "$state")" in
    Discovery|Spec|Plan|Implementation|Review)
      add "Active task checkpoint (${state}) — resume from here; it is the source of truth for task state:"
      add "$(head -45 "$state" | sed 's/^/  /')" ;;
    *)
      add "Checkpoint present but not in an active mode: ${state} — $(head -1 "$state" 2>/dev/null | sed 's/^#[[:space:]]*//'). Read it only if this session continues that task." ;;
  esac
fi

# --- most recent spec (by mtime) ---
spec="$(find docs/specs -type f -name '*.md' 2>/dev/null -exec ls -t {} + 2>/dev/null | head -1 || true)"
[ -n "$spec" ] && add "Most recent spec: ${spec}"

# --- status banner + session title (Wave 5; honor ui.status_messages) ---
title="Groundwork: ${branch:-?}"
banner=""
if [ "$(jq -r '.ui.status_messages' .groundwork.json 2>/dev/null)" != "false" ]; then
  mode_line=""
  if [ -f "$state" ]; then
    # Canonical modes only — a non-canonical value yields nothing, so the banner and the
    # session title fall back to the branch rather than echoing raw Markdown.
    m="$(gw_mode "$state")"
    l="$(grep -iE '^[[:space:]]*-?[[:space:]]*Level:' "$state" 2>/dev/null | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | awk '{print $1}')"
    [ -n "$m" ] && { title="Groundwork: ${m}${l:+ $l}"; mode_line=" · ${m}${l:+ $l}"; }
  fi
  banner="Groundwork · ${branch:-?} · ${engine}${mode_line}"
fi

# Emit the SessionStart output. jq handles escaping. sessionTitle/systemMessage are added
# only when set, and are ignored by CC versions that don't render them (additionalContext
# always works). Per-section caps above keep this cheap on every session.
jq -nc --arg c "$ctx" --arg t "$title" --arg m "$banner" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}
   + (if $t != "" then {sessionTitle:$t} else {} end)
   + (if $m != "" then {systemMessage:$m} else {} end)' 2>/dev/null || true
exit 0
