#!/usr/bin/env bash
# Groundwork plugin :: executable proof for done-gate.sh and format-on-edit.sh (W11-AC2, AC12).
# Both learned the runner in Wave 11, and done-gate also learned `-uall`. Neither had a suite.
# Run: bash hooks/tests/gates.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

expect() { # name want dir hook stdin
  local name="$1" want="$2" dir="$3" hook="$4" stdin="${5:-}" got
  ( cd "$dir" && printf '%s' "$stdin" | bash "$HOOKS/$hook" >/dev/null 2>&1 ); got=$?
  if [ "$got" = "$want" ]; then pass=$((pass+1)); printf '  ok   %-32s (exit %s)\n' "$name" "$got"
  else fail=$((fail+1)); printf '  FAIL %-32s (want %s, got %s)\n' "$name" "$want" "$got"; fi
}

repo() { # dir json  -> git repo with committed baseline
  mkdir -p "$1"
  printf '%s\n' "$2" > "$1/.groundwork.json"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'x\n' > a.txt && git add -A && git commit -qm init )
}
stub() { printf '#!/bin/sh\nexit %s\n' "${2:-0}" > "$1"; chmod +x "$1"; }

echo "done-gate:"

# runner:host runs the analyser instead of skipping on a missing Sail
d="$ROOT/d1"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./bad.sh" } }'
stub "$d/bad.sh" 1; printf '<?php\n' > "$d/x.php"
expect "host analyse blocks"      2 "$d" "done-gate.sh"
d="$ROOT/d2"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./ok.sh" } }'
stub "$d/ok.sh" 0;  printf '<?php\n' > "$d/x.php"
expect "host analyse clean"       0 "$d" "done-gate.sh"

# an explicit override wins over the runner's availability (regression guard)
d="$ROOT/d3"; repo "$d" '{ "runner": "sail", "commands": { "analyse": "./bad.sh" } }'
stub "$d/bad.sh" 1; printf '<?php\n' > "$d/x.php"
expect "override beats runner"    2 "$d" "done-gate.sh"

# W11-AC12: PHP inside a brand-new untracked directory must be detected
d="$ROOT/d4"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./bad.sh" } }'
stub "$d/bad.sh" 1; mkdir -p "$d/app/Services"; printf '<?php\n' > "$d/app/Services/S.php"
expect "new dir php detected"     2 "$d" "done-gate.sh"

# opt-out and no-PHP stay silent
# W14b/E11: an opt-out is silent only when the project SAID WHY. An undocumented opt-out with changed
# PHP is a silent skip — the Definition of Done keeps promising a step nobody runs — so it reports.
d="$ROOT/d5"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./bad.sh" }, "gates": { "analyse_on_stop": false, "analyse_skip_reason": "no analyser in this legacy repo yet" } }'
stub "$d/bad.sh" 1; printf '<?php\n' > "$d/x.php"
expect "toggle off + reason silent" 0 "$d" "done-gate.sh"
d="$ROOT/d5b"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./bad.sh" }, "gates": { "analyse_on_stop": false } }'
stub "$d/bad.sh" 1; printf '<?php\n' > "$d/x.php"
expect "toggle off, no reason"      1 "$d" "done-gate.sh"
d="$ROOT/d5c"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./bad.sh" }, "gates": { "analyse_on_stop": false } }'
stub "$d/bad.sh" 1; printf 'plain\n' > "$d/notes.txt"
expect "toggle off, no php, quiet"  0 "$d" "done-gate.sh"
d="$ROOT/d6"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./bad.sh" } }'
stub "$d/bad.sh" 1; printf 'plain\n' > "$d/notes.txt"
expect "no php no-op"             0 "$d" "done-gate.sh"

