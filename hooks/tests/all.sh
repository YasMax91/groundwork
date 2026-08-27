#!/usr/bin/env bash
# Groundwork plugin :: run every hook test suite.
# The hooks are the only executable part of this plugin, and a denying hook can strand a
# workflow — so they carry tests, and this is the one command that runs all of them.
# Run: bash hooks/tests/all.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
failed=0

for suite in lib run test-gate gates openapi-gate coverage-claim estimate-ledger estimate-claim task-intent agent-contract statusline session-start trim-output pre-compact failsafe; do
  f="$DIR/${suite}.sh"
  [ -f "$f" ] || { printf '\n== %s: MISSING (%s)\n' "$suite" "$f"; failed=$((failed+1)); continue; }
  printf '\n== %s\n' "$suite"
  bash "$f" || failed=$((failed+1))
done

printf '\n=====================\n'
if [ "$failed" -eq 0 ]; then
  echo "all hook suites passed"
else
  echo "FAILED suites: $failed"
fi
[ "$failed" -eq 0 ]
