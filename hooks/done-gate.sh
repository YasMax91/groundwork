#!/usr/bin/env bash
# Groundwork plugin :: Stop hook.
# Block "done" if static analysis fails on changed PHP. Fires only when PHP changed;
# never blocks on environment problems (Sail down, not a git repo, etc.).
set -uo pipefail

# Shared resolvers (runner-aware commands). Fail-safe: without the library the Sail
# defaults below are exactly the pre-library behavior.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_cmd          >/dev/null 2>&1 || gw_cmd() { printf './vendor/bin/sail %s %s' "$1" "${2:-}"; }
command -v gw_runner_ready >/dev/null 2>&1 || gw_runner_ready() { [ -x ./vendor/bin/sail ]; }

# Only act in a Groundwork-initialized project — elsewhere the plugin is inert, and now that a skip
# is a visible notice, staying silent here matters.
[ -f .groundwork.json ] || exit 0

# Committing must not disarm the gate. The plugin's own flow ends in a commit, so the last Stop of a
# task would otherwise run against an empty working tree and verify nothing at all. Unpushed commits
# still count as "work in progress"; once pushed, the gate lets go.
gw_changed_paths() {
  local wt up committed=""
  wt="$(git status --porcelain -uall 2>/dev/null | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//' || true)"
  if [ "$(jq -r '.gates.check_unpushed' .groundwork.json 2>/dev/null)" != "false" ]; then
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    [ -n "$up" ] && committed="$(git diff --name-only "$up..HEAD" 2>/dev/null || true)"
  fi
  printf '%s\n%s\n' "$wt" "$committed" | grep -v '^$' | sort -u
}

# Resolve gate command + override from .groundwork.json (runner-aware; Sail by default).
cmd="$(gw_cmd composer analyse)"; overridden=0
if [ -f .groundwork.json ]; then
  override="$(jq -r '.commands.analyse // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && { cmd="$override"; overridden=1; }
fi

# Only act when PHP actually changed since the last commit.
# `-uall` is required: without it a brand-new directory is reported as the directory itself
# ("?? app/Services/"), hiding every PHP file in it and silently skipping the gate.
# This check now precedes the opt-out so that a disabled gate stays completely silent on a change
# that has no PHP in it at all.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed="$(gw_changed_paths | grep -E '\.php$' || true)"
[ -z "$changed" ] && exit 0

# Opt-out, and the reason for it. Turning the gate off is a legitimate project decision; leaving the
# Definition of Done promising a static-analysis step nobody runs is not. So the opt-out is silent
# only when the project stated why — otherwise changed PHP went unanalysed and that is reported.
if [ "$(jq -r '.gates.analyse_on_stop' .groundwork.json 2>/dev/null)" = "false" ]; then
  [ -n "$(jq -r '.gates.analyse_skip_reason // empty' .groundwork.json 2>/dev/null || true)" ] && exit 0
  echo "groundwork done-gate: static analysis is off (gates.analyse_on_stop=false) and no reason is recorded — changed PHP was NOT analysed. Configure an analyser (the init skill offers Larastan) or record gates.analyse_skip_reason." >&2
  exit 1
fi

# A declared no-op is not a pass. `echo '...'`, `true` and `:` all exit 0, so a project that wrote one
# into commands.analyse to silence the gate was being told its static analysis ran clean.
case "$(printf '%s' "$cmd" | awk '{print $1}')" in
  echo|true|:|printf)
    echo "groundwork done-gate: commands.analyse is a declared no-op ($cmd) — NOTHING WAS ANALYSED. A no-op cannot report a pass. Configure a real analyser (the init skill offers Larastan), or set gates.analyse_on_stop=false with gates.analyse_skip_reason." >&2
    exit 1 ;;
esac

# If the gate relies on Sail and it is unavailable, do not block (env issue).
# An explicit `commands.analyse` override wins: only its own Sail dependency is checked.
if [ "$overridden" = "1" ]; then
  case "$cmd" in *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;; esac
else
  gw_runner_ready || { echo "groundwork done-gate: runner unavailable — gate NOT run (nothing was verified)." >&2; exit 1; }
fi

# Run the gate. Pass -> allow stop. Fail -> block (exit 2) and feed errors back to the agent.
# shellcheck disable=SC2086
out="$($cmd 2>&1)"; status=$?
if [ "$status" -ne 0 ]; then
  # An environment problem is a command that never RAN. Deciding that by substring is unsafe:
  # "No such file or directory" and "command not found" occur inside perfectly real Laravel failures
  # (Storage, file_get_contents, Process, artisan-command tests), and matching them turned a red suite
  # into a pass. So: exit 127 is conclusive; otherwise the output must carry an environment phrase AND
  # no sign that the tool actually ran and reported results.
  ran_marker='Tests:|PHPUnit|Failures:|assertions|OK \(|FAIL|PASS|\[ERROR\]|\[OK\]|Line +[0-9]|errors?$|No errors|\.php:[0-9]|at [a-zA-Z_/.]+\.php|Provider|Exception|Error$'
  env_phrase='is not defined|Could not open input file|command not found|No such container|Cannot connect|Is the docker daemon running|permission denied while trying to connect'
  if [ "$status" -eq 127 ] || { printf '%s' "$out" | grep -qE "$env_phrase" \
       && ! printf '%s' "$out" | grep -qE "$ran_marker"; }; then
    echo "groundwork done-gate: the analysis command could not run (environment) — analysis skipped, NOTHING WAS VERIFIED." >&2
    exit 1
  fi
  {
    echo "groundwork done-gate: static analysis FAILED on changed PHP — not done yet. Fix before finishing."
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi

exit 0
