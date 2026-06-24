#!/usr/bin/env bash
# RaDevs plugin :: Stop hook.
# Block "done" if the test suite fails on changed PHP. Fires only when PHP changed;
# never blocks on environment problems (Sail down, not a git repo, etc.).
set -uo pipefail

# Resolve gate command + opt-out from .groundwork.json (defaults to Sail + artisan test).
cmd='./vendor/bin/sail artisan test'
if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.test_on_stop' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
  override="$(jq -r '.commands.test // empty' .groundwork.json 2>/dev/null || true)"
  [ -n "$override" ] && cmd="$override"
fi

# Only act when PHP actually changed since the last commit.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
changed="$(git status --porcelain 2>/dev/null | grep -E '\.php"?$' || true)"
[ -z "$changed" ] && exit 0

# If the gate relies on Sail and it is unavailable, do not block (env issue).
case "$cmd" in
  *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;;
esac

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

# Run the gate. Pass -> allow stop. Fail -> block (exit 2) and feed errors back to the agent.
# shellcheck disable=SC2086
out="$($cmd 2>&1)"; status=$?
if [ "$status" -ne 0 ]; then
  {
    echo "groundwork test-gate: tests FAILED on changed PHP — not done yet (red). Make them green before finishing."
    printf '%s\n' "$out" | tail -40
  } >&2
  exit 2
fi
exit 0
