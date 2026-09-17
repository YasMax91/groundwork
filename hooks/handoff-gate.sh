#!/usr/bin/env bash
# Groundwork plugin :: Stop hook.
# Block "done" when the frontend-facing surface changed and no frontend document changed with it.
#
# The frontend handoff used to be instruction only: a skill said to write it, and nothing checked.
# A task that ended without it left the frontend developer reading a contract that no longer
# matched the backend, and nothing anywhere said so. This gate makes the omission visible at the
# moment it happens, while the change is still in front of the agent.
set -uo pipefail

# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true

[ -f .groundwork.json ] || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# The window this gate judges: the working tree plus every commit since the work was last
# accounted for. Committing must not disarm it — the plugin's own flow ends in a commit, and on a
# local branch with no upstream that would otherwise make the change invisible the moment it lands.
#
# "Last accounted for" is the most recent of: the upstream tip (already pushed and reviewed), the
# last commit that touched the frontend documentation (the previous handoff), and the point this
# branch left the default branch. Taking the most recent keeps the window to work that genuinely
# has no handoff behind it, instead of re-raising the gate over history that was handed off long ago.
gw_window_base() {
  local docs_dir="$1" cand base="" c
  cand=""
  if [ "$(jq -r '.gates.check_unpushed' .groundwork.json 2>/dev/null)" != "false" ]; then
    c="$(git rev-parse '@{u}' 2>/dev/null || true)"; [ -n "$c" ] && cand="$cand $c"
  fi
  c="$(git log -1 --format=%H -- "$docs_dir" 2>/dev/null || true)"; [ -n "$c" ] && cand="$cand $c"
  for b in origin/HEAD main master develop development; do
    c="$(git merge-base HEAD "$b" 2>/dev/null || true)"
    [ -n "$c" ] && [ "$c" != "$(git rev-parse HEAD 2>/dev/null)" ] && { cand="$cand $c"; break; }
  done
  for c in $cand; do
    git merge-base --is-ancestor "$c" HEAD 2>/dev/null || continue
    if [ -z "$base" ] || git merge-base --is-ancestor "$base" "$c" 2>/dev/null; then base="$c"; fi
  done
  printf '%s' "$base"
}

gw_changed_paths() {
  local wt committed="" base
  wt="$(git status --porcelain -uall 2>/dev/null | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//' || true)"
  base="$(gw_window_base "$1")"
  if [ -n "$base" ]; then
    committed="$(git diff --name-only "$base..HEAD" 2>/dev/null || true)"
  else
    # No anchor at all (a fresh repo, one commit, no branches): judge the whole history, because
    # anything else would let the very first frontend-facing commit through unseen.
    committed="$(git log --format= --name-only 2>/dev/null || true)"
  fi
  printf '%s\n%s\n' "$wt" "$committed" | grep -v '^$' | sort -u
}

docs_dir="$(jq -r '.docs.frontend // "docs/ai/frontend"' .groundwork.json 2>/dev/null || true)"
case "$docs_dir" in ""|null) docs_dir="docs/ai/frontend" ;; esac

changed="$(gw_changed_paths "$docs_dir")"
[ -z "$changed" ] && exit 0

# What counts as frontend-facing. Deliberately wide: a miss is silent and reaches the frontend as a
# broken contract, while a false trigger costs one waiver line. `gates.handoff_surface` replaces this
# list for a project shaped differently.
DEFAULT_SURFACE='^routes/.*\.php$|^app/Http/|^app/Enums/|^app/Policies/|^app/Models/|^app/Services/|^database/migrations/'
surface="$(jq -r '.gates.handoff_surface // empty' .groundwork.json 2>/dev/null || true)"
[ -z "$surface" ] && surface="$DEFAULT_SURFACE"

# routes/console.php is scheduling, and the portal's own routes are not a contract the frontend reads.
# `gates.handoff_surface_exclude` carves out what this project's frontend genuinely cannot see — a
# server-rendered admin panel, say, where the storefront is the only API consumer. Carve out only
# what is provably invisible: a model, a resource or a migration behind that panel is still in.
DEFAULT_EXCLUDE='^routes/console\.php$|^routes/docs-portal\.php$'
exclude="$(jq -r '.gates.handoff_surface_exclude // empty' .groundwork.json 2>/dev/null || true)"
[ -n "$exclude" ] && exclude="${DEFAULT_EXCLUDE}|${exclude}" || exclude="$DEFAULT_EXCLUDE"

triggers="$(printf '%s\n' "$changed" | grep -E "$surface" | grep -vE "$exclude" || true)"
[ -z "$triggers" ] && exit 0

# A frontend document changed in the same window → the handoff happened.
if printf '%s\n' "$changed" | grep -q "^${docs_dir}/"; then
  exit 0
fi

# Turning the gate off is a legitimate project decision; leaving the Definition of Done promising a
# handoff nobody writes is not. Silent only when the project stated why.
if [ "$(jq -r '.gates.handoff_on_stop' .groundwork.json 2>/dev/null)" = "false" ]; then
  reason="$(jq -r '.gates.handoff_skip_reason // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$reason" ] && exit 0
  echo "groundwork handoff-gate: the frontend-facing surface changed and the gate is off with no gates.handoff_skip_reason — NO HANDOFF WAS WRITTEN and nothing recorded why." >&2
  exit 1
fi

# A change with genuinely no frontend impact is waived by naming the files it covers. The waiver is
# per-file on purpose: it cannot become a blanket "never ask me again", and the next file outside it
# raises the gate again.
waiver=".claude/groundwork/handoff-waiver"
if [ -f "$waiver" ]; then
  uncovered=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    grep -qxF "$f" "$waiver" || uncovered="${uncovered}${f}"$'\n'
  done <<< "$triggers"
  if [ -z "$uncovered" ]; then
    why="$(grep -m1 '^# reason:' "$waiver" | sed 's/^# reason: *//')"
    echo "groundwork handoff-gate: no handoff — waived for these files${why:+ ($why)}." >&2
    exit 1
  fi
  triggers="$(printf '%s' "$uncovered" | grep -v '^$' || true)"
fi

{
  echo "groundwork handoff-gate: the frontend-facing surface changed and no document under ${docs_dir}/ changed with it — the frontend would be reading a contract that no longer matches this backend."
  echo
  echo "Changed, and visible to the frontend:"
  printf '%s\n' "$triggers" | sed 's/^/  /' | head -25
  n="$(printf '%s\n' "$triggers" | wc -l | tr -d ' ')"
  [ "$n" -gt 25 ] && echo "  … and $((n - 25)) more"
  echo
  echo "Either run /groundwork:frontend-handoff — it writes the delta, updates the reference doc and"
  echo "stamps the front-matter the documentation portal groups by — or, if this change genuinely"
  echo "cannot be seen from the frontend, record that decision instead of leaving it unsaid:"
  echo
  echo "  mkdir -p .claude/groundwork"
  echo "  printf '# reason: <why the frontend cannot see this>\\n%s\\n' \\"
  echo "    \"\$(printf '%s\\n' <the files above>)\" >> .claude/groundwork/handoff-waiver"
  echo
  echo "A waiver covers only the files it names. The next file outside it raises this gate again."
} >&2
exit 2
