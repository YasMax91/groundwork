#!/usr/bin/env bash
# Groundwork plugin :: executable proof for stdin-guard.sh.
# The hook rewrites every Bash command, so two things are proven, not assumed: the rewrite ends
# the reads that used to hang (under an stdin that never closes, as the Bash tool provides), and
# it leaves everything else — heredocs, exit codes, output, the other input fields — as it was.
# Run: bash hooks/tests/stdin-guard.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/stdin-guard.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
d="$ROOT/p"; mkdir -p "$d"
d_off="$ROOT/off"; mkdir -p "$d_off"
printf '{ "gates": { "isolate_stdin": false } }\n' > "$d_off/.groundwork.json"

ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2"; }

payload() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c,description:"d",timeout:5000}}'; }
hook()    { ( cd "${2:-$d}" && printf '%s' "$1" | bash "$HOOK" 2>/dev/null ); }
wrapped() { hook "$(payload "$1")" | jq -r '.hookSpecificOutput.updatedInput.command'; }

# Run a command under an stdin that stays open (the Bash tool's condition) with a watchdog.
# Prints the command's output; returns its exit code, or 124 when the watchdog had to kill it.
run_open_stdin() { # shell command
  local fifo="$ROOT/in" out="$ROOT/out" rc i=0
  rm -f "$fifo"; mkfifo "$fifo"
  # A writer that never writes keeps the fifo open — the command's stdin never reaches EOF.
  sleep 60 > "$fifo" < /dev/null 2>/dev/null &
  local writer=$!
  "$1" -c "$2" < "$fifo" > "$out" 2>&1 &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rc=124
  else
    wait "$pid"; rc=$?
    cat "$out"
  fi
  kill "$writer" 2>/dev/null; wait "$writer" 2>/dev/null
  rm -f "$fifo" "$out"
  return "$rc"
}

echo "rewrite:"
w="$(wrapped 'ls -la')"
[ "$w" = "$(printf 'true | (\nls -la\n)')" ] && ok "wraps the command" || bad "wraps the command" "$w"

full="$(hook "$(payload 'ls')" | jq -c '.hookSpecificOutput.updatedInput | {description, timeout}')"
[ "$full" = '{"description":"d","timeout":5000}' ] && ok "keeps the other input fields" || bad "keeps the other input fields" "$full"

out="$(hook "$(payload 'ls')" | jq -r '.hookSpecificOutput.permissionDecision // "none"')"
[ "$out" = "none" ] && ok "makes no permission decision" || bad "makes no permission decision" "$out"

[ -z "$(hook "$(payload "$w")")" ] && ok "does not wrap twice" || bad "does not wrap twice" "output on a wrapped command"
[ -z "$(hook '{"tool_name":"Edit","tool_input":{"file_path":"a"}}')" ] && ok "ignores other tools" || bad "ignores other tools" "output"
[ -z "$(hook "$(payload 'ls')" "$d_off")" ] && ok "opt-out via gates.isolate_stdin" || bad "opt-out via gates.isolate_stdin" "output"
[ -z "$(hook '')" ] && ok "empty stdin" || bad "empty stdin" "output"
[ -z "$(hook 'not json')" ] && ok "unparseable stdin" || bad "unparseable stdin" "output"

for sh in bash zsh; do
  command -v "$sh" >/dev/null 2>&1 || { echo "  ($sh not installed — skipped)"; continue; }
  echo "behaviour under $sh, stdin left open:"

  # The proof the guard is needed at all: unwrapped, a stray read hangs.
  run_open_stdin "$sh" 'cat > /dev/null' >/dev/null; rc=$?
  [ "$rc" = 124 ] && ok "$sh: unwrapped 'cat >' hangs (control)" || bad "$sh: unwrapped 'cat >' hangs (control)" "exit $rc"

  for c in 'cat > /dev/null' 'python3 - 2>/dev/null || true' 'read -r line; echo "got:$line"'; do
    run_open_stdin "$sh" "$(wrapped "$c")" >/dev/null; rc=$?
    [ "$rc" != 124 ] && ok "$sh: ends at once: $c" || bad "$sh: ends at once: $c" "still hangs"
  done

  # The exact command that hung for 65 hours: heredoc bound to the second python only.
  got="$(run_open_stdin "$sh" "$(wrapped "$(printf "python3 - 2>/dev/null || python3 - <<'EOF'\nprint('second')\nEOF")")")"; rc=$?
  [ "$rc" != 124 ] && ok "$sh: the 65-hour command now ends" || bad "$sh: the 65-hour command now ends" "still hangs"

  got="$(run_open_stdin "$sh" "$(wrapped "$(printf "python3 - <<'PY'\nprint('from heredoc')\nPY")")")"
  [ "$got" = "from heredoc" ] && ok "$sh: heredoc still feeds its command" || bad "$sh: heredoc still feeds its command" "$got"

  run_open_stdin "$sh" "$(wrapped 'echo x; exit 7')" >/dev/null; rc=$?
  [ "$rc" = 7 ] && ok "$sh: exit code preserved" || bad "$sh: exit code preserved" "exit $rc"

  got="$(run_open_stdin "$sh" "$(wrapped "$(printf 'echo one # trailing comment\necho two | tr a-z A-Z')")")"
  [ "$got" = "$(printf 'one\nTWO')" ] && ok "$sh: output and trailing comment intact" || bad "$sh: output and trailing comment intact" "$got"
done

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
