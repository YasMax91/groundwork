#!/usr/bin/env bash
# Groundwork plugin :: status line — one-line workflow state for the bottom bar.
# Wired via the project .claude/settings.json `statusLine` (the `init` skill offers it).
# Claude Code passes session JSON on stdin; we drain it but rely on project files + git.
# Fail-safe: outside a Groundwork project, or when ui.statusline is false, print nothing.
set -uo pipefail

cat >/dev/null 2>&1 || true   # drain stdin (session JSON); we don't depend on it

# Shared resolvers (canonical Mode); fail-safe fallback to the raw first word.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_mode >/dev/null 2>&1 || gw_mode() {
  grep -iE '^[[:space:]]*-?[[:space:]]*Mode:' "${1:-.claude/groundwork/task-state.md}" 2>/dev/null \
    | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | awk -F'|' '{print $1}' | awk '{print $1}'
}

[ -f .groundwork.json ] || exit 0
[ "$(jq -r '.ui.statusline' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

engine="$(jq -r '.database.default // "mysql"' .groundwork.json 2>/dev/null || echo mysql)"

branch='-'; dirty=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
fi

mode='—'; level=''; spec='—'
state=".claude/groundwork/task-state.md"
if [ -f "$state" ]; then
  field() { grep -iE "^[[:space:]]*-?[[:space:]]*$1:" "$state" 2>/dev/null | head -1 | sed -E 's/^[^:]*:[[:space:]]*//'; }
  # Canonical modes only — a hand-edited "**COMMITTED**" renders the neutral placeholder,
  # never raw Markdown in the status bar.
  m="$(gw_mode "$state")"; [ -n "$m" ] && mode="$m"
  l="$(field Level | awk '{print $1}')";                          [ -n "$l" ] && level="$l"
  s="$(field Spec  | sed -E 's#.*/##' | awk '{print $1}')";       [ -n "$s" ] && spec="$s"
fi

out="Groundwork · ${branch}"
[ "${dirty:-0}" != "0" ] && out="${out}*${dirty}"
out="${out} · ${engine} · ${mode}"
[ -n "$level" ] && out="${out} ${level}"
out="${out} · spec:${spec}"
printf '%s\n' "$out"
exit 0
