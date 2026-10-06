#!/usr/bin/env bash
# Groundwork plugin :: run a hook in the SESSION's directory, not the directory the session started in.
#
#   in-cwd.sh <hook file> — reads the hook payload from stdin, cd's into its `cwd`, and hands the same
#   payload to the hook on stdin.
#
# Every gate resolves `.groundwork.json` and `.claude/groundwork/…` relative to its working directory. The
# harness starts hook processes in the directory the session was opened in; a session opened in the main
# checkout that then works in a worktree therefore had every gate read the MAIN checkout — another task's
# checkpoint (pre-tool-guard refusing edits «in Discovery mode»), another tree's diff (OpenAPI and handoff
# gates blocking on files the session never touched), another tree's suite. The payload's `cwd` is where the
# session actually is (wave 36). Fail-safe: no payload, no `cwd`, or a `cwd` that is not a directory → the
# hook runs where it was started, exactly as before.
set -uo pipefail

hook="${1:-}"
dir="$(cd "$(dirname "$0")" && pwd)"
[ -n "$hook" ] && [ -f "$dir/$hook" ] || exit 0

payload="$(cat 2>/dev/null || true)"
cwd=""
if [ -n "$payload" ]; then
  if command -v jq >/dev/null 2>&1; then
    cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
  else
    cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd") or "")' 2>/dev/null || true)"
  fi
fi
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"

case "$hook" in
  *.py) printf '%s' "$payload" | python3 "$dir/$hook" ;;
  *)    printf '%s' "$payload" | bash "$dir/$hook" ;;
esac
