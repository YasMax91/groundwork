#!/usr/bin/env bash
# Groundwork plugin :: executable proof for waves 37-38 — the close tests while working, the change's tests
# before a shared push, the whole suite only when something shared changed.
# gw_tests.py · test-select.py · test-gate.sh (scope, budget, watchdog, records) · suite-record.py ·
# push-gate.py · test-run.py. Run: bash hooks/tests/scope.sh
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-56s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-56s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }
has() { if printf '%s' "$3" | grep -q -- "$2"; then pass=$((pass+1)); printf '  ok   %-56s\n' "$1"
        else fail=$((fail+1)); printf '  FAIL %-56s no "%s" in: %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 300)"; fi; }

# --- a bare origin + a project whose "phpunit" is a stub: it logs its arguments, writes a JUnit log when asked,
#     and fails / drops the connection once / sleeps as $ROOT/control.json says ------------------------------
O="$ROOT/origin.git"; git init -q --bare -b development "$O"
P="$ROOT/shop"; git clone -q "$O" "$P" 2>/dev/null
cd "$P" && git config user.email t@t && git config user.name t
mkdir -p app/Services app/Models app/Http/Controllers app/Http/Requests tests/Feature tests/Unit \
         database/migrations config routes bin lang/en bootstrap docs/ai/frontend/handoff
w() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
# A fixture edited in place, through a temp file: `sed -i ''` is BSD sed's form — GNU sed reads the '' as the script
# and the expression as a file name, so on Linux the fixture stayed as written and every check after it ran on an
# unchanged tree. An edit that changes nothing is a failure of its own, never a silent no-op.
edit() { if sed "$1" "$2" > "$ROOT/edit.tmp" && ! cmp -s "$ROOT/edit.tmp" "$2"; then cat "$ROOT/edit.tmp" > "$2"
         else fail=$((fail+1)); printf '  FAIL %-56s %s\n' "the fixture edit changed nothing" "$2: $1"; fi; }
w app/Services/OrderService.php '<?php
class OrderService {
    public function total() { return 1; }
    public function refund() { return 2; }
}'
w app/Services/Mailer.php '<?php class Mailer { function send() {} }'
w app/Models/Product.php '<?php
class Product {
    public function priceFor($q) { return 1; }
    public function label() { return "x"; }
}'
w app/Http/Controllers/OrderController.php '<?php
class OrderController {
    public function store(StoreOrderRequest $request) { return 1; }
    public function index() { return 2; }
}'
w app/Http/Requests/StoreOrderRequest.php '<?php
class StoreOrderRequest {
    public function rules() { return []; }
}'
w routes/web.php "<?php
Route::get('/shop/basket', [BasketController::class, 'show'])->name('basket.show');
Route::post('/orders/checkout', [OrderController::class, 'store'])->name('orders.checkout');
Route::get('/orders/history', [OrderController::class, 'index'])->name('orders.history');
Route::put('/update', [ProfileController::class, 'update'])->name('update');"
w config/promo.php "<?php return [
    'ttl' => 30,
    'cap' => 5,
];"
w lang/en/custom.php "<?php return [
    'greeting' => 'Hi',
    'farewell' => 'Bye',
];"
w database/migrations/2026_01_01_create_coupons.php "<?php
Schema::create('coupons', function (\$table) {
    \$table->id();
});"
w bootstrap/app.php '<?php return 1;'
w composer.lock '{"packages": []}'
w docs/ai/frontend/kits.md '# Kits'
w docs/ai/frontend/handoff/a.md '# A'
w docs/other.md '# Other'
w .gitignore 'storage/'
t() { w "tests/$1.php" "<?php class $(basename "$1") { function t() { $2 } }"; }
t Feature/OrderServiceTest        '(new OrderService)->total();'
t Feature/OrderServiceRefundTest  '(new OrderService)->refund();'
t Feature/ReportTest              '(new OrderService)->total();'
t Feature/AuditTest               'new OrderService;'
t Feature/CouponTest              "\$this->assertDatabaseHas('coupons', []);"
t Feature/DiscountColumnTest      "\$this->assertDatabaseHas('coupons', ['discount_cents' => 1]);"
t Unit/PromoTest                  "config('promo.ttl');"
t Unit/PromoCapTest               "config('promo.cap');"
t Feature/BasketTest              "route('basket.show');"
t Feature/CheckoutTest            "\$this->postJson('/orders/checkout', []);"
t Feature/HistoryTest             "\$this->getJson(route('orders.history'));"
t Unit/UpdateWordTest             "\$x->update(); \$this->put('/update');"
t Unit/CustomKeyTest              "__('custom.greeting');"
t Unit/CustomWordTest             '// a custom thing'
t Feature/KitsDocTest             "file_get_contents(base_path('docs/ai/frontend/kits.md'));"
t Feature/HandoffDocsTest         "glob(base_path('docs/ai/frontend/handoff/*.md'));"
t Unit/ProductTest                'new Product;'
t Unit/CartTest                   '(new Product)->priceFor(1);'
t Unit/WishlistTest               'new Product;'
t Unit/UnrelatedTest              'return;'
w phpunit.xml '<phpunit><testsuites>
    <testsuite name="Unit"><directory suffix="Test.php">./tests/Unit</directory></testsuite>
    <testsuite name="Feature"><directory suffix="Test.php">./tests/Feature</directory></testsuite>
