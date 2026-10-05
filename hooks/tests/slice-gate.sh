#!/usr/bin/env bash
# Groundwork plugin :: executable proof for slice-gate.sh (wave 31).
# Every AC of docs/specs/wave-31-the-slice-list-becomes-a-contract.md gets cases here, and the
# journal rows (AC5) are taken verbatim from the 37-checkpoint audit that redirected the spec.
# Run: bash hooks/tests/slice-gate.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/slice-gate.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() { # dir [gates json] [memory json]
  # The defaults are assigned, never inlined as "${2:-\{\}}": inside double quotes those
  # backslashes survive into the file and the JSON stops parsing, which reads as "no config".
  local g="${2:-}" m="${3:-}"
  [ -n "$g" ] || g='{}'
  [ -n "$m" ] || m='{}'
  mkdir -p "$1/.claude/groundwork" "$1/tests/Feature" "$1/docs/specs"
  printf '{ "runner": "host", "gates": %s, "memory": %s }\n' "$g" "$m" > "$1/.groundwork.json"
}

state() { # dir mode level slices...
  local d="$1" mode="$2" level="$3"; shift 3
  { printf '# Task: t\n- Mode: %s\n- Level: %s\n- Spec: docs/specs/s.md\n\n## Plan (slices)\n' "$mode" "$level"
    for s in "$@"; do printf '%s\n' "$s"; done
  } > "$d/.claude/groundwork/task-state.md"
}

goodtest() { printf '<?php\nclass T { public function test_it() { $this->assertSame(1, $x); } }\n' > "$1"; }

run()  { ( cd "$1" && printf '{}' | bash "$HOOK" 2>&1 >/dev/null ); }
code() { ( cd "$1" && printf '{}' | bash "$HOOK" >/dev/null 2>&1 ); printf '%s' "$?"; }

expect() { # name dir want_code [want_substr]
  local got out; got="$(code "$2")"; out="$(run "$2")"
  if [ "$got" = "$3" ] && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -q "$4"; }; then
    pass=$((pass+1)); printf '  ok   %-40s (exit %s)\n' "$1" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-40s want exit %s%s, got %s: %s\n' "$1" "$3" "${4:+ + \"$4\"}" "$got" "$(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
}

echo "slice-gate:"

# --- AC1: a closed slice that names no proof ------------------------------------------------------
d="$ROOT/ac1"; proj "$d"; state "$d" Implementation L2 '- [x] promo code applies to the cart total (AC1)'
expect "AC1 closed with no proof" "$d" 2 "closed with no proof"
d="$ROOT/ac1b"; proj "$d"; state "$d" Implementation L2 '- [ ] promo code applies to the cart total (AC1)'
expect "AC1 an open slice is work, not a fault" "$d" 0

# --- AC2: test: <path> — existence is the question, passing is wave-32's -------------------------
d="$ROOT/ac2a"; proj "$d"; state "$d" Implementation L2 '- [x] expiry is refused (AC1) — test: tests/Feature/GoneTest.php'
expect "AC2 missing test file" "$d" 2 "does not exist"
d="$ROOT/ac2b"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 '- [x] expiry is refused (AC1) — test: tests/Feature/HereTest.php'
expect "AC2 present test file" "$d" 0
# a test that would FAIL is still accepted — this gate executes nothing
d="$ROOT/ac2c"; proj "$d"
printf '<?php\nclass T { public function test_it() { $this->assertSame(1, 2); } }\n' > "$d/tests/Feature/RedTest.php"
state "$d" Implementation L2 '- [x] expiry is refused (AC1) — test: tests/Feature/RedTest.php'
expect "AC2 a failing test is not this gate" "$d" 0