# E11: a declared no-op MUST NOT pass as analysis. `echo '...'` exits 0, so before this the gate
# reported a clean static-analysis run for a project that has no analyser at all.
d="$ROOT/n1"; repo "$d" '{ "runner": "host", "commands": { "analyse": "echo \"no static-analysis tool configured\"" } }'
printf '<?php\n' > "$d/x.php"
expect "echo stub is not a pass"   1 "$d" "done-gate.sh"
d="$ROOT/n2"; repo "$d" '{ "runner": "host", "commands": { "analyse": "true" } }'
printf '<?php\n' > "$d/x.php"
expect "true stub is not a pass"   1 "$d" "done-gate.sh"
d="$ROOT/n3"; repo "$d" '{ "runner": "host", "commands": { "analyse": ":" } }'
printf '<?php\n' > "$d/x.php"
expect "colon stub is not a pass"  1 "$d" "done-gate.sh"
d="$ROOT/n4"; repo "$d" '{ "runner": "host", "commands": { "analyse": "  echo skip" } }'
printf '<?php\n' > "$d/x.php"
expect "leading space stub"        1 "$d" "done-gate.sh"
# A real command whose name merely contains a stub word still runs.
d="$ROOT/n5"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./echoes.sh" } }'
stub "$d/echoes.sh" 0; printf '<?php\n' > "$d/x.php"
expect "not a stub: ./echoes.sh"   0 "$d" "done-gate.sh"

# REGRESSION GUARD (the contract both gates state in their header): an unreachable command is an
# ENVIRONMENT problem, never a red. runner:host with no override must not block the Stop forever.
d="$ROOT/d7"; repo "$d" '{ "runner": "host" }'; printf '<?php\n' > "$d/x.php"
expect "host missing cmd reports"  1 "$d" "done-gate.sh"
d="$ROOT/d8"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./nope.sh" } }'
printf '<?php\n' > "$d/x.php"
expect "missing script reports"    1 "$d" "done-gate.sh"

# --- H1: a RED suite whose output merely CONTAINS an env phrase must still block.
# "No such file or directory" / "command not found" appear routinely inside real Laravel failures
# (Storage, file_get_contents, Process, artisan-command tests) — matching them by substring turned a
# red suite into "environment, not a failure". Only a command that never ran may be waived.
d="$ROOT/h1"; repo "$d" '{ "runner": "host", "commands": { "test": "./red.sh" } }'
cat > "$d/red.sh" <<'SH'
#!/bin/sh
echo "ErrorException: file_get_contents(/tmp/x): Failed to open stream: No such file or directory"
echo "Tests:  1 failed, 4 passed"
exit 1
SH
chmod +x "$d/red.sh"; printf '<?php\n' > "$d/x.php"
expect "red suite w/ env phrase"   2 "$d" "test-gate.sh"

d="$ROOT/h1b"; repo "$d" '{ "runner": "host", "commands": { "analyse": "./red.sh" } }'
cat > "$d/red.sh" <<'SH'
#!/bin/sh
echo " [ERROR] Call to an undefined method App\Foo::bar()"
echo "sh: npm: command not found"
exit 1
SH
chmod +x "$d/red.sh"; printf '<?php\n' > "$d/x.php"
expect "red analyse w/ env phrase" 2 "$d" "done-gate.sh"

# a command that genuinely could not run is still waived
d="$ROOT/h1c"; repo "$d" '{ "runner": "host", "commands": { "test": "./nope.sh" } }'
printf '<?php\n' > "$d/x.php"
expect "unrunnable cmd reports"    1 "$d" "test-gate.sh"

# H2: skipping because the runner is unavailable must SAY so, not go silent
d="$ROOT/h2"; repo "$d" '{ "runner": "sail" }'; printf '<?php\n' > "$d/x.php"
msg="$( cd "$d" && bash "$HOOKS/test-gate.sh" 2>&1 >/dev/null )"
( cd "$d" && bash "$HOOKS/test-gate.sh" >/dev/null 2>&1 ); rc=$?
# stderr alone is not enough: on exit 0 the harness sends it to the debug log and nobody sees it.
if [ -n "$msg" ] && [ "$rc" -eq 1 ]; then pass=$((pass+1)); printf '  ok   %-32s [message + visible exit]\n' "skip is actually visible"
else fail=$((fail+1)); printf '  FAIL %-32s (msg=%s rc=%s)\n' "skip is actually visible" "${msg:+yes}" "$rc"; fi

# --- #1: committing must NOT disarm the gate while the work is unpushed ---
d="$ROOT/c1"; mkdir -p "$d/remote"
( cd "$d/remote" && git init -q --bare )
mkdir -p "$d/wt"; printf '{ "runner": "host", "commands": { "test": "./bad.sh" } }\n' > "$d/wt/.groundwork.json"
printf '#!/bin/sh\nexit 1\n' > "$d/wt/bad.sh"; chmod +x "$d/wt/bad.sh"
( cd "$d/wt" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'x\n' > a.txt && git add -A && git commit -qm init \
  && git remote add origin ../remote && git push -q -u origin HEAD >/dev/null 2>&1 )