</testsuites><php><env name="DB_DATABASE" value="shop_test"/></php></phpunit>'
cat > bin/phpunit <<PY
#!/usr/bin/env python3
import glob, json, os, sys, time
ROOT = "$ROOT"
args = sys.argv[1:]
junit = next((a.split("=", 1)[1] for a in args if a.startswith("--log-junit=")), "")
open(os.path.join(ROOT, "runs.log"), "a").write(" ".join(a for a in args if not a.startswith("--log-junit")) + "\n")
try:
    ctl = json.load(open(os.path.join(ROOT, "control.json")))
except Exception:
    ctl = {}
time.sleep(ctl.get("sleep", 0))
files = [a for a in args if a.startswith("tests/")] or sorted(glob.glob("tests/**/*Test.php", recursive=True))
cases, failed = [], 0
for f in files:
    msg, mode = "", ctl.get(f, "pass")
    marker = os.path.join(ROOT, "conn-" + f.replace("/", "_"))
    if mode == "fail":
        msg = "Failed asserting that false is true."
    elif mode == "conn-once" and not os.path.exists(marker):
        open(marker, "w").close()
        msg = "SQLSTATE[HY000] [2002] Connection refused"
    failed += 1 if msg else 0
    cases.append((f, msg))
if junit:
    os.makedirs(os.path.dirname(junit), exist_ok=True)
    with open(junit, "w") as fh:
        fh.write('<?xml version="1.0"?><testsuites><testsuite name="all">')
        for f, msg in cases:
            fh.write('<testcase name="t" file="%s" time="0.5">%s</testcase>'
                     % (os.path.abspath(f), '<failure message="%s">%s</failure>' % (msg, msg) if msg else ""))
        fh.write("</testsuite></testsuites>")
n = len(cases)
print("  Tests:    %s%d passed (%d assertions)" % ("%d failed, " % failed if failed else "", n - failed, n))
sys.exit(1 if failed else 0)
PY
chmod +x bin/phpunit
cfg() { local g=""; [ -n "${2:-}" ] && g=", \"gates\": { $2 }"
        printf '{ "runner": "host", "commands": { "test": "./bin/phpunit"%s }%s }\n' "${1:-}" "$g" > .groundwork.json; }
cfg
git add -A && git commit -qm init && git push -q -u origin development 2>/dev/null

reset_tree() { git checkout -q -- . && git clean -qfd -e storage >/dev/null; }
reset_records() { rm -rf "$(git rev-parse --git-common-dir)/groundwork"; rm -f "$ROOT"/conn-* "$ROOT/control.json"; }
sel() { python3 "$HOOKS/test-select.py" | tr '\n' ' ' | sed 's/ $//'; }
selj() { python3 "$HOOKS/test-select.py" --json | jq -r ".$1 | join(\" \")"; }
gate() { : > "$ROOT/runs.log"; printf '{}' | bash "$HOOKS/test-gate.sh" >/dev/null 2>"$ROOT/gate.err"; echo "rc=$? args=$(sed '/^$/d' "$ROOT/runs.log" | tr '\n' '|' | sed 's/|$//')"; }
push() { local out; out="$(jq -nc --arg c "$P" --arg cmd "$1" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}' \
  | python3 "$HOOKS/push-gate.py")"; [ -z "$out" ] && echo allow || printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; }
reason() { jq -nc --arg c "$P" --arg cmd "$1" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}' | python3 "$HOOKS/push-gate.py" \
  | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
post() { jq -nc --arg c "$P" --arg cmd "$1" --arg out "$2" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd},
  tool_response:{stdout:$out, stderr:""}}' | python3 "$HOOKS/suite-record.py"; }