# --- AC3: manual: must say what a person observed -------------------------------------------------
d="$ROOT/ac3a"; proj "$d"
state "$d" Implementation L2 '- [x] refusal wording (AC1) — manual: product owner read the 422 body on staging 2026-09-14'
expect "AC3 substantive manual proof" "$d" 0
d="$ROOT/ac3b"; proj "$d"; state "$d" Implementation L2 '- [x] refusal wording (AC1) — manual:'
expect "AC3 empty manual" "$d" 2 "manual: with no text"
d="$ROOT/ac3c"; proj "$d"; state "$d" Implementation L2 '- [x] refusal wording (AC1) — manual: refusal wording'
expect "AC3 manual restates the title" "$d" 2 "restates the slice title"
d="$ROOT/ac3d"; proj "$d"; state "$d" Implementation L2 '- [x] refusal wording (AC1) — manual: verified'
expect "AC3 a content-free manual word" "$d" 2 "proves nothing"

# --- AC4: abandonment is terminal, reportable, never complete -------------------------------------
d="$ROOT/ac4a"; proj "$d"
state "$d" Implementation L2 '- [~] bulk import (AC1) — abandoned: CSV schema not agreed; handed off in the summary'
expect "AC4 abandoned with a reason" "$d" 1 "HANDOFF REQUIRED"
d="$ROOT/ac4b"; proj "$d"; state "$d" Implementation L2 '- [~] bulk import (AC1) — abandoned:'
expect "AC4 abandoned with no reason" "$d" 2 "with no reason"

# --- AC5: journal rows, verbatim from the audited corpus ------------------------------------------
d="$ROOT/ac5"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 \
  '- [x] real slice (AC1) — test: tests/Feature/HereTest.php' \
  '- [x] commit — 5f8320a' \
  '- [x] E. Spec docs/specs/2026-07-content-placeholders.md + api-reference §13.4 + handoff 2026-07-28-content-placeholders.md' \
  '- [x] G. Live check in the admin panel (temporary local auto-login route, removed again): grid layout fixed,'
expect "AC5 journal rows are not slices" "$d" 0

# --- AC6: reconciliation against the spec, at Mode: Done ------------------------------------------
mkspec() { printf '# Spec\n\n| AC1 | a |\n| AC2 | b |\n| AC3 | c |\n' > "$1/docs/specs/s.md"; }
d="$ROOT/ac6a"; proj "$d"; mkspec "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" "Done — shipped" L2 '- [x] one (AC1) — test: tests/Feature/HereTest.php'
expect "AC6 unclaimed AC ids are named" "$d" 2 "AC2 AC3"
d="$ROOT/ac6b"; proj "$d"; mkspec "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" "Done — shipped" L2 '- [x] all three (AC1, AC2, AC3) — test: tests/Feature/HereTest.php'
expect "AC6 every AC claimed" "$d" 0
d="$ROOT/ac6c"; proj "$d"; mkspec "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" "Done — shipped" L2 \
  '- [x] two (AC1, AC2) — test: tests/Feature/HereTest.php' \
  '- [~] third (AC3) — abandoned: the provider has no sandbox for it'
expect "AC6 an abandoned AC counts as named" "$d" 1 "HANDOFF REQUIRED"
# not at Mode: Done, so nothing is reconciled yet
d="$ROOT/ac6d"; proj "$d"; mkspec "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 '- [x] one (AC1) — test: tests/Feature/HereTest.php'
expect "AC6 mid-task does not reconcile" "$d" 0

# --- GW34-AC3: every verbatim source requirement needs a proof cell, at Mode: Done ----------------
mkreq() { printf '# Spec\n\n## Source requirements\n\n| ID | Requirement | Source | Proof |\n|---|---|---|---|\n%s\n\n## Acceptance criteria\n\n| AC1 | a |\n' "$2" > "$1/docs/specs/s.md"; }
d="$ROOT/r1"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
mkreq "$d" "| R1 | export orders | msg 09:12 | tests/Feature/HereTest.php |
| R2 | mobile too | msg 09:14 | |
| R3 | sub-task: filters | brief:12 | - |"
state "$d" "Done — shipped" L2 '- [x] one (AC1) — test: tests/Feature/HereTest.php'
expect "GW34 unproven requirements are named" "$d" 2 "R2 R3"
d="$ROOT/r2"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
mkreq "$d" "| R1 | export orders | msg 09:12 | tests/Feature/HereTest.php |
| R2 | mobile too | msg 09:14 | out of scope: agreed 09:20, next task |"
state "$d" "Done — shipped" L2 '- [x] one (AC1) — test: tests/Feature/HereTest.php'
expect "GW34 every requirement proven" "$d" 0
d="$ROOT/r3"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
mkreq "$d" "| R1 | export orders | msg 09:12 | |"
state "$d" Implementation L2 '- [x] one (AC1) — test: tests/Feature/HereTest.php'
expect "GW34 mid-task does not reconcile" "$d" 0

