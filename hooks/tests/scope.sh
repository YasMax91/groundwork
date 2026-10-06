#!/usr/bin/env bash
# Groundwork plugin :: executable proof for wave 37 — targeted tests while working, the whole suite before
# a shared push. test-select.py · test-gate.sh scope · suite-record.py · push-gate.py.
# Run: bash hooks/tests/scope.sh
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-50s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-50s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }

# a bare origin + a project whose "phpunit" is a stub that logs its arguments
O="$ROOT/origin.git"; git init -q --bare -b development "$O"
P="$ROOT/shop"; git clone -q "$O" "$P" 2>/dev/null
cd "$P" && git config user.email t@t && git config user.name t
mkdir -p app/Services tests/Feature tests/Unit database/migrations config routes bin
printf '<?php class OrderService {}\n' > app/Services/OrderService.php
printf '<?php class Mailer {}\n' > app/Services/Mailer.php
printf '<?php return ["ttl" => 30];\n' > config/promo.php
printf "<?php Schema::create('coupons', function () {});\n" > database/migrations/2026_01_01_create_coupons.php
printf "<?php Route::get('/shop/basket', 'X')->name('basket.show');\n" > routes/web.php
printf '<?php class OrderServiceTest { function t() { new OrderService; } }\n' > tests/Feature/OrderServiceTest.php
printf "<?php class CouponTest { function t() { \$this->assertDatabaseHas('coupons', []); } }\n" > tests/Feature/CouponTest.php
printf "<?php class PromoTest { function t() { config('promo.ttl'); } }\n" > tests/Unit/PromoTest.php
printf "<?php class BasketTest { function t() { route('basket.show'); } }\n" > tests/Feature/BasketTest.php
printf '<?php class UnrelatedTest {}\n' > tests/Unit/UnrelatedTest.php
printf '#!/bin/sh\necho "$@" >> "%s/runs.log"\necho "Tests:    3 passed (5 assertions)"\n' "$ROOT" > bin/phpunit; chmod +x bin/phpunit
printf '{ "runner": "host", "commands": { "test": "./bin/phpunit" } }\n' > .groundwork.json
git add -A && git commit -qm init && git push -q -u origin development 2>/dev/null

sel() { python3 "$HOOKS/test-select.py" | tr '\n' ' ' | sed 's/ $//'; }
gate() { : > "$ROOT/runs.log"; printf '{}' | bash "$HOOKS/test-gate.sh" >/dev/null 2>"$ROOT/gate.err"; echo "rc=$? args=$(tr -d '\n' < "$ROOT/runs.log")"; }

echo "scope:"
eq "nothing changed: nothing selected"           ""                                   "$(sel)"
printf '<?php class OrderService { function x() {} }\n' > app/Services/OrderService.php
eq "a changed class selects the tests naming it"  "tests/Feature/OrderServiceTest.php" "$(sel)"
eq "the gate runs only those files"              "rc=0 args=tests/Feature/OrderServiceTest.php" "$(gate)"
git checkout -q -- . ; printf "<?php Schema::create('coupons', function () { /* +col */ });\n" > database/migrations/2026_01_01_create_coupons.php
eq "a migration selects tests naming its table"   "tests/Feature/CouponTest.php"       "$(sel)"
git checkout -q -- . ; printf '<?php return ["ttl" => 60];\n' > config/promo.php
eq "a config file selects tests reading its keys" "tests/Unit/PromoTest.php"          "$(sel)"
git checkout -q -- . ; printf "<?php Route::get('/shop/basket', 'Y')->name('basket.show');\n" > routes/web.php
eq "a routes file selects tests naming its routes" "tests/Feature/BasketTest.php"      "$(sel)"
git checkout -q -- . ; printf '<?php class UnrelatedTest { function t() {} }\n' > tests/Unit/UnrelatedTest.php
eq "a changed test selects itself"                "tests/Unit/UnrelatedTest.php"       "$(sel)"
git checkout -q -- . ; printf '<?php class Mailer { function y() {} }\n' > app/Services/Mailer.php
eq "no test names it: nothing selected"           ""                                   "$(sel)"
eq "…and the gate runs nothing, says so"          "rc=0 args="                         "$(gate)"
grep -q 'none run now' "$ROOT/gate.err"; eq "…visibly" 0 $?
printf '{ "runner": "host", "commands": { "test": "./bin/phpunit" }, "gates": { "test_scope": "full" } }\n' > .groundwork.json
eq "test_scope=full: the whole suite, no paths"   "rc=0 args="                         "$(gate)"
[ -s "$ROOT/runs.log" ] || true
git checkout -q -- .groundwork.json