tr_run() { : > "$ROOT/runs.log"; GW_RETRY_PAUSE=0 python3 "$HOOKS/test-run.py" "$@" > "$ROOT/tr.out" 2>&1; echo $?; }
F=tests/Feature; U=tests/Unit

echo "selection — the close circle and the wide one:"
eq "nothing changed: nothing selected"                    ""   "$(sel)"
edit 's/return 2;/return 3;/' app/Services/OrderService.php            # inside refund()
eq "a class: its own tests, by name"                      "$F/OrderServiceRefundTest.php $F/OrderServiceTest.php" "$(sel)"
eq "…tests merely naming it are the wide circle"          "$F/AuditTest.php $F/ReportTest.php" "$(selj wide)"
reset_tree; edit 's/return 1;/return 9;/' app/Services/OrderService.php   # inside total()
eq "a changed method adds the tests calling it"           "$F/OrderServiceRefundTest.php $F/OrderServiceTest.php $F/ReportTest.php" "$(sel)"
reset_tree; edit 's/return 1;/return 9;/' app/Models/Product.php
eq "a model's method: its tests and its callers"          "$U/ProductTest.php $U/CartTest.php" "$(sel)"
eq "…a model's mere mentions stay wide"                   "$U/WishlistTest.php" "$(selj wide)"
reset_tree; edit "s/'show'\]/'view']/" routes/web.php
eq "a routes file: only the changed route's tests"        "$F/BasketTest.php" "$(sel)"
reset_tree; edit "s/'update'\])/'save'])/" routes/web.php
eq "a route named only by a common word selects nothing" "" "$(sel)"
reset_tree; edit 's/return 1;/return 7;/' app/Http/Controllers/OrderController.php
eq "a controller method: the tests of its route"          "$F/CheckoutTest.php" "$(sel)"
reset_tree; edit 's/return \[\];/return ["a" => 1];/' app/Http/Requests/StoreOrderRequest.php
eq "a form request: no close test…"                       "" "$(sel)"
eq "…the route of the action using it is wide"            "$F/CheckoutTest.php" "$(selj wide)"
reset_tree; edit "s/'ttl' => 30/'ttl' => 60/" config/promo.php
eq "a config file: only the changed key's tests"          "$U/PromoTest.php" "$(sel)"
reset_tree; edit "s/'Hi'/'Hello'/" lang/en/custom.php
eq "a lang file: the key, not the file's name as a word"  "$U/CustomKeyTest.php" "$(sel)"
reset_tree; edit 's/\$table->id();/$table->id(); $table->integer("discount_cents")->nullable();/' database/migrations/2026_01_01_create_coupons.php
eq "a migration: no close test of its own"                 "" "$(sel)"
eq "…tests naming its table or new column are wide"       "$F/CouponTest.php $F/DiscountColumnTest.php" "$(selj wide)"
eq "…and a column on its own new table is not shared"     "" "$(selj shared)"
reset_tree; w database/migrations/2026_02_01_drop_note.php "<?php Schema::table('orders', function (\$table) { \$table->dropColumn('note'); });"
eq "a migration dropping a column is shared"              "database/migrations/2026_02_01_drop_note.php" "$(selj shared)"
reset_tree; w database/migrations/2026_02_02_code.php "<?php
Schema::table('orders', function (\$table) {
    \$table->string('code');
});"
eq "a NOT NULL column on an existing table is shared"     "database/migrations/2026_02_02_code.php" "$(selj shared)"
reset_tree; w database/migrations/2026_02_03_code.php "<?php
Schema::table('orders', function (\$table) {
    \$table->string('code')->nullable();
});"
eq "…a nullable one is not"                               "" "$(selj shared)"
reset_tree; printf "Route::middleware('auth')->group(function () {});\n" >> routes/web.php
eq "a routes line changing middleware is shared"          "routes/web.php" "$(selj shared)"
reset_tree; printf '<?php return 2;\n' > bootstrap/app.php
eq "bootstrap/app.php is shared…"                         "bootstrap/app.php" "$(selj shared)"
eq "…and never a needle named 'app'"                      "" "$(selj wide)"
reset_tree; printf '{"packages": [1]}\n' > composer.lock
eq "composer.lock is shared"                              "composer.lock" "$(selj shared)"
reset_tree; printf '<?php abstract class TestCase { function setUp() {} }\n' > tests/TestCase.php
eq "the base test class is shared…"                       "tests/TestCase.php" "$(selj shared)"
eq "…and selects no close test (every test uses it)"     "" "$(sel)"
reset_tree; for i in $(seq 1 25); do t "Unit/Bulk${i}Test" '(new Mailer)->send();'; done
git add -A >/dev/null; git commit -qm "25 tests calling Mailer::send"
printf '<?php class Mailer { function send() { return 5; } }\n' > app/Services/Mailer.php
eq "a needle in more than 5% of tests (min 20) is wide" "" "$(python3 "$HOOKS/test-select.py" --base HEAD | tr '\n' ' ' | sed 's/ $//')"
eq "…all 25 of them run before the push"                  "25" "$(python3 "$HOOKS/test-select.py" --json --base HEAD | jq '.wide | length')"
git checkout -q -- . ; git reset -q --hard HEAD~1
reset_tree; printf '# Kits v2\n' > docs/ai/frontend/kits.md
eq "a document: the test that reads it"                   "$F/KitsDocTest.php" "$(sel)"
reset_tree; printf '# B\n' > docs/ai/frontend/handoff/b.md
eq "a document matched by a test's glob"                  "$F/HandoffDocsTest.php" "$(sel)"
reset_tree; printf '# Other v2\n' > docs/other.md
eq "a document no test reads: nothing"                    "" "$(sel)"
reset_tree; printf '<?php class UnrelatedTest { function t() { return 1; } }\n' > tests/Unit/UnrelatedTest.php
eq "a changed test selects itself"                        "$U/UnrelatedTest.php" "$(sel)"
reset_tree; printf '<?php class Mailer { function send() { return 1; } }\n' > app/Services/Mailer.php
eq "no test names it: nothing selected"                   "" "$(sel)"
eq "…and the Stop gate runs nothing, says so"             "rc=0 args=" "$(gate)"
has "…visibly"                                            "none run now" "$(cat "$ROOT/gate.err")"

