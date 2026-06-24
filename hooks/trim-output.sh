#!/usr/bin/env bash
# RaDevs plugin :: PostToolUse(Bash) hook — optional, fail-safe output trimmer.
# Collapses the passing-test / clean-analysis spam from known-noisy project commands to
# save context, WITHOUT ever hiding a failure.
#
# OFF by default: it rewrites what the agent sees (`updatedToolOutput`), and the plugin's
# rule is no false-greens. Enable per project with `.groundwork.json` gates.trim_tool_output
# = true, but verify the payload field in your environment first — the PostToolUse tool-output
# field name is not fully documented. Capture it once with `claude --debug` (inspect the
# PostToolUse stdin) before trusting this in a real workflow.
#
# Fail-safe guarantees:
#   * does nothing unless gates.trim_tool_output == true (explicit opt-in);
#   * does nothing unless it can POSITIVELY locate the tool output (unknown field -> no change);
#   * NEVER trims when any failure indicator is present — the full output passes through;
#   * only ever keeps the tail (where runners print the summary) plus a visible marker.
set -uo pipefail

[ -f .groundwork.json ] || exit 0
[ "$(jq -r '.gates.trim_tool_output' .groundwork.json 2>/dev/null)" = "true" ] || exit 0

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$cmd" ] || exit 0

# Only act on known-noisy, high-volume project commands.
case "$cmd" in
  *"artisan test"*|*"pest"*|*"phpunit"*|*"composer analyse"*|*"pint"*|*"route:list"*) ;;
  *) exit 0 ;;
esac

# Locate the tool output across candidate field names (schema not fully documented).
out="$(printf '%s' "$input" | jq -r '
  ( .tool_response // .tool_output // .tool_result // empty ) as $r
  | if   ($r | type) == "string" then $r
    elif ($r | type) == "object" then ( $r.stdout // $r.output // $r.stderr // ($r | tostring) )
    else empty end' 2>/dev/null || true)"
[ -n "$out" ] || exit 0   # fail-safe: cannot find the output -> change nothing

# NEVER trim if anything looks like a failure — pass the full output through untouched.
if printf '%s' "$out" | grep -qiE 'fail|error|exception|not ok|\[ERR|was not|expected|incorrect|risky|warning'; then
  exit 0
fi
# Require a positive success signal too, or leave it alone (avoid trimming unrelated noise).
if ! printf '%s' "$out" | grep -qiE 'pass|no errors|tests:|ok\b|done|nothing to'; then
  exit 0
fi

lines="$(printf '%s\n' "$out" | grep -c . || true)"
[ "${lines:-0}" -lt 25 ] && exit 0   # small outputs aren't worth trimming

tail_out="$(printf '%s\n' "$out" | tail -15)"
new="[groundwork: passing output trimmed — ${lines} lines collapsed; rerun the command for full detail]
${tail_out}"

jq -nc --arg o "$new" '{hookSpecificOutput:{hookEventName:"PostToolUse",updatedToolOutput:$o}}' 2>/dev/null || true
exit 0
