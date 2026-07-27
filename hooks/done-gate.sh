#!/usr/bin/env bash
# RaDevs plugin :: Stop hook.
# Block "done" if static analysis fails on changed PHP. Fires only when PHP changed;
# never blocks on environment problems (Sail down, not a git repo, etc.).
set -uo pipefail

# Shared resolvers (runner-aware commands). Fail-safe: without the library the Sail
# defaults below are exactly the pre-library behavior.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_cmd          >/dev/null 2>&1 || gw_cmd() { printf './vendor/bin/sail %s %s' "$1" "${2:-}"; }
command -v gw_runner_ready >/dev/null 2>&1 || gw_runner_ready() { [ -x ./vendor/bin/sail ]; }

# Resolve gate command + opt-out from .groundwork.json (runner-aware; Sail by default).
cmd="$(gw_cmd composer analyse)"; overridden=0
if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.analyse_on_stop' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
  override="$(jq -r '.commands.analyse // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && { cmd="$override"; overridden=1; }
fi

# Only act when PHP actually changed since the last commit.
# `-uall` is required: without it a brand-new directory is reported as the directory itself
# ("?? app/Services/"), hiding every PHP file in it and silently skipping the gate.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed="$(git status --porcelain -uall 2>/dev/null | grep -E '\.php"?$' || true)"
[ -z "$changed" ] && exit 0

# If the gate relies on Sail and it is unavailable, do not block (env issue).
# An explicit `commands.analyse` override wins: only its own Sail dependency is checked.
if [ "$overridden" = "1" ]; then
  case "$cmd" in *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;; esac
else
  gw_runner_ready || exit 0
fi

# Run the gate. Pass -> allow stop. Fail -> block (exit 2) and feed errors back to the agent.
# shellcheck disable=SC2086
out="$($cmd 2>&1)"; status=$?
if [ "$status" -ne 0 ]; then
  # A missing binary / undefined composer script / container down is an environment problem, not a
  # static-analysis failure — this gate must never block on one (openapi-gate's allow-list).
  case "$out" in
    *"is not defined"*|*"Could not open input file"*|*"command not found"*|*"No such file or directory"*|*"Cannot connect"*|*"No such container"*)
      echo "groundwork done-gate: the analysis command could not run (environment) — analysis skipped, not a failure." >&2
      exit 0 ;;
  esac
  {
    echo "groundwork done-gate: static analysis FAILED on changed PHP — not done yet. Fix before finishing."
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi
exit 0
