#!/usr/bin/env bash
# RaDevs plugin :: PostToolUse(Write|Edit) hook.
# Auto-format an edited PHP file via the project's formatter. Best-effort, never blocks.
set -uo pipefail

input="$(cat 2>/dev/null || true)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

# Only PHP files that exist.
case "$file" in
  *.php) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Shared resolvers (runner-aware commands); fail-safe fallback to the Sail defaults.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_cmd          >/dev/null 2>&1 || gw_cmd() { printf './vendor/bin/sail %s' "$1"; }
command -v gw_runner_ready >/dev/null 2>&1 || gw_runner_ready() { [ -x ./vendor/bin/sail ]; }

# Resolve format command + opt-out from .groundwork.json (runner-aware; Sail + Pint by default).
cmd="$(gw_cmd pint)"; overridden=0
if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.format_on_edit' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
  override="$(jq -r '.commands.format // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && { cmd="$override"; overridden=1; }
fi

# If the command relies on Sail and it is unavailable, skip quietly (env issue, not a failure).
# An explicit `commands.format` override wins: only its own Sail dependency is checked.
if [ "$overridden" = "1" ]; then
  case "$cmd" in *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;; esac
else
  gw_runner_ready || exit 0
fi

# Format the single file; swallow all errors so the hook never blocks editing.
# shellcheck disable=SC2086
$cmd "$file" >/dev/null 2>&1 || true
exit 0
