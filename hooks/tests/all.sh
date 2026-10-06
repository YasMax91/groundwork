#!/usr/bin/env bash
# Groundwork plugin :: run every hook test suite.
# The hooks are the only executable part of this plugin, and a denying hook can strand a
# workflow — so they carry tests, and this is the one command that runs all of them.
# Run: bash hooks/tests/all.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
failed=0

for suite in lib run test-gate gates openapi-gate handoff-gate coverage-claim estimate-ledger estimate-claim estimate-docs task-intent agent-contract statusline session-start trim-output pre-compact defect-scan slice-gate plain-language stdin-guard lane lane-idle in-cwd failsafe; do
  f="$DIR/${suite}.sh"
  [ -f "$f" ] || { printf '\n== %s: MISSING (%s)\n' "$suite" "$f"; failed=$((failed+1)); continue; }
  printf '\n== %s\n' "$suite"
  bash "$f" || failed=$((failed+1))
done

# The follow-through plugin lives in this repository and shares this runner and CI.
printf '\n== follow-through\n'
FT_TESTS="$DIR/../../follow-through/hooks/tests"
if [ -d "$FT_TESTS" ]; then
  if python3 -m unittest discover -s "$FT_TESTS" > "${TMPDIR:-/tmp}/ft-tests.$$" 2>&1; then
    tail -3 "${TMPDIR:-/tmp}/ft-tests.$$" | sed 's/^/  /'
  else
    cat "${TMPDIR:-/tmp}/ft-tests.$$"; failed=$((failed+1))
  fi
  rm -f "${TMPDIR:-/tmp}/ft-tests.$$"
else
  printf '  MISSING (%s)\n' "$FT_TESTS"; failed=$((failed+1))
fi

printf '\n=====================\n'
if [ "$failed" -eq 0 ]; then
  echo "all hook suites passed"
else
  echo "FAILED suites: $failed"
fi
[ "$failed" -eq 0 ]