echo "the Stop gate — budget, records, watchdog:"
reset_tree; reset_records; edit 's/return 1;/return 9;/' app/Services/OrderService.php
eq "runs the close circle only"                           "rc=0 args=$F/OrderServiceRefundTest.php $F/OrderServiceTest.php $F/ReportTest.php" "$(gate)"
eq "the same code again: nothing re-run"                  "rc=0 args=" "$(gate)"
has "…and it says why"                                    "already passed on this exact code" "$(cat "$ROOT/gate.err")"
reset_records; d="$(git rev-parse --git-common-dir)/groundwork"; mkdir -p "$d"
printf '{"%s": 100, "%s": 100, "%s": 100}' "$F/OrderServiceRefundTest.php" "$F/OrderServiceTest.php" "$F/ReportTest.php" > "$d/test-durations.json"
cfg '' '"test_budget_seconds": 150'
eq "a budget: the closest file that fits"                 "rc=0 args=$F/OrderServiceRefundTest.php" "$(gate)"
has "…the rest is named and left to the push check"       "2 more close tests did not fit the 150 s budget" "$(cat "$ROOT/gate.err")"
reset_records; cfg '' '"test_budget_seconds": 5'; printf '{"sleep": 30}' > "$ROOT/control.json"
start=$(date +%s); r="$(gate)"; took=$(( $(date +%s) - start ))
[ "${r%% *}" = "rc=1" ] && [ "$took" -lt 20 ]; eq "a run past twice the budget is stopped, not killed silently" 0 $?
has "…and says nothing was verified"                      "NOTHING WAS VERIFIED" "$(cat "$ROOT/gate.err")"
reset_records; cfg; mkdir -p storage/framework/testing; printf '{"%s": "fail"}' "$F/OrderServiceTest.php" > "$ROOT/control.json"
eq "a red run blocks"                                     "rc=2 args=$F/OrderServiceRefundTest.php $F/OrderServiceTest.php $F/ReportTest.php" "$(gate)"
rm -f "$ROOT/control.json"
eq "…its green files are remembered: only the red one runs again" "rc=0 args=$F/OrderServiceTest.php" "$(gate)"
[ -z "$(ls storage/framework/testing 2>/dev/null)" ]; eq "…and the JUnit logs are cleaned up" 0 $?
dur="$(jq -r --arg f "$F/ReportTest.php" '.[$f]' "$(git rev-parse --git-common-dir)/groundwork/test-durations.json")"
eq "…their durations are recorded"                        "0.5" "$dur"
rm -rf storage
reset_records
post "./vendor/bin/sail artisan test --compact $F/OrderServiceTest.php $F/ReportTest.php" "  Tests:    2 passed (4 assertions)"
eq "an agent's green run of named files is remembered"    "rc=0 args=$F/OrderServiceRefundTest.php" "$(gate)"
reset_records
post "./vendor/bin/sail artisan test --filter=total" "  Tests:    3 passed (4 assertions)"
eq "…a --filter run is not"                               "rc=0 args=$F/OrderServiceRefundTest.php $F/OrderServiceTest.php $F/ReportTest.php" "$(gate)"
reset_records
post "./vendor/bin/sail artisan test tests/Feature" "  Tests:    9 passed (9 assertions)"
eq "…a folder run counts for every test in it"            "rc=0 args=" "$(gate)"
cfg '' '"test_scope": "full"'
eq "test_scope=full: the whole suite, no paths"           "rc=0 args=" "$(gate)"
cfg ', "test_full": "./bin/phpunit --parallel"' '"test_scope": "full"'
eq "…and it runs commands.test_full"                      "rc=0 args=--parallel" "$(gate)"
cfg; reset_tree

