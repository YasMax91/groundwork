#!/usr/bin/env bash
# RaDevs plugin :: PreCompact hook.
# Context is about to be compacted (transcript thinned). Drop a breadcrumb into the
# task checkpoint so that after compaction — when SessionStart re-injects this file —
# the agent treats the checkpoint as the source of truth instead of a thinned
# transcript. Side-effect only; never blocks compaction.
set -uo pipefail

[ -f .groundwork.json ] || exit 0
[ "$(jq -r '.memory.checkpoint' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

state=".claude/groundwork/task-state.md"
[ -f "$state" ] || exit 0

input="$(cat 2>/dev/null || true)"
trigger="$(printf '%s' "$input" | jq -r '.trigger // .matcher // .custom_instructions // "auto"' 2>/dev/null || echo auto)"

# Avoid unbounded growth: only add the marker if it is not already the last line.
if [ "$(tail -1 "$state" 2>/dev/null || true)" != "> ⟳ context compacted (${trigger}) — checkpoint above is the source of truth." ]; then
  printf '\n> ⟳ context compacted (%s) — checkpoint above is the source of truth.\n' "$trigger" >> "$state"
fi
exit 0