# --- AC7: no (ACn) anywhere — one notice, no refusal ----------------------------------------------
d="$ROOT/ac7"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 '- [x] a slice with no criterion — test: tests/Feature/HereTest.php'
expect "AC7 no AC reference warns only" "$d" 1 "nothing was reconciled"

# --- AC7b: an ordinary notice must not wear the abandonment's header ------------------------------
# `grep -c` prints "0" on no match and [ -n "0" ] is true, so this header printed over every notice.
d="$ROOT/ac7b"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 '- [x] a slice with no criterion — test: tests/Feature/HereTest.php'
if run "$d" | grep -q "HANDOFF REQUIRED"; then
  fail=$((fail+1)); printf '  FAIL %-40s HANDOFF header on a plain notice\n' "AC7b notice is not a handoff"
else
  pass=$((pass+1)); printf '  ok   %-40s (no false handoff)\n' "AC7b notice is not a handoff"
fi

# --- AC14: a checkpoint written before this grammar is told, not refused --------------------------
d="$ROOT/ac14a"; proj "$d"
state "$d" Implementation L2 \
  '- [x] S1 upload stops destroying the original: original byte-for-byte + full-res WebP master' \
  '- [x] S2 schema (BROUGHT FORWARD before S1 — S1 writes the image_originals row)'
expect "AC14 a pre-v0.41.0 checkpoint" "$d" 0 "predates the v0.41.0 slice grammar"
# one slice speaking the new format arms the gate for all of them
d="$ROOT/ac14b"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 \
  '- [x] S1 named its proof — test: tests/Feature/HereTest.php' \
  '- [x] S2 did not'
expect "AC14 one new-format slice arms it" "$d" 2 "closed with no proof"
# an (ACn) alone is enough to count as the new format
d="$ROOT/ac14c"; proj "$d"
state "$d" Implementation L2 '- [x] S1 carries a criterion (AC1)'
expect "AC14 an (ACn) alone arms it" "$d" 2 "closed with no proof"

# --- AC8: the v0.40.0 format keeps working --------------------------------------------------------
d="$ROOT/ac8a"; proj "$d"; goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 '- [x] legacy row (AC1) — red test: tests/Feature/HereTest.php — status: green'
expect "AC8 red test: reads as test:" "$d" 0
d="$ROOT/ac8b"; proj "$d"
state "$d" Implementation L2 '- [x] legacy row (AC1) — red test: tests/Feature/GoneTest.php — status: green'
expect "AC8 status: green is not evidence" "$d" 2 "does not exist"

# --- AC9: an oracle that cannot fail --------------------------------------------------------------
d="$ROOT/ac9a"; proj "$d"; printf '<?php\nclass T { public function test_it() { $x = 1; } }\n' > "$d/tests/Feature/NoAssertTest.php"
state "$d" Implementation L2 '- [x] s (AC1) — test: tests/Feature/NoAssertTest.php'
expect "AC9 no assertion" "$d" 2 "no-assertion"
d="$ROOT/ac9b"; proj "$d"; printf '<?php\nclass T { public function test_it() { $this->assertTrue(true); } }\n' > "$d/tests/Feature/TautTest.php"
state "$d" Implementation L2 '- [x] s (AC1) — test: tests/Feature/TautTest.php'
expect "AC9 assertTrue(true)" "$d" 2 "tautological-assert"
d="$ROOT/ac9c"; proj "$d"; printf '<?php\nclass T { public function test_it() { $this->assertEquals(1, 1); } }\n' > "$d/tests/Feature/TautEqTest.php"
state "$d" Implementation L2 '- [x] s (AC1) — test: tests/Feature/TautEqTest.php'
expect "AC9 assertEquals(1, 1)" "$d" 2 "tautological-assert"
d="$ROOT/ac9d"; proj "$d"; printf '<?php\nclass T { public function test_it() { $this->markTestSkipped("later"); } }\n' > "$d/tests/Feature/SkipTest.php"
state "$d" Implementation L2 '- [x] s (AC1) — test: tests/Feature/SkipTest.php'
expect "AC9 a test that only skips" "$d" 2 "no-assertion"

