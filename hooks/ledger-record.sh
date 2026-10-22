#!/usr/bin/env bash
# Groundwork plugin :: Stop hook — record what the task took, once, when the checkpoint says it shipped.
#
# Wave 18 built the measurement; writing the row depended on the agent remembering a command in
# skills/final-check/SKILL.md — the exact shape of rule this plugin exists to move into the engine.
# Its own dedup key is the task (slug + `Started:`), so firing on every Stop costs one grep.
#
# The stopping session's own transcript goes with it (wave 40): a session opened in another folder files it
# there, out of reach of the project's transcript directories. in-cwd.sh --each-repo runs this in every
# repository the session changed, so a task done from outside its project is recorded in that project.
#
# Never blocks and never speaks on the happy path: a lost measurement must cost a number, never a turn.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -x "$DIR/estimate-ledger.sh" ] || exit 0
payload="$(cat 2>/dev/null || true)"
transcript=''
if [ -n "$payload" ]; then
  if command -v jq >/dev/null 2>&1; then
    transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
  else
    transcript="$(printf '%s' "$payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path") or "")' 2>/dev/null || true)"
  fi
fi
GW_SESSION_TRANSCRIPT="$transcript" bash "$DIR/estimate-ledger.sh" --record-if-done >/dev/null || true
exit 0
