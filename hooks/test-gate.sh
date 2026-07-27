#!/usr/bin/env bash
# RaDevs plugin :: Stop hook.
# Block "done" if the test suite fails on changed PHP. Fires only when PHP changed;
# never blocks on environment problems (Sail down, not a git repo, etc.).
set -uo pipefail

# Shared resolvers (runner-aware commands). Fail-safe: without the library the Sail
# defaults below are exactly the pre-library behavior.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_cmd          >/dev/null 2>&1 || gw_cmd() { printf './vendor/bin/sail %s %s' "$1" "${2:-}"; }
command -v gw_runner_ready >/dev/null 2>&1 || gw_runner_ready() { [ -x ./vendor/bin/sail ]; }

# Only act in a RaDevs-initialized project — elsewhere the plugin is inert, and now that a skip
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

# Resolve gate command + opt-out from .groundwork.json (runner-aware; Sail by default).
cmd="$(gw_cmd artisan test)"; overridden=0
if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.test_on_stop' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
  override="$(jq -r '.commands.test // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && { cmd="$override"; overridden=1; }
fi

# Only act when PHP actually changed since the last commit.
# `-uall` is required: without it a brand-new directory is reported as the directory itself
# ("?? app/Services/"), hiding every PHP file in it and silently skipping the gate.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed="$(gw_changed_paths | grep -E '\.php$' || true)"
[ -z "$changed" ] && exit 0

# If the gate relies on Sail and it is unavailable, do not block (env issue).
# An explicit `commands.test` override wins: only its own Sail dependency is checked, never the
# configured runner's — a project may deliberately point the gate somewhere else entirely.
if [ "$overridden" = "1" ]; then
  case "$cmd" in *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;; esac
else
  gw_runner_ready || { echo "groundwork test-gate: runner unavailable — gate NOT run (nothing was verified)." >&2; exit 1; }
fi

# Warn (do not block) when the suite resolves to SQLite while the project targets a real engine.
# A green on SQLite is a false green for engine-specific defects (migrations, FKs, JSON, enum, LIKE).
declared='mysql'
[ -f .groundwork.json ] && declared="$(jq -r '.database.default // "mysql"' .groundwork.json 2>/dev/null || echo mysql)"
if [ "$declared" != "sqlite" ]; then
  for f in phpunit.xml phpunit.xml.dist .env.testing; do
    [ -f "$f" ] || continue
    matches="$(grep -Ei 'value="(sqlite|:memory:)"|^[[:space:]]*DB_CONNECTION[[:space:]]*=[[:space:]]*sqlite' "$f" 2>/dev/null | grep -v '<!--' || true)"
    if [ -n "$matches" ]; then
      echo "groundwork test-gate: WARNING — tests resolve to SQLite (in $f) but this project targets '$declared'. A green on SQLite is a false green for engine-specific defects; run the suite on $declared." >&2
      break
    fi
  done
fi

# --- serialise the suite across parallel sessions sharing one test database ---
# Two sessions interleaving `migrate:fresh` and a running suite produce failures that describe
# neither session's code ("1412 Table definition has changed" -> "1146 doesn't exist"). An atomic
# mkdir is the lock (flock is absent on macOS). Every path here fails OPEN: a busy database is an
# environment problem, and this gate must never invent a red.
lock_dir='.claude/groundwork/locks/test-db'
lock_wait=45      # keep well inside the harness's hook timeout, or the wait is killed before it reports
stale_minutes=30  # deliberately NOT derived from lock_wait: a long suite must not lose its own lock
lock_id="$$"
lock_held=0

release_lock() { # only ever remove OUR lock — never one a still-running session owns
  [ "$lock_held" = "1" ] || return 0
  [ "$(cat "$lock_dir/owner" 2>/dev/null || true)" = "$lock_id" ] || return 0
  rm -rf "$lock_dir" 2>/dev/null || true
}

if [ -f .groundwork.json ] && [ "$(jq -r '.gates.test_db_lock' .groundwork.json 2>/dev/null)" != "false" ]; then
  w="$(jq -r '.gates.test_lock_wait_seconds // empty' .groundwork.json 2>/dev/null || true)"
  case "$w" in ''|*[!0-9]*) ;; *) lock_wait="$w" ;; esac

  mkdir -p "$(dirname "$lock_dir")" 2>/dev/null || true
  waited=0
  while :; do
    if mkdir "$lock_dir" 2>/dev/null; then
      printf '%s\n' "$lock_id" > "$lock_dir/owner" 2>/dev/null || true
      lock_held=1
      trap release_lock EXIT INT TERM
      break
    fi

    # mkdir failed but nothing is there -> we cannot create locks here (permissions, read-only FS).
    # That is an environment problem, not a busy database: proceed unlocked rather than stall.
    if [ ! -d "$lock_dir" ]; then
      echo "groundwork test-gate: could not create the test-DB lock — running unlocked." >&2
      break
    fi

    # Take over a lock left behind by an interrupted session rather than honoring it forever.
    if [ -n "$(find "$lock_dir" -maxdepth 0 -mmin "+$stale_minutes" 2>/dev/null || true)" ]; then
      rm -rf "$lock_dir" 2>/dev/null || true
      # Still there -> we cannot remove it either; do not spin on it.
      if [ -d "$lock_dir" ]; then
        echo "groundwork test-gate: a stale test-DB lock could not be removed — running unlocked." >&2
        break
      fi
      continue
    fi

    if [ "$waited" -ge "$lock_wait" ]; then
      echo "groundwork test-gate: the test database is busy with another session — suite NOT run, NOTHING WAS VERIFIED. Re-run when it frees up." >&2
      exit 1
    fi
    sleep 1; waited=$((waited + 1))
  done
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
    echo "groundwork test-gate: the test command could not run (environment) — suite NOT run, NOTHING WAS VERIFIED." >&2
    exit 1
  fi
  {
    echo "groundwork test-gate: tests FAILED on changed PHP — not done yet (red). Make them green before finishing."
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi

exit 0
