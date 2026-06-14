#!/usr/bin/env bash
# RaDevs plugin :: Stop hook.
# Block "done" if static analysis fails on changed PHP. Fires only when PHP changed;
# never blocks on environment problems (Sail down, not a git repo, etc.).
set -uo pipefail

# Resolve gate command + opt-out from .groundwork.json (defaults to Sail + composer analyse).
cmd='./vendor/bin/sail composer analyse'
if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.analyse_on_stop // true' .groundwork.json 2>/dev/null || echo true)" = "false" ] && exit 0
  override="$(jq -r '.commands.analyse // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && cmd="$override"
fi

# Only act when PHP actually changed since the last commit.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed="$(git status --porcelain 2>/dev/null | grep -E '\.php"?$' || true)"
[ -z "$changed" ] && exit 0

# If the gate relies on Sail and it is unavailable, do not block (env issue).
case "$cmd" in
  *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;;
esac

# Run the gate. Pass -> allow stop. Fail -> block (exit 2) and feed errors back to the agent.
# shellcheck disable=SC2086
out="$($cmd 2>&1)"; status=$?
if [ "$status" -ne 0 ]; then
  {
    echo "groundwork done-gate: static analysis FAILED on changed PHP — not done yet. Fix before finishing."
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi
exit 0
