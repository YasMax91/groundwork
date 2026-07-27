#!/usr/bin/env bash
# RaDevs plugin :: executable proof for openapi-gate.sh.
# A blocking Stop gate can strand the workflow, so every branch gets a case here: it must block
# a contract change that skipped the spec, and stay silent on everything else.
# No framework — plain bash. Run: bash hooks/tests/openapi-gate.sh
set -uo pipefail

GATE="$(cd "$(dirname "$0")/.." && pwd)/openapi-gate.sh"
[ -f "$GATE" ] || { echo "gate not found: $GATE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

# expect <name> <expected-exit> <fixture-dir>
expect() {
  local name="$1" want="$2" dir="$3" got
  ( cd "$dir" && bash "$GATE" >/dev/null 2>&1 )
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-28s (exit %s)\n' "$name" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-28s (want %s, got %s)\n' "$name" "$want" "$got"
  fi
}

# fixture <dir> <openapi_on_stop> — a git repo with l5-swagger and one committed controller
fixture() {
  local d="$1" gate="$2"
  mkdir -p "$d/app/Http/Controllers" "$d/routes"
  cat > "$d/.groundwork.json" <<JSON
{ "runner": "sail", "gates": { "openapi_on_stop": $gate } }
JSON
  cat > "$d/composer.json" <<'JSON'
{ "require": { "laravel/framework": "^11.0", "darkaonline/l5-swagger": "^8.6" } }
JSON
  printf '<?php\nclass FooController {}\n' > "$d/app/Http/Controllers/FooController.php"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init )
}

touch_controller() { printf '<?php\nclass FooController { public function show() {} }\n' > "$1/app/Http/Controllers/FooController.php"; }
touch_with_annotation() {
  cat > "$1/app/Http/Controllers/FooController.php" <<'PHP'
<?php
class FooController {
    #[OA\Get(path: '/api/foo', responses: [new OA\Response(response: 200, description: 'ok')])]
    public function show() {}
}
PHP
}

echo "openapi-gate:"

# --- AC1: contract surface changed, spec untouched -> BLOCK ---
d="$ROOT/ac1"; fixture "$d" true; touch_controller "$d"
expect "AC1 contract w/o spec"     2 "$d"

# --- AC2: annotations changed in the same diff -> allow (generation skipped, no runner) ---
d="$ROOT/ac2"; fixture "$d" true; touch_with_annotation "$d"
expect "AC2 spec updated"          0 "$d"

# --- AC3: opt-out toggle ---
d="$ROOT/ac3"; fixture "$d" false; touch_controller "$d"
expect "AC3 gate disabled"         0 "$d"

# --- AC4: project without OpenAPI tooling -> silent no-op ---
d="$ROOT/ac4"; fixture "$d" true; touch_controller "$d"
cat > "$d/composer.json" <<'JSON'
{ "require": { "laravel/framework": "^11.0" } }
JSON
expect "AC4 no tooling"            0 "$d"

# --- AC5: no .groundwork.json -> not a RaDevs project ---
d="$ROOT/ac5"; fixture "$d" true; touch_controller "$d"; rm -f "$d/.groundwork.json"
expect "AC5 no config"             0 "$d"

# --- AC6: only non-contract files changed ---
d="$ROOT/ac6"; fixture "$d" true
mkdir -p "$d/app/Services"; printf '<?php\nclass FooService {}\n' > "$d/app/Services/FooService.php"
expect "AC6 non-contract change"   0 "$d"

# --- AC7: checkpoint declares the contract untouched ---
d="$ROOT/ac7"; fixture "$d" true; touch_controller "$d"
mkdir -p "$d/.claude/groundwork"
printf '# Task: refactor\n- Mode: Implementation\n- OpenAPI: n/a — internal refactor, no route touched\n' \
  > "$d/.claude/groundwork/task-state.md"
expect "AC7 declared n/a"          0 "$d"

# --- AC8: brand-new untracked controller that already carries annotations ---
d="$ROOT/ac8"; fixture "$d" true
cat > "$d/app/Http/Controllers/BarController.php" <<'PHP'
<?php
class BarController {
    #[OA\Post(path: '/api/bar', responses: [new OA\Response(response: 201, description: 'created')])]
    public function store() {}
}
PHP
expect "AC8 new documented file"    0 "$d"

# --- AC9: FormRequest change also counts as contract surface ---
d="$ROOT/ac9"; fixture "$d" true
mkdir -p "$d/app/Http/Requests"; printf '<?php\nclass StoreFooRequest {}\n' > "$d/app/Http/Requests/StoreFooRequest.php"
expect "AC9 formrequest change"     2 "$d"

# --- AC10: generation failure blocks; env failure does not ---
d="$ROOT/ac10"; fixture "$d" true; touch_with_annotation "$d"
mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\necho "Error: @OA\\\\Schema() unresolved $ref"\nexit 1\n' > "$d/vendor/bin/sail"
chmod +x "$d/vendor/bin/sail"
expect "AC10 broken generation"     2 "$d"

d="$ROOT/ac11"; fixture "$d" true; touch_with_annotation "$d"
mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\necho "Command \\"l5-swagger:generate\\" is not defined."\nexit 1\n' > "$d/vendor/bin/sail"
chmod +x "$d/vendor/bin/sail"
expect "AC11 env failure allows"    0 "$d"

d="$ROOT/ac12"; fixture "$d" true; touch_with_annotation "$d"
mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\necho "Regenerating docs"\nexit 0\n' > "$d/vendor/bin/sail"
chmod +x "$d/vendor/bin/sail"
expect "AC12 clean generation"      0 "$d"

# --- W11-AC3: on a runner:host project the generation step must actually RUN, not skip.
# Before Wave 11 the command defaulted to Sail, was unreachable, and this half silently no-opped.
d="$ROOT/ac13"; fixture "$d" true; touch_with_annotation "$d"
cat > "$d/.groundwork.json" <<'JSON'
{ "runner": "host", "gates": { "openapi_on_stop": true },
  "commands": { "openapi_generate": "./gen.sh" } }
JSON
printf '#!/bin/sh\necho "Error: @OA\\\\Schema() unresolved $ref"\nexit 1\n' > "$d/gen.sh"; chmod +x "$d/gen.sh"
expect "AC13 host generation runs"  2 "$d"

d="$ROOT/ac14"; fixture "$d" true; touch_with_annotation "$d"
cat > "$d/.groundwork.json" <<'JSON'
{ "runner": "host", "gates": { "openapi_on_stop": true },
  "commands": { "openapi_generate": "./gen.sh" } }
JSON
printf '#!/bin/sh\necho "Regenerating docs"\nexit 0\n' > "$d/gen.sh"; chmod +x "$d/gen.sh"
expect "AC14 host clean generation" 0 "$d"

# --- an explicit override wins over the runner's availability (runner:sail, no Sail binary) ---
d="$ROOT/ac15"; fixture "$d" true; touch_with_annotation "$d"
cat > "$d/.groundwork.json" <<'JSON'
{ "runner": "sail", "gates": { "openapi_on_stop": true },
  "commands": { "openapi_generate": "./gen.sh" } }
JSON
printf '#!/bin/sh\necho "Error: @OA\\\\Schema() unresolved $ref"\nexit 1\n' > "$d/gen.sh"; chmod +x "$d/gen.sh"
expect "AC15 override under sail"   2 "$d"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