echo "the push check — what changed since verified code:"
reset_records
eq "a feature-branch push: always allowed"                allow "$(push 'git push -u origin feat/x')"
eq "not a push: allowed"                                  allow "$(push 'git status && git log -1')"
eq "no green whole run yet: deny"                         deny  "$(push 'git push origin development')"
cfg ', "test_full": "./bin/phpunit --parallel --processes=4"'
has "…naming the runner"                                  "test-run.py\" --for-push development" "$(reason 'git push origin development')"
has "…and the whole-suite command it will use"            "--parallel --processes=4" "$(reason 'git push origin development')"
eq "HEAD:development spec: deny"                          deny  "$(push 'git push origin HEAD:development')"
eq "gh pr merge: deny"                                    deny  "$(push 'gh pr merge 12 --squash')"
cfg; git commit -qam "config" 2>/dev/null
python3 "$HOOKS/suite-record.py" --record >/dev/null
eq "after a green whole run on this code: allow"          allow "$(push 'git push origin development')"
printf '# Other v2\n' > docs/other.md; git commit -qam "docs"
eq "a document no test reads: allowed with no run"        allow "$(push 'git push origin development')"
printf '# Kits v2\n' > docs/ai/frontend/kits.md; git commit -qam "kits doc"
eq "a document a test reads: deny"                        deny  "$(push 'git push origin development')"
has "…naming that test"                                   "KitsDocTest" "$(reason 'git push origin development')"
post "./vendor/bin/sail artisan test $F/KitsDocTest.php" "  Tests:    1 passed (1 assertions)"
eq "…allowed once it passed on this code"                 allow "$(push 'git push origin development')"
edit 's/return 2;/return 5;/' app/Services/OrderService.php; git commit -qam "refund"
eq "a class change: deny until its tests pass"            deny  "$(push 'git push origin development')"
eq "test-run.py --for-push: green, exit 0"                0     "$(tr_run --for-push HEAD)"
eq "…it ran close + wide, not the suite"                  "$F/OrderServiceRefundTest.php $F/OrderServiceTest.php $F/AuditTest.php $F/ReportTest.php" "$(sed '/^$/d' "$ROOT/runs.log")"
has "…and says so"                                        "RECORDED" "$(cat "$ROOT/tr.out")"
eq "…the push is allowed"                                 allow "$(push 'git push origin development')"
printf '<?php class Mailer { function send() { return 2; } }\n' > app/Services/Mailer.php; git commit -qam "mailer"
eq "the chain: no test names the change, allowed"         allow "$(push 'git push origin development')"
printf '{"packages": [2]}\n' > composer.lock; git commit -qam "deps"
eq "a shared file: deny, the whole suite"                 deny  "$(push 'git push origin development')"
has "…naming the shared file"                             "composer.lock" "$(reason 'git push origin development')"
eq "test-run.py --for-push runs the whole suite"          0     "$(tr_run --for-push HEAD)"
eq "…the push is allowed"                                 allow "$(push 'git push origin development')"
git push -q origin development 2>/dev/null
d="$(git rev-parse --git-common-dir)/groundwork"
python3 - "$d" <<'PY'
import json, os, sys, time
d = sys.argv[1]
for sub in ("suite-passes", "verified"):
    for f in os.listdir(os.path.join(d, sub)):
        p = os.path.join(d, sub, f); r = json.load(open(p))
        for k in ("time", "root_time"):
            if k in r: r[k] = int(time.time()) - 25 * 3600
        json.dump(r, open(p, "w"))