printf '<?php\nclass Broken {}\n' > "$d/wt/x.php"
expect "red blocks before commit"  2 "$d/wt" "test-gate.sh"
( cd "$d/wt" && git add -A && git commit -qm "work" )
expect "red still blocks after commit" 2 "$d/wt" "test-gate.sh"
( cd "$d/wt" && git push -q origin HEAD >/dev/null 2>&1 )
expect "pushed work is released"   0 "$d/wt" "test-gate.sh"

echo
echo "format-on-edit:"

# the formatter runs (best-effort, never blocks) and honors the toggle
d="$ROOT/f1"; repo "$d" '{ "runner": "host", "commands": { "format": "./fmt.sh" } }'
printf '#!/bin/sh\necho "$@" >> fmt.log\nexit 0\n' > "$d/fmt.sh"; chmod +x "$d/fmt.sh"
printf '<?php\n' > "$d/x.php"
expect "formats edited php"       0 "$d" "format-on-edit.sh" "{\"tool_input\":{\"file_path\":\"$d/x.php\"}}"
if [ -f "$d/fmt.log" ]; then pass=$((pass+1)); printf '  ok   %-32s [invoked]\n' "override actually invoked"
else fail=$((fail+1)); printf '  FAIL %-32s formatter was never called\n' "override actually invoked"; fi

d="$ROOT/f2"; repo "$d" '{ "runner": "host", "gates": { "format_on_edit": false }, "commands": { "format": "./fmt.sh" } }'
printf '#!/bin/sh\ntouch fmt.log\n' > "$d/fmt.sh"; chmod +x "$d/fmt.sh"; printf '<?php\n' > "$d/x.php"
expect "toggle off"               0 "$d" "format-on-edit.sh" "{\"tool_input\":{\"file_path\":\"$d/x.php\"}}"
if [ ! -f "$d/fmt.log" ]; then pass=$((pass+1)); printf '  ok   %-32s [not invoked]\n' "toggle off skips formatter"
else fail=$((fail+1)); printf '  FAIL %-32s formatter ran while disabled\n' "toggle off skips formatter"; fi

# non-PHP is ignored
d="$ROOT/f3"; repo "$d" '{ "runner": "host", "commands": { "format": "./fmt.sh" } }'
printf '#!/bin/sh\ntouch fmt.log\n' > "$d/fmt.sh"; chmod +x "$d/fmt.sh"; printf 'x\n' > "$d/notes.md"
expect "ignores non-php"          0 "$d" "format-on-edit.sh" "{\"tool_input\":{\"file_path\":\"$d/notes.md\"}}"

# an explicit override wins over the runner's availability here too (runner:sail, no Sail binary)
d="$ROOT/f4"; repo "$d" '{ "runner": "sail", "commands": { "format": "./fmt.sh" } }'
printf '#!/bin/sh\ntouch fmt.log\n' > "$d/fmt.sh"; chmod +x "$d/fmt.sh"; printf '<?php\n' > "$d/x.php"
expect "override under sail"      0 "$d" "format-on-edit.sh" "{\"tool_input\":{\"file_path\":\"$d/x.php\"}}"
if [ -f "$d/fmt.log" ]; then pass=$((pass+1)); printf '  ok   %-32s [invoked]\n' "override beats runner"
else fail=$((fail+1)); printf '  FAIL %-32s override skipped by runner check\n' "override beats runner"; fi

# the shipped project template must not pin gates to Sail — runner:host has to work out of the box
tpl="$(cd "$(dirname "$0")/../.." && pwd)/templates/project/.groundwork.json"
if [ -f "$tpl" ] && [ -z "$(jq -r '.commands | to_entries[]? | select(.value | test("vendor/bin/sail")) | .key' "$tpl" 2>/dev/null)" ]; then
  pass=$((pass+1)); printf '  ok   %-32s [no sail pinned]\n' "template honors runner"
else
  fail=$((fail+1)); printf '  FAIL %-32s template pins commands to Sail\n' "template honors runner"
fi

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
