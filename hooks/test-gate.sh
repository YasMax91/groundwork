#!/usr/bin/env bash
# Groundwork plugin :: Stop hook.
# Block "done" if the test suite fails on changed PHP. Fires only when PHP changed;
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

# A suite that resolves to SQLite on a project targeting another engine does not produce a weaker
# green — it produces a false one, for exactly the defects the engine decides (migrations, FKs, JSON,
# enum, LIKE, decimal). Measured on this author's own repositories: three of eleven projects declared
# MySQL and ran their suite on in-memory SQLite, and the warning this used to print had been sitting
# there unread. So it refuses, and the opt-out has to state a reason — the same shape as
# `gates.analyse_on_stop` + `gates.analyse_skip_reason`.
declared='mysql'
[ -f .groundwork.json ] && declared="$(jq -r '.database.default // "mysql"' .groundwork.json 2>/dev/null || echo mysql)"
if [ "$declared" != "sqlite" ]; then
  for f in phpunit.xml phpunit.xml.dist .env.testing; do
    [ -f "$f" ] || continue
    matches="$(grep -Ei 'name="DB_(CONNECTION|DATABASE)"[^>]*value="(sqlite|:memory:)"|^[[:space:]]*DB_CONNECTION[[:space:]]*=[[:space:]]*sqlite' "$f" 2>/dev/null | grep -v '<!--' || true)"
    [ -n "$matches" ] || continue
    reason="$(jq -r '.gates.sqlite_tests_reason // empty' .groundwork.json 2>/dev/null || true)"
    if [ -n "$reason" ]; then
      echo "groundwork test-gate: the suite runs on SQLite while this project targets '${declared}' — accepted reason: ${reason}. Engine-specific defects are NOT covered by this run." >&2
      break
    fi
    {
      echo "groundwork test-gate: the suite resolves to SQLite (in ${f}) but this project targets '${declared}' — this run would be a false green, so it was not made."
      echo "Point the tests at ${declared} (DB_CONNECTION/DB_DATABASE in ${f}), or state why SQLite is acceptable here in .groundwork.json gates.sqlite_tests_reason."
      echo "(disable the whole gate with gates.test_on_stop=false)"
    } >&2
    exit 2
  done
fi

# --- scope: the close tests within a budget while working; the push check covers the rest (waves 37-38) ---
# The whole suite on every Stop cost otaje 383 minutes in a week (wave 37). Its replacement ran whatever
# test-select.py picked, and a routes file or a central class picked hundreds of files: from 2026-10-06 to
# 10-21, 30 Stop runs took 5+ minutes and 12 hit the hook's 10-minute limit with nothing verified. Now the
# selection keeps to the close circle (gw_tests.py), drops files already green on this exact code, and is
# cut to `gates.test_budget_seconds` (default 180) by recorded durations; what did not fit is named and
# left to push-gate.py, which runs close + wide before a shared branch. A run is stopped at twice the budget
# (never past 540 s) and says what it did not verify, instead of being killed silently by the harness.
# `gates.test_scope: "full"` restores the whole suite here. A custom `commands.test` that is not an
# artisan / phpunit / pest call cannot take file arguments, so it still runs whole.
hooks_dir="$(cd "$(dirname "$0")" && pwd)"
scope="$(jq -r '.gates.test_scope // "targeted"' .groundwork.json 2>/dev/null || echo targeted)"
full_run=1
limit=540
junit=''; run_files=''; notes=''
full_cmd="$(jq -r '.commands.test_full // empty' .groundwork.json 2>/dev/null || true)"   # e.g. … artisan test --parallel
budget="$(jq -r '.gates.test_budget_seconds // 180' .groundwork.json 2>/dev/null || echo 180)"
case "$budget" in ''|*[!0-9]*) budget=180 ;; esac
if [ "$scope" = "full" ] || ! printf '%s' "$cmd" | grep -qE 'artisan test|phpunit|/pest( |$)'; then
  [ -n "$full_cmd" ] && cmd="$full_cmd"