# --- committed but unpushed work stays covered ---
printf '<?php class OrderService { function z() {} }\n' > app/Services/OrderService.php; git commit -qam "work"
eq "unpushed commit still selects its tests"      "tests/Feature/OrderServiceTest.php" "$(sel)"

# --- push gate ---
push() { local out; out="$(jq -nc --arg c "$P" --arg cmd "$1" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}' \
  | python3 "$HOOKS/push-gate.py")"; [ -z "$out" ] && echo allow || printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; }
eq "push to development without a full run: deny" deny  "$(push 'git push origin development')"
eq "HEAD:development spec: deny"                  deny  "$(push 'git push origin HEAD:development')"
eq "push of a feature branch: allow"              allow "$(push 'git push -u origin feat/x')"
eq "gh pr merge without a full run: deny"         deny  "$(push 'gh pr merge 12 --squash')"
eq "not a push: allow"                            allow "$(push 'git status && git log -1')"
python3 "$HOOKS/suite-record.py" --record >/dev/null
eq "after a green full run on this tree: allow"   allow "$(push 'git push origin development')"
printf '<?php class OrderService { function w() {} }\n' > app/Services/OrderService.php; git commit -qam "more"
eq "new code after the run: deny again"           deny  "$(push 'git push origin development')"

# --- a green run on the working tree counts for the commit made from it ---
printf '<?php class OrderService { function v() {} }\n' > app/Services/OrderService.php
python3 "$HOOKS/suite-record.py" --record >/dev/null
git commit -qam "same content as the green run"
eq "commit of the tree that passed: allow"        allow "$(push 'git push origin development')"

# --- the gate's own full run records a pass; an agent's full run is recorded from its output ---
printf '<?php class OrderService { function u() {} }\n' > app/Services/OrderService.php
printf '{ "runner": "host", "commands": { "test": "./bin/phpunit" }, "gates": { "test_scope": "full" } }\n' > .groundwork.json
git commit -qam "u, with a full-scope config"; gate >/dev/null
eq "the gate's green full run is recorded"        allow "$(push 'git push origin development')"
printf '<?php class OrderService { function t2() {} }\n' > app/Services/OrderService.php; git commit -qam "t2"
jq -nc --arg c "$P" '{cwd:$c, tool_name:"Bash", tool_input:{command:"./vendor/bin/sail artisan test --compact"},
  tool_response:{stdout:"  Tests:    4112 passed (13000 assertions)\n  Duration: 301.2s", stderr:""}}' | python3 "$HOOKS/suite-record.py"
eq "an agent's green full run is recorded"        allow "$(push 'git push origin development')"
printf '<?php class OrderService { function t3() {} }\n' > app/Services/OrderService.php; git commit -qam "t3"
jq -nc --arg c "$P" '{cwd:$c, tool_name:"Bash", tool_input:{command:"./vendor/bin/sail artisan test --filter=Order"},
  tool_response:{stdout:"  Tests:    4 passed (9 assertions)", stderr:""}}' | python3 "$HOOKS/suite-record.py"
eq "a filtered run is not a full run"             deny  "$(push 'git push origin development')"
jq -nc --arg c "$P" '{cwd:$c, tool_name:"Bash", tool_input:{command:"./vendor/bin/sail artisan test"},
  tool_response:{stdout:"  Tests:    2 failed, 4110 passed (13000 assertions)", stderr:""}}' | python3 "$HOOKS/suite-record.py"
eq "a red full run is not recorded"               deny  "$(push 'git push origin development')"

printf '{ "runner": "host", "commands": { "test": "./bin/phpunit", "test_full": "./bin/phpunit --parallel --processes=4" } }\n' > .groundwork.json
reason="$(jq -nc --arg c "$P" '{cwd:$c, tool_name:"Bash", tool_input:{command:"git push origin development"}}' | python3 "$HOOKS/push-gate.py" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
printf '%s' "$reason" | grep -q -- '--parallel --processes=4'; eq "push-gate names commands.test_full" 0 $?
: > "$ROOT/runs.log"; printf '{ "runner": "host", "commands": { "test": "./bin/phpunit", "test_full": "./bin/phpunit --parallel" }, "gates": { "test_scope": "full" } }\n' > .groundwork.json
printf '{}' | bash "$HOOKS/test-gate.sh" >/dev/null 2>&1; eq "full scope runs commands.test_full" "--parallel" "$(tr -d '\n' < "$ROOT/runs.log")"
printf '{ "runner": "host", "commands": { "test": "./bin/phpunit" }, "gates": { "full_suite_before_push": false } }\n' > .groundwork.json
eq "opt-out honoured"                             allow "$(push 'git push origin development')"

echo; echo "  passed: $pass, failed: $fail"; [ "$fail" -eq 0 ]
