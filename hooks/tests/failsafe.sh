#!/usr/bin/env bash
# Groundwork plugin :: executable proof for W11-AC8 — every hook survives a missing lib.sh.
# The shared library is a new dependency for seven hooks, so its absence is tested rather than
# assumed: each hook must still run (never a shell error) and fall back to its Sail defaults.
# Run: bash hooks/tests/failsafe.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS/lib.sh"
[ -f "$LIB" ] || { echo "lib not found: $LIB"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"
BACKUP="$ROOT/lib.sh.bak"
# Copy, never move: if this suite is killed uncatchably (SIGKILL), the original must still be there.
# lib.sh is untracked, so a lost copy could not be recovered with git.
cp "$LIB" "$BACKUP"
restore() { [ -f "$BACKUP" ] && cp "$BACKUP" "$LIB"; rm -rf "$ROOT"; }
trap restore EXIT INT TERM

# A project fixture the hooks will actually engage with.
d="$ROOT/p"; mkdir -p "$d/app" "$d/.claude/groundwork"
printf '{ "runner": "sail", "database": { "default": "mysql" }, "ui": { "statusline": true } }\n' > "$d/.groundwork.json"
printf '# Task: x\n- Mode: Discovery\n- Level: L2\n' > "$d/.claude/groundwork/task-state.md"
( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'x\n' > a.txt && git add -A && git commit -qm init )
printf '<?php\nclass A {}\n' > "$d/app/A.php"

runs() { # name hook stdin
  local name="$1" hook="$2" stdin="${3:-}" got
  ( cd "$d" && printf '%s' "$stdin" | bash "$HOOKS/$hook" >/dev/null 2>&1 ); got=$?
  # 0 = allowed, 1 = "did not run, and reported it", 2 = a deliberate block.
  # Anything else means the script itself broke (127, or 1 from an unbound variable).
  if [ "$got" -eq 0 ] || [ "$got" -eq 1 ] || [ "$got" -eq 2 ]; then
    pass=$((pass+1)); printf '  ok   %-28s (exit %s)\n' "$name" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-28s (exit %s — hook broke without lib.sh)\n' "$name" "$got"
  fi
}

echo "failsafe (lib.sh absent):"
rm -f "$LIB"   # hide the library for the duration of the suite (restored from $BACKUP by the trap)

runs "session-start"   "session-start.sh"   ''
runs "statusline"      "statusline.sh"      ''
runs "done-gate"       "done-gate.sh"       ''
runs "test-gate"       "test-gate.sh"       ''
runs "openapi-gate"    "openapi-gate.sh"    ''
runs "format-on-edit"  "format-on-edit.sh"  "{\"tool_input\":{\"file_path\":\"$d/app/A.php\"}}"
runs "pre-tool-guard"  "pre-tool-guard.sh"  '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'

# The guard must still enforce its rules from the fallback: host php stays denied under runner:sail.
mkdir -p "$d/vendor/bin"; printf '#!/bin/sh\nexit 0\n' > "$d/vendor/bin/sail"; chmod +x "$d/vendor/bin/sail"
( cd "$d" && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"php artisan migrate"}}' \
  | bash "$HOOKS/pre-tool-guard.sh" >/dev/null 2>&1 ); got=$?
if [ "$got" = 2 ]; then
  pass=$((pass+1)); printf '  ok   %-28s (exit 2 — rule still enforced)\n' "guard denies host php"
else
  fail=$((fail+1)); printf '  FAIL %-28s (want 2, got %s)\n' "guard denies host php" "$got"
fi

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
