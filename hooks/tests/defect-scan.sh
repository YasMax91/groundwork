#!/usr/bin/env bash
# Groundwork plugin :: executable proof for defect-scan.sh (wave 30).
# Every case here is a defect that was found in a real repository on 2026-08-27, plus the shape that
# looked like the same defect and was not — because the first version of this scan cried wolf on it.
# Run: bash hooks/tests/defect-scan.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/defect-scan.sh"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT

proj() { # dir [gates json]
  mkdir -p "$1/app/Services" "$1/app/Events" "$1/app/Jobs" "$1/config" "$1/database/migrations"
  printf '{ "runner": "host", "gates": %s }\n' "${2:-\{\}}" > "$1/.groundwork.json"
  printf "<?php return ['connections' => ['redis' => ['after_commit' => false]]];\n" > "$1/config/queue.php"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init )
}
run() { ( cd "$1" && bash "$HOOK" 2>&1 >/dev/null ); }
code() { ( cd "$1" && bash "$HOOK" >/dev/null 2>&1 ); printf '%s' "$?"; }

expect() { # name dir want_code want_substr("" = any)
  local got; got="$(code "$2")"
  local out; out="$(run "$2")"
  if [ "$got" = "$3" ] && { [ -z "${4:-}" ] || printf '%s' "$out" | grep -q "$4"; }; then
    pass=$((pass+1)); printf '  ok   %-34s (exit %s)\n' "$1" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-34s want exit %s%s, got %s: %s\n' "$1" "$3" "${4:+ + \"$4\"}" "$got" "$(printf '%s' "$out" | head -2 | tr '\n' ' ')"
  fi
}

echo "defect-scan:"

# --- env() outside config: the crm-wigs defect (job posts to a hostless URL after config:cache) ---
d="$ROOT/env"; proj "$d"
printf '<?php\nclass SendFiles { public function handle() { $u = rtrim(env("MEDIA_URL"), "/"); } }\n' > "$d/app/Jobs/SendFiles.php"
expect "env() in app is blocked" "$d" 2 "env() outside config"

d="$ROOT/envcfg"; proj "$d"
printf "<?php return ['url' => env('MEDIA_URL')];\n" > "$d/config/media.php"
expect "env() in config/ is fine" "$d" 0

d="$ROOT/envdoc"; proj "$d"
printf '<?php\n// never call env() outside config\nclass A {}\n' > "$d/app/Services/A.php"
expect "env() in a comment is fine" "$d" 0

# --- money as float: the crm-wigs payments.amount defect ------------------------------------------
d="$ROOT/money"; proj "$d"
printf '<?php\nreturn new class { public function up() { Schema::create("payments", function ($t) { $t->double("amount"); }); } };\n' \
  > "$d/database/migrations/2026_01_01_000000_create_payments.php"
expect "money as double is blocked" "$d" 2 "money as float/double"

d="$ROOT/money2"; proj "$d"
printf '<?php\nreturn new class { public function up() { Schema::create("m", function ($t) { $t->double("weight_kg"); }); } };\n' \
  > "$d/database/migrations/2026_01_01_000000_create_m.php"
expect "a non-money double is fine" "$d" 0

# --- an irreversible effect inside a transaction: the next-lvl invoice defect ---------------------
d="$ROOT/mail"; proj "$d"
printf '<?php\nclass InvoiceService { public function send() { return DB::transaction(function () {\n  $x = 1;\n  $sent = Mail::to("a@b.c")->send($mailable);\n  return $sent; }); } }\n' \
  > "$d/app/Services/InvoiceService.php"
expect "mail inside a transaction warns" "$d" 1 "irreversible side effect"

# --- a broadcast event inside a transaction: the fam-sync TaskDeleted defect ----------------------
d="$ROOT/ev"; proj "$d"
printf '<?php\nclass TaskDeleted implements ShouldBroadcast { }\n' > "$d/app/Events/TaskDeleted.php"
printf '<?php\nclass TaskService { public function del() { DB::transaction(function () {\n  TaskDeleted::dispatch(1); }); } }\n' \
  > "$d/app/Services/TaskService.php"
expect "broadcast w/o afterCommit warns" "$d" 1 "ShouldDispatchAfterCommit"

# …and the same shape that fam-sync had already solved must stay quiet — this is what the first
# version of the audit script cried wolf on.
d="$ROOT/ev2"; proj "$d"
printf '<?php\nclass FamilyTouched implements ShouldBroadcast, ShouldDispatchAfterCommit { }\n' > "$d/app/Events/FamilyTouched.php"
printf '<?php\nclass FamilyService { public function t() { DB::transaction(function () {\n  event(new FamilyTouched(1)); }); } }\n' \
  > "$d/app/Services/FamilyService.php"
expect "ShouldDispatchAfterCommit is quiet" "$d" 0

# a plain event with no queue and no broadcast is a synchronous call, not a race
d="$ROOT/ev3"; proj "$d"
printf '<?php\nclass PlainThing { }\n' > "$d/app/Events/PlainThing.php"
printf '<?php\nclass S { public function t() { DB::transaction(function () {\n  event(new PlainThing(1)); }); } }\n' > "$d/app/Services/S.php"
expect "a synchronous event is quiet" "$d" 0

# after_commit=true globally disarms the whole check
d="$ROOT/ev4"; proj "$d"
printf "<?php return ['connections' => ['redis' => ['after_commit' => true]]];\n" > "$d/config/queue.php"
printf '<?php\nclass Q implements ShouldQueue { }\n' > "$d/app/Events/Q.php"
printf '<?php\nclass S2 { public function t() { DB::transaction(function () {\n  Q::dispatch(1); }); } }\n' > "$d/app/Services/S2.php"
expect "after_commit=true disarms it" "$d" 0

# --- a job with no retry or failure handling ------------------------------------------------------
d="$ROOT/job"; proj "$d"
printf '<?php\nclass Naked implements ShouldQueue { public function handle() {} }\n' > "$d/app/Jobs/Naked.php"
expect "a job with no retries warns" "$d" 1 "no \$tries"
d="$ROOT/job2"; proj "$d"
printf '<?php\nclass Careful implements ShouldQueue { public $tries = 3; public function failed($e) {} }\n' > "$d/app/Jobs/Careful.php"
expect "a job that handles failure is fine" "$d" 0

# --- the contract every gate here honours ----------------------------------------------------------
d="$ROOT/off"; proj "$d" '{ "defect_scan": false }'
printf '<?php\nclass X { public function h() { env("A"); } }\n' > "$d/app/Services/X.php"
expect "gates.defect_scan=false opts out" "$d" 0
d="$ROOT/bare"; mkdir -p "$d/app"; printf '<?php\nclass X { public function h() { env("A"); } }\n' > "$d/app/X.php"
expect "no .groundwork.json, no scan" "$d" 0
d="$ROOT/clean"; proj "$d"
expect "nothing changed, nothing said" "$d" 0
d="$ROOT/nogit"; mkdir -p "$d/app"; printf '{ "runner": "host" }\n' > "$d/.groundwork.json"
printf '<?php\nclass X { public function h() { env("A"); } }\n' > "$d/app/X.php"
expect "outside a git repo it is inert" "$d" 0

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