fi
if [ "$scope" != "full" ] && printf '%s' "$cmd" | grep -qE 'artisan test|phpunit|/pest( |$)'; then
  plan="$(python3 "$hooks_dir/test-select.py" --plan-stop 2>/dev/null || true)"
  run_files="$(printf '%s' "$plan" | jq -r '.run[]?' 2>/dev/null || true)"
  n_green="$(printf '%s' "$plan" | jq -r '.green // 0' 2>/dev/null || echo 0)"
  n_wide="$(printf '%s' "$plan" | jq -r '.wide // 0' 2>/dev/null || echo 0)"
  n_def="$(printf '%s' "$plan" | jq -r '.deferred | length' 2>/dev/null || echo 0)"
  shared="$(printf '%s' "$plan" | jq -r '.shared | join(", ")' 2>/dev/null || true)"
  [ "${n_def:-0}" -gt 0 ] 2>/dev/null && notes="${notes}groundwork test-gate: ${n_def} more close tests did not fit the ${budget} s budget and go to the push check: $(printf '%s' "$plan" | jq -r '.deferred[:5] | join(", ")')$([ "$n_def" -gt 5 ] && printf ' …')
"
  [ -n "$shared" ] && notes="${notes}groundwork test-gate: shared files changed (${shared}) — the whole suite runs before a push to a shared branch (test-run.py --for-push).
"
  if [ -z "$run_files" ]; then
    if [ "${n_green:-0}" -gt 0 ] 2>/dev/null; then
      echo "groundwork test-gate: the ${n_green} close tests already passed on this exact code — none run now." >&2
    else
      echo "groundwork test-gate: no test is close to this change — none run now. The push check runs its wider tests (${n_wide:-0}) before a shared branch." >&2
    fi
    printf '%s' "$notes" >&2
    exit 0
  fi
  n_sel="$(printf '%s\n' "$run_files" | grep -c .)"
  if [ -d storage/framework/testing ]; then      # git-ignored in every Laravel skeleton; durations come from here
    junit="storage/framework/testing/gw-junit-$$.xml"
    cmd="$cmd --log-junit=$junit"
  fi
  cmd="$cmd $(printf '%s\n' "$run_files" | tr '\n' ' ')"
  full_run=0
  limit=$((budget * 2)); [ "$limit" -gt 540 ] && limit=540; [ "$limit" -lt 10 ] && limit=10
fi

# Stop a run past its limit — and, under Sail, its PHP process inside the container, which outlives the
# host-side client (otaje, 2026-09-25: an interrupted run kept going and held the test database).
stop_container_tests() {
  case "$cmd" in *vendor/bin/sail*)
    svc="$(sed -n 's/^APP_SERVICE=//p' .env 2>/dev/null | tr -d '"' | head -1)"
    ./vendor/bin/sail exec -T "${svc:-laravel.test}" pkill -f 'artisan test|vendor/bin/phpunit|vendor/bin/pest|paratest' >/dev/null 2>&1 || true ;;
  esac
}
stop_run() {
  pkill -TERM -P "$1" 2>/dev/null || true; kill -TERM "$1" 2>/dev/null || true
  stop_container_tests
  sleep 1; pkill -KILL -P "$1" 2>/dev/null || true; kill -KILL "$1" 2>/dev/null || true
}

# --- serialise the suite across parallel sessions sharing one test database ---
# Two sessions interleaving `migrate:fresh` and a running suite produce failures that describe
# neither session's code ("1412 Table definition has changed" -> "1146 doesn't exist"). An atomic
# mkdir is the lock (flock is absent on macOS). Every path here fails OPEN: a busy database is an
# environment problem, and this gate must never invent a red.
# The lock lives in the repository's COMMON git dir, keyed by the test database (GW35-AC3): every
# worktree of the repository sees it, and two lanes with their own test databases never wait on each
# other. Until v0.45.0 it lived in `.claude/groundwork/locks/` of each working tree, so two worktrees
# sharing one test database each held "the" lock and collided anyway.
# phpunit.xml first: it is what the run actually uses — it beats .env.testing, often with force="true".
lock_db="$(grep -oE 'name="DB_DATABASE"[^>]*value="[^"]*"' phpunit.xml 2>/dev/null | sed -E 's/.*value="([^"]*)".*/\1/' | head -1)"
[ -n "$lock_db" ] || lock_db="$(sed -n 's/^[[:space:]]*DB_DATABASE[[:space:]]*=[[:space:]]*//p' .env.testing 2>/dev/null | head -1 | tr -d '"'"'"' ')"
lock_db="$(printf '%s' "${lock_db:-default}" | tr -c 'A-Za-z0-9_.-' '_')"
lock_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$lock_common" ] && [ -d "$lock_common" ]; then
  lock_dir="$lock_common/groundwork/locks/test-db-$lock_db"
