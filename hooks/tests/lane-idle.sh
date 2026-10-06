#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/lane-idle.py (wave 36). Docker is a stub that logs.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-44s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-44s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }
mkdir -p "$ROOT/bin"; printf '#!/bin/sh\necho "$@" >> "%s/docker.log"\n' "$ROOT" > "$ROOT/bin/docker"; chmod +x "$ROOT/bin/docker"
M="$ROOT/shop"; mkdir -p "$M"
( cd "$M" && git init -q && git config user.email t@t && git config user.name t && printf '{}\n' > .groundwork.json \
  && git add -A && git commit -qm init && git worktree add -q "$M/wt" -b lane )
printf 'COMPOSE_PROJECT_NAME=shop\n' > "$M/.env"
mkdir -p "$M/wt/.claude"; printf '{"compose_project":"shop_wt"}\n' > "$M/wt/.claude/lane.json"
end() { : > "$ROOT/docker.log"; jq -nc --arg c "$1" '{session_id:"s-end", cwd:$c, hook_event_name:"SessionEnd"}' \
  | PATH="$ROOT/bin:$PATH" python3 "$HOOKS/lane-idle.py"; sleep 1; cat "$ROOT/docker.log" | tr -d '\n'; }
echo "lane-idle:"
eq "last session closes: lane stopped"      "compose -p shop_wt stop" "$(end "$M/wt")"
REG="$M/.git/follow-through/sessions"; mkdir -p "$REG"
printf '{"session_id":"other","cwd":"%s","heartbeat":%s}\n' "$M/wt" "$(date +%s)" > "$REG/other.json"
eq "another live session: lane kept"        ""  "$(end "$M/wt")"
printf '{"session_id":"other","cwd":"%s","heartbeat":%s}\n' "$M/wt" "$(( $(date +%s) - 7200 ))" > "$REG/other.json"
eq "stale sibling entry: lane stopped"      "compose -p shop_wt stop" "$(end "$M/wt")"
printf '{"compose_project":"shop"}\n' > "$M/wt/.claude/lane.json"
eq "lane.json naming main stack: kept"      ""  "$(end "$M/wt")"
printf '{"compose_project":"shop_wt"}\n' > "$M/wt/.claude/lane.json"
printf '{"gates":{"lane_idle_stop":false}}\n' > "$M/wt/.groundwork.json"
eq "opt-out honoured"                       ""  "$(end "$M/wt")"
eq "main checkout (no lane.json): nothing"  ""  "$(end "$M")"
echo; echo "  passed: $pass, failed: $fail"; [ "$fail" -eq 0 ]