# --- AC15: the shapes the real corpus writes ------------------------------------------------------
# Every row below is taken from a checkpoint in the 11-project audit. Before these parsed, the gate
# refused slices whose work was done and whose evidence was named.
d="$ROOT/ac15a"; proj "$d"; mkdir -p "$d/tests/Feature/Content"; goodtest "$d/tests/Feature/Content/CloudImageDiskConfigTest.php"
{ printf '# Task: t\n- Mode: Implementation\n- Level: L2\n- Spec: docs/specs/s.md\n\n## Plan (slices)\n'
  printf -- '- [x] S0 dependency + cloud disk + per-APP_ENV bucket prefix + MinIO in compose (AC1) —\n'
  printf '      red test: tests/Feature/Content/CloudImageDiskConfigTest — status: green (7 cases)\n'
  printf '      Live proof: write/read/url/delete round-trip through the `images` disk against MinIO.\n'
} > "$d/.claude/groundwork/task-state.md"
expect "AC15 proof on a continuation line" "$d" 0

d="$ROOT/ac15b"; proj "$d"; mkdir -p "$d/tests/Feature"
goodtest "$d/tests/Feature/GenerateDerivativesJobTest.php"; goodtest "$d/tests/Feature/ImageConcurrencyTest.php"
state "$d" Implementation L2 '- [x] pipeline core (AC1) — red tests: GenerateDerivativesJobTest (10), ImageConcurrencyTest (7) — green'
expect "AC15 plural tests:, class names" "$d" 0

d="$ROOT/ac15c"; proj "$d"; mkdir -p "$d/tests/Unit"; goodtest "$d/tests/Unit/PhoneNormalizeTest.php"
state "$d" Implementation L2 '- [x] Phone normalization (AC6, AC7) — tests/Unit/PhoneNormalizeTest.php'
expect "AC15 a test named with no label" "$d" 0

d="$ROOT/ac15d"; proj "$d"; mkdir -p "$d/tests/Feature/Admin"; goodtest "$d/tests/Feature/Admin/AdminTranslatableSortTest.php"
state "$d" Implementation L2 '- [x] S0 red: `tests/Feature/Admin/AdminTranslatableSortTest.php`, 3 cases (AC1)'
expect "AC15 red: instead of red test:" "$d" 0

# a slice naming a CODE file is not a slice naming its proof — the class this gate exists for
d="$ROOT/ac15e"; proj "$d"; mkdir -p "$d/app/Models/Traits"
printf '<?php\nclass X {}\n' > "$d/app/Models/Traits/OrdersByTranslatedColumn.php"
state "$d" Implementation L2 '- [x] S1: `app/Models/Traits/OrdersByTranslatedColumn.php` — `scopeOrderByTranslated` (AC1)'
expect "AC15 a code file is not a proof" "$d" 2 "closed with no proof"

# prose on a continuation must not be read as more test names
d="$ROOT/ac15f"; proj "$d"; mkdir -p "$d/tests/Feature/Content"; goodtest "$d/tests/Feature/Content/ImageOriginalPreservedTest.php"
{ printf '# Task: t\n- Mode: Implementation\n- Level: L2\n- Spec: docs/specs/s.md\n\n## Plan (slices)\n'
  printf -- '- [x] S1 upload stops destroying the original (AC1) —\n'
  printf '      red test: tests/Feature/Content/ImageOriginalPreservedTest — green (7 cases)\n'
  printf '      ImageUploadDownscalingTest was RENAMED to ImageUploadEncodingTest, which kept history, so\n'
  printf '      the suite still covers it.\n'
} > "$d/.claude/groundwork/task-state.md"
expect "AC15 prose is not a test name" "$d" 0