else
  lock_dir='.claude/groundwork/locks/test-db'
fi
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

    # Its holder is dead (a session restarted mid-run): take it over now rather than in 30 minutes, and stop
    # what the dead run left inside the container (otaje, 2026-10-21: the suite kept running there unowned).
    holder_pid="$(tr -dc '0-9' < "$lock_dir/owner" 2>/dev/null || true)"
    if [ -n "$holder_pid" ] && ! ps -p "$holder_pid" >/dev/null 2>&1; then
      stop_container_tests
      rm -rf "$lock_dir" 2>/dev/null || true
      [ -d "$lock_dir" ] || continue
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
      holder="$(head -1 "$lock_dir/label" 2>/dev/null || true)"   # test-run.py names its run; a gate does not
      echo "groundwork test-gate: the test database is busy (${holder:-another session}) — suite NOT run, NOTHING WAS VERIFIED. Re-run when it frees up." >&2
      exit 1
    fi
    sleep 1; waited=$((waited + 1))
  done
fi

# Run the gate. Pass -> allow stop. Fail -> block (exit 2) and feed errors back to the agent.
outf="$(mktemp "${TMPDIR:-/tmp}/gw-test-gate.XXXXXX" 2>/dev/null || echo "${TMPDIR:-/tmp}/gw-test-gate.$$")"
# shellcheck disable=SC2086
$cmd >"$outf" 2>&1 &
run_pid=$!
ticks=0; timed_out=0              # tenths of a second; fine-grained first, so a quick run costs no extra second
while kill -0 "$run_pid" 2>/dev/null; do
  if [ "$ticks" -ge $((limit * 10)) ]; then timed_out=1; stop_run "$run_pid"; break; fi
  if [ "$ticks" -lt 50 ]; then sleep 0.1; ticks=$((ticks + 1)); else sleep 1; ticks=$((ticks + 10)); fi
done
wait "$run_pid" 2>/dev/null; status=$?
out="$(cat "$outf" 2>/dev/null || true)"; rm -f "$outf"

if [ "$timed_out" = "1" ]; then
  [ -n "$junit" ] && rm -f "$junit"
  {
    echo "groundwork test-gate: the run passed its ${limit} s limit and was stopped — NOTHING WAS VERIFIED for: $(printf '%s\n' "$run_files" | head -5 | tr '\n' ' ')"
    echo "Run them with \`python3 \"$hooks_dir/test-run.py\" --close\` (run_in_background: true), or lower the selection."
    printf '%s' "$notes"
  } >&2
  exit 1
fi

# What this run proved, by the exact code: the green files (all of them on exit 0; per file from the JUnit
# log otherwise) and their durations, so neither the next Stop nor the push check repeats them.
if [ "$full_run" = "0" ]; then
  printf '%s\n' "$run_files" | python3 "$hooks_dir/suite-record.py" --record-run --status "$status" --junit "$junit" >/dev/null 2>&1 || true
fi

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
    if [ "$full_run" = "1" ]; then
      echo "groundwork test-gate: tests FAILED on changed PHP — not done yet (red). Make them green before finishing."
    else
      echo "groundwork test-gate: the ${n_sel} test files that touch this change FAILED — not done yet (red). Make them green before finishing."
    fi
    printf '%s\n' "$out" | tail -40
    printf '%s' "$notes"
  } >&2
  exit 2
fi

# A green whole-suite run on this exact tree is what push-gate.py asks for; remember it.
[ "$full_run" = "1" ] && python3 "$hooks_dir/suite-record.py" --record >/dev/null 2>&1 || true
printf '%s' "$notes" >&2
exit 0
