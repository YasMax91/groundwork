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
expect "AC11 env failure reports"   1 "$d"

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

# --- W12-AC11: a comment-only edit cannot change the contract -> must not block (L0 typo fix) ---
d="$ROOT/ac16"; fixture "$d" true
cat > "$d/app/Http/Controllers/FooController.php" <<'PHP'
<?php
// fixed a typo in this comment
class FooController {}
PHP
expect "AC16 comment-only allowed"  0 "$d"

# but a real code change in the same file still blocks
d="$ROOT/ac17"; fixture "$d" true
cat > "$d/app/Http/Controllers/FooController.php" <<'PHP'
<?php
// a comment too
class FooController { public function show() {} }
PHP
expect "AC17 code change blocks"    2 "$d"

# and an annotation inside a comment block is NOT "comment-only"
d="$ROOT/ac18"; fixture "$d" true
cat > "$d/app/Http/Controllers/FooController.php" <<'PHP'
<?php
/**
 * @OA\Get(path="/api/foo")
 */
class FooController {}
PHP
expect "AC18 annotation counts"     0 "$d"

# --- comment-only detection must not be fooled (found by adversarial audit of Wave 12) ---

# N1: a PHP 8 attribute starts with '#' but is CODE — a route/middleware/policy change
# APPEND ONLY — no code line is removed, so the diff is purely additions (the audit's exact case)
d="$ROOT/ac19"; fixture "$d" true
printf "#[Delete('/api/foo/{id}')]\n" >> "$d/app/Http/Controllers/FooController.php"
expect "AC19 php8 attribute blocks"  2 "$d"

# N2: a line that OPENS with /* but carries real code after it
d="$ROOT/ac20"; fixture "$d" true
printf '/* new endpoint */ public function destroy($id) {}\n' >> "$d/app/Http/Controllers/FooController.php"
expect "AC20 code after /* blocks"   2 "$d"

# N3: a comment-only edit must not switch OFF the broken-generation half of the gate
d="$ROOT/ac21"; fixture "$d" true
printf '// just a comment touch\n' >> "$d/app/Http/Controllers/FooController.php"
mkdir -p "$d/app/Schemas"
cat > "$d/app/Schemas/FooSchema.php" <<'PHP'
<?php
#[OA\Schema(schema: 'Foo')]
class FooSchema {}
PHP
mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\necho "Error: @OA\\\\Schema() unresolved $ref"\nexit 1\n' > "$d/vendor/bin/sail"
chmod +x "$d/vendor/bin/sail"
expect "AC21 broken spec still caught" 2 "$d"

# a genuine multi-line doc comment is still comment-only
d="$ROOT/ac22"; fixture "$d" true
printf '/**\n * Handles orders.\n */\n' >> "$d/app/Http/Controllers/FooController.php"
expect "AC22 docblock allowed"       0 "$d"

# B2: trailing /* … */ made the greedy one-line-comment pattern swallow real code
d="$ROOT/ac23"; fixture "$d" true
printf "/* legacy */ Route::get('/reports', [R::class,'i']); /* new */\n" >> "$d/app/Http/Controllers/FooController.php"
expect "AC23 greedy block bypass"    2 "$d"

# B4: a closing */ line that carries code after it
d="$ROOT/ac24"; fixture "$d" true
printf '/**\n * Reports.\n */ Route::post(%s, [R::class, %s]);\n' "'/reports'" "'store'" >> "$d/app/Http/Controllers/FooController.php"
expect "AC24 closer-with-code bypass" 2 "$d"

# --- #4: the contract gate must not be satisfied by a bare token or an empty yaml ---
d="$ROOT/ac25"; fixture "$d" true; touch_controller "$d"
printf '<?php\n// TODO OA\\ later\n' > "$d/unrelated.php"
expect "AC25 bare OA token rejected" 2 "$d"

d="$ROOT/ac26"; fixture "$d" true; touch_controller "$d"
: > "$d/swagger-notes.yaml"
expect "AC26 empty yaml rejected"    2 "$d"

d="$ROOT/ac27"; fixture "$d" true; touch_controller "$d"
printf 'openapi: 3.0.0\npaths:\n  /api/foo:\n    get: {}\n' > "$d/openapi.yaml"
expect "AC27 real yaml accepted"     0 "$d"

# --- M10 (was covered by NO test): a spec that generates with warnings must block ---
d="$ROOT/ac28"; fixture "$d" true; touch_with_annotation "$d"
mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\necho "Multiple @OA\\Get() with the same operationId \"getOrders\""\nexit 0\n' > "$d/vendor/bin/sail"
chmod +x "$d/vendor/bin/sail"
expect "AC28 duplicate operationId"  2 "$d"

d="$ROOT/ac29"; fixture "$d" true; touch_with_annotation "$d"
mkdir -p "$d/vendor/bin"
printf '#!/bin/sh\necho "\$ref \"#/components/schemas/OrderResource\" not found"\nexit 0\n' > "$d/vendor/bin/sail"
chmod +x "$d/vendor/bin/sail"
expect "AC29 unresolved ref"         2 "$d"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
