#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/in-cwd.sh (wave 36).
# Reproduces the otaje defect: a session opened in the main checkout works in a worktree; the main
# checkout's checkpoint is another task in Discovery mode; the gate must judge the worktree.
# Run: bash hooks/tests/in-cwd.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-46s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-46s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }

M="$ROOT/main"; mkdir -p "$M/app"
( cd "$M" && git init -q && git config user.email t@t && git config user.name t
  printf '{ "runner": "host", "gates": { "lock_edits_in_discovery": true } }\n' > .groundwork.json
  printf '<?php\n' > app/A.php; git add -A; git commit -qm init
  git worktree add -q "$M/wt" -b lane )
checkpoint() { mkdir -p "$1/.claude/groundwork"; printf '# Task: %s\n- Mode: %s\n' "$2" "$3" > "$1/.claude/groundwork/task-state.md"; }
checkpoint "$M" "someone else's task" Discovery
checkpoint "$M/wt" "this lane's task" Implementation

decision() { # start-dir hook payload-cwd -> deny | allow
  local out
  out="$(jq -nc --arg c "$3" --arg f "$3/app/A.php" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"Edit", tool_input:{file_path:$f}}' \
    | ( cd "$1" && bash "$HOOKS/in-cwd.sh" "$2" 2>&1 ))"
  if printf '%s' "$out" | grep -qiE 'deny|Discovery mode'; then echo deny; else echo allow; fi
}
direct() { # start-dir hook payload-cwd -> the old behaviour, no wrapper
  local out
  out="$(jq -nc --arg c "$3" --arg f "$3/app/A.php" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"Edit", tool_input:{file_path:$f}}' \
    | ( cd "$1" && bash "$HOOKS/$2" 2>&1 ))"
  if printf '%s' "$out" | grep -qiE 'deny|Discovery mode'; then echo deny; else echo allow; fi
}

echo "in-cwd:"
eq "without the wrapper: main checkpoint wins"  deny  "$(direct "$M" pre-tool-guard.sh "$M/wt")"
eq "with the wrapper: the worktree is judged"   allow "$(decision "$M" pre-tool-guard.sh "$M/wt")"
eq "with the wrapper: main still guards main"   deny  "$(decision "$M" pre-tool-guard.sh "$M")"

# payload passes through intact: the hook still reads its stdin
out="$(printf '{"cwd":"%s","hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"x"}' "$M/wt" | ( cd "$M" && bash "$HOOKS/in-cwd.sh" coverage-claim.sh ); echo "rc=$?")"
eq "payload reaches the hook (re-entry silent)" "rc=0" "$out"

# fail-safe: no cwd, missing dir, unknown hook
out="$(printf '{}' | ( cd "$M/wt" && bash "$HOOKS/in-cwd.sh" pre-tool-guard.sh ); echo "rc=$?")"
eq "no cwd in payload: runs where started"      "rc=0" "$out"
out="$(printf '{"cwd":"/no/such/dir"}' | ( cd "$M/wt" && bash "$HOOKS/in-cwd.sh" pre-tool-guard.sh ); echo "rc=$?")"
eq "missing cwd dir: runs where started"        "rc=0" "$out"
out="$(printf '{}' | bash "$HOOKS/in-cwd.sh" no-such-hook.sh; echo "rc=$?")"
eq "unknown hook: silent allow"                 "rc=0" "$out"

# every hook in hooks.json goes through the wrapper
n_all="$(jq '[.hooks[][].hooks[]] | length' "$HOOKS/hooks.json")"
n_wrapped="$(jq '[.hooks[][].hooks[] | select(.command | test("in-cwd.sh"))] | length' "$HOOKS/hooks.json")"
eq "every hooks.json command is wrapped"        "$n_all" "$n_wrapped"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