PY
printf '<?php class Mailer { function send() { return 3; } }\n' > app/Services/Mailer.php; git commit -qam "mailer 3"
eq "a whole run older than a day: deny"                   deny  "$(push 'git push origin development')"
has "…and it says so"                                     "no green whole run in the last 24 hours" "$(reason 'git push origin development')"
cfg '' '"full_suite_before_push": "always"'; git commit -qam "always"
python3 "$HOOKS/suite-record.py" --record >/dev/null
printf '# Other v3\n' > docs/other.md; git commit -qam "docs again"
eq "\"always\": even a document needs the whole suite"    deny  "$(push 'git push origin development')"
cfg '' '"full_suite_before_push": false'
eq "false: off"                                           allow "$(push 'git push origin development')"
cfg; git commit -qam "back to default"

echo "a lane's run is the commit's run:"
python3 "$HOOKS/suite-record.py" --record >/dev/null
edit 's/shop_test/shop_test_lane1/' phpunit.xml; git update-index --skip-worktree phpunit.xml
eq "skip-worktree phpunit.xml: the working-tree id is the commit's" "$(git rev-parse 'HEAD^{tree}')" "$(python3 "$HOOKS/suite-record.py" --check WORKTREE)"
eq "…so the push is allowed"                              allow "$(push 'git push origin development')"
git update-index --no-skip-worktree phpunit.xml; git checkout -q -- phpunit.xml

echo "the runner:"
reset_records
d="$(git rev-parse --git-common-dir)/groundwork"; mkdir -p "$d"
printf '{"%s": 300, "%s": 300}' "$F/AuditTest.php" "$F/BasketTest.php" > "$d/test-durations.json"
eq "--whole: green, exit 0"                               0     "$(tr_run --whole)"
eq "…in parts no longer than ~8 minutes"                  "2"   "$(sed '/^$/d' "$ROOT/runs.log" | grep -c .)"
eq "…which together are the whole suite"                  "$(find tests -name '*Test.php' | sort | tr '\n' ' ')" "$(tr ' ' '\n' < "$ROOT/runs.log" | sed '/^$/d' | sort | tr '\n' ' ')"
eq "…recorded as a whole pass"                            0     "$(python3 "$HOOKS/suite-record.py" --check WORKTREE >/dev/null; echo $?)"
printf '#!/bin/sh\necho "Running tests in parallel requires \\"brianium/paratest\\"."; exit 1\n' > bin/noparatest; chmod +x bin/noparatest
reset_records; cfg ', "test_full": "./bin/noparatest"'
eq "--whole when test_full runs no test: serial parts instead" 0 "$(tr_run --whole)"
has "…and it says so"                                     "serial parts instead" "$(cat "$ROOT/tr.out")"
cfg; rm -f bin/noparatest
reset_records; mkdir -p storage/framework/testing; printf '{"%s": "conn-once"}' "$F/ReportTest.php" > "$ROOT/control.json"
eq "a file that lost the database connection: re-run once, green" 0 "$(tr_run --whole)"
has "…and says it re-ran it"                              "re-running them once" "$(cat "$ROOT/tr.out")"
rm -rf storage; rm -f "$ROOT/control.json"
printf '<?php class Mailer { function send() { return 4; } }\n' > app/Services/Mailer.php
eq "--for-push on a tree that is not HEAD: refused"       1     "$(tr_run --for-push HEAD)"
reset_tree
lockd="$(git rev-parse --git-common-dir)/groundwork/locks/test-db-shop_test"; mkdir -p "$lockd"; printf 'test-run.py --whole, started 10:00 UTC\n' > "$lockd/label"
edit 's/return 1;/return 8;/' app/Services/OrderService.php
eq "a busy test database: not run"                        1     "$(tr_run --close --lock-wait 1)"
has "…naming what holds it"                               "started 10:00 UTC" "$(cat "$ROOT/tr.out")"
printf 'run-999999\n' > "$lockd/owner"
eq "a lock whose holder is dead: taken over, run"         0     "$(tr_run --close --lock-wait 1)"
has "…and it says so"                                     "no longer exists" "$(cat "$ROOT/tr.out")"
rm -rf "$lockd"; reset_tree

echo; echo "  passed: $pass, failed: $fail"; [ "$fail" -eq 0 ]