# --- AC10: the progress guard ---------------------------------------------------------------------
d="$ROOT/ac10"; proj "$d"; state "$d" Implementation L2 '- [x] unproven (AC1)'
code "$d" >/dev/null; code "$d" >/dev/null; code "$d" >/dev/null
expect "AC10 guard releases after three" "$d" 0 "released after"
# proving something resets the counter
d="$ROOT/ac10b"; proj "$d"; state "$d" Implementation L2 '- [x] unproven (AC1)' '- [x] also unproven (AC2)'
code "$d" >/dev/null; code "$d" >/dev/null
goodtest "$d/tests/Feature/HereTest.php"
state "$d" Implementation L2 '- [x] proven (AC1) — test: tests/Feature/HereTest.php' '- [x] also unproven (AC2)'
expect "AC10 a new proof resets the guard" "$d" 2 "closed with no proof"

# --- AC11: it executes nothing --------------------------------------------------------------------
d="$ROOT/ac11"; proj "$d"; mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\ntouch "%s/EXECUTED"\n' "$d" > "$d/vendor/bin/sail"; chmod +x "$d/vendor/bin/sail"
cp "$d/vendor/bin/sail" "$d/vendor/bin/php"; cp "$d/vendor/bin/sail" "$d/vendor/bin/composer"
goodtest "$d/tests/Feature/HereTest.php"
state "$d" "Done — shipped" L2 '- [x] s (AC1) — test: tests/Feature/HereTest.php'
( cd "$d" && PATH="$d/vendor/bin:$PATH" printf '{}' | bash "$HOOK" >/dev/null 2>&1 )
if [ ! -f "$d/EXECUTED" ]; then
  pass=$((pass+1)); printf '  ok   %-40s (no command ran)\n' "AC11 executes nothing"
else
  fail=$((fail+1)); printf '  FAIL %-40s a command was executed\n' "AC11 executes nothing"
fi

# --- AC12: the contract every gate here honours ---------------------------------------------------
d="$ROOT/ac12a"; mkdir -p "$d/.claude/groundwork"
printf '# Task: t\n- Mode: Implementation\n- Level: L2\n\n## Plan (slices)\n- [x] x\n' > "$d/.claude/groundwork/task-state.md"
expect "AC12 no .groundwork.json" "$d" 0
d="$ROOT/ac12b"; proj "$d"
expect "AC12 no checkpoint" "$d" 0
d="$ROOT/ac12c"; proj "$d" '{ "slice_ledger": false }'; state "$d" Implementation L2 '- [x] unproven (AC1)'
expect "AC12 gates.slice_ledger=false" "$d" 0
d="$ROOT/ac12d"; proj "$d"; state "$d" Implementation L0 '- [x] unproven (AC1)'
expect "AC12 L0 is silent" "$d" 0
d="$ROOT/ac12e"; proj "$d"; state "$d" Implementation L1 '- [x] unproven (AC1)'
expect "AC12 L1 is silent" "$d" 0
d="$ROOT/ac12f"; proj "$d" '{}' '{ "checkpoint": false }'; state "$d" Implementation L2 '- [x] unproven (AC1)'
expect "AC12 memory.checkpoint=false says so" "$d" 0 "cannot be checked"
d="$ROOT/ac12g"; proj "$d"; state "$d" Implementation L2 '- [x] unproven (AC1)'
got="$( cd "$d" && printf '{"stop_hook_active":true}' | bash "$HOOK" >/dev/null 2>&1; printf '%s' "$?" )"
if [ "$got" = "0" ]; then
  pass=$((pass+1)); printf '  ok   %-40s (exit 0)\n' "AC12 re-entry is silent"
else
  fail=$((fail+1)); printf '  FAIL %-40s want exit 0, got %s\n' "AC12 re-entry is silent" "$got"
fi
d="$ROOT/ac12h"; proj "$d"; state "$d" Implementation L2
expect "AC12 an empty plan says nothing" "$d" 0

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
