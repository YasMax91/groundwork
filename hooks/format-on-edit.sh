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

# Resolve format command + opt-out from .groundwork.json (defaults to Sail + Pint).
cmd='./vendor/bin/sail pint'
if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.format_on_edit' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
  override="$(jq -r '.commands.format // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && cmd="$override"
fi

# If the command relies on Sail and it is unavailable, skip quietly (env issue, not a failure).
case "$cmd" in
  *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;;
esac

# Format the single file; swallow all errors so the hook never blocks editing.
# shellcheck disable=SC2086
$cmd "$file" >/dev/null 2>&1 || true
exit 0
