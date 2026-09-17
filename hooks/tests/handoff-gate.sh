#!/usr/bin/env bash
# Groundwork plugin :: executable proof for handoff-gate.sh.
# The gate exists so a frontend-facing change cannot end quietly without its handoff. A blocking
# Stop gate can also strand the workflow, so every branch gets a case: it must block the omission,
# stay silent when the handoff is there, and stay silent on work the frontend cannot see.
# No framework — plain bash. Run: bash hooks/tests/handoff-gate.sh
set -uo pipefail

GATE="$(cd "$(dirname "$0")/.." && pwd)/handoff-gate.sh"
[ -f "$GATE" ] || { echo "gate not found: $GATE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

expect() {
  local name="$1" want="$2" dir="$3" got
  ( cd "$dir" && bash "$GATE" >/dev/null 2>&1 )
  got=$?
  if [ "$got" = "$want" ]; then
    pass=$((pass+1)); printf '  ok   %-42s (exit %s)\n' "$name" "$got"
  else
    fail=$((fail+1)); printf '  FAIL %-42s (want %s, got %s)\n' "$name" "$want" "$got"
  fi
}

# says <name> <substring> <dir> — the message has to name what the agent must do
says() {
  local name="$1" want="$2" dir="$3" out
  out="$( cd "$dir" && bash "$GATE" 2>&1 >/dev/null )"
  if printf '%s' "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ok   %-42s (message names it)\n' "$name"
  else
    fail=$((fail+1)); printf '  FAIL %-42s (message lacks "%s")\n' "$name" "$want"
  fi
}

# fixture <dir> [extra .groundwork.json gates json]
fixture() {
  local d="$1" gates="${2:-{\}}"
  mkdir -p "$d/app/Http/Controllers" "$d/app/Services" "$d/routes" "$d/docs/ai/frontend/handoff" "$d/database/migrations"
  printf '{ "runner": "sail", "docs": { "frontend": "docs/ai/frontend" }, "gates": %s }\n' "$gates" > "$d/.groundwork.json"
  printf '<?php\nclass FooController {}\n' > "$d/app/Http/Controllers/FooController.php"
  printf '# doc\n' > "$d/docs/ai/frontend/catalog.md"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init ) >/dev/null 2>&1
}

echo "handoff-gate"

# 1. Nothing changed at all.
A="$ROOT/clean"; fixture "$A"
expect "clean tree" 0 "$A"

# 2. A controller changed, no document → blocked.
B="$ROOT/controller"; fixture "$B"
printf '<?php\nclass FooController { public function index() {} }\n' > "$B/app/Http/Controllers/FooController.php"
expect "controller without handoff" 2 "$B"
says   "names the file" "app/Http/Controllers/FooController.php" "$B"
says   "names the skill" "/groundwork:frontend-handoff" "$B"

# 3. The same change, with a delta written → silent.
C="$ROOT/with-handoff"; fixture "$C"
printf '<?php\nclass FooController { public function index() {} }\n' > "$C/app/Http/Controllers/FooController.php"
printf -- '---\ntitle: "x"\n---\n' > "$C/docs/ai/frontend/handoff/2026-01-01-x.md"
expect "controller with handoff" 0 "$C"

# 4. A reference doc counts too — a change can be pure correction of the current truth.
D="$ROOT/with-reference"; fixture "$D"
printf '<?php\nclass FooController { public function index() {} }\n' > "$D/app/Http/Controllers/FooController.php"
printf '# doc changed\n' > "$D/docs/ai/frontend/catalog.md"
expect "controller with reference doc" 0 "$D"

# 5. Work the frontend cannot see.
E="$ROOT/internal"; fixture "$E"
mkdir -p "$E/tests/Unit"; printf '<?php\n// test\n' > "$E/tests/Unit/FooTest.php"
printf '# readme\n' > "$E/README.md"
expect "tests and readme only" 0 "$E"

# 6. Scheduling and the portal's own routes are not a contract the frontend reads.
F="$ROOT/console"; fixture "$F"
printf '<?php\n// schedule\n' > "$F/routes/console.php"
printf '<?php\n// portal\n' > "$F/routes/docs-portal.php"
expect "console and portal routes" 0 "$F"

# 7. A migration is frontend-facing: fields come from the schema.
G="$ROOT/migration"; fixture "$G"
printf '<?php\n// add column\n' > "$G/database/migrations/2026_01_01_000000_add.php"
expect "migration without handoff" 2 "$G"

# 8. A service can change what an unchanged field means — the silent case this gate exists for.
H="$ROOT/service"; fixture "$H"
printf '<?php\nclass StockService {}\n' > "$H/app/Services/StockService.php"
expect "service without handoff" 2 "$H"

# 9. Committing must not disarm the gate: the plugin's own flow ends in a commit.
I="$ROOT/committed"; fixture "$I"
printf '<?php\nclass FooController { public function index() {} }\n' > "$I/app/Http/Controllers/FooController.php"
( cd "$I" && git add -A && git commit -qm change ) >/dev/null 2>&1
expect "committed, unpushed" 2 "$I"

# 10. A waiver covers only the files it names.
J="$ROOT/waived"; fixture "$J"
printf '<?php\nclass FooController { public function index() {} }\n' > "$J/app/Http/Controllers/FooController.php"
mkdir -p "$J/.claude/groundwork"
printf '# reason: internal rename, no response field moved\napp/Http/Controllers/FooController.php\n' > "$J/.claude/groundwork/handoff-waiver"
expect "waived file" 1 "$J"
printf '<?php\nclass BarController {}\n' > "$J/app/Http/Controllers/BarController.php"
expect "file outside the waiver" 2 "$J"
says   "names the unwaived file" "BarController.php" "$J"

# 11. Opt-out: silent with a stated reason, reported without one.
K="$ROOT/off-with-reason"; fixture "$K" '{ "handoff_on_stop": false, "handoff_skip_reason": "no frontend consumer" }'
printf '<?php\nclass FooController { public function index() {} }\n' > "$K/app/Http/Controllers/FooController.php"
expect "off with a stated reason" 0 "$K"

L="$ROOT/off-silently"; fixture "$L" '{ "handoff_on_stop": false }'
printf '<?php\nclass FooController { public function index() {} }\n' > "$L/app/Http/Controllers/FooController.php"
expect "off with no reason" 1 "$L"

# 12. A project shaped differently narrows the surface itself.
M="$ROOT/custom-surface"; fixture "$M" '{ "handoff_surface": "^app/Http/Resources/" }'
printf '<?php\nclass FooController { public function index() {} }\n' > "$M/app/Http/Controllers/FooController.php"
expect "outside a custom surface" 0 "$M"

# 13. Outside a Groundwork project the plugin is inert.
N="$ROOT/not-a-project"; mkdir -p "$N/app/Http/Controllers"
printf '<?php\n' > "$N/app/Http/Controllers/FooController.php"
expect "no .groundwork.json" 0 "$N"

# 14. Not a git repository — no window to read, nothing to claim.
O="$ROOT/not-git"; mkdir -p "$O/app/Http/Controllers"
printf '{ "gates": {} }\n' > "$O/.groundwork.json"
printf '<?php\n' > "$O/app/Http/Controllers/FooController.php"
expect "not a git repo" 0 "$O"

# 15. The window closes on a handoff and opens again on the next contract change. This is the
#     property the gate is for: one handoff must not cover every later change on the same branch.
P="$ROOT/reopen"; fixture "$P"
printf '<?php\nclass FooController { public function index() {} }\n' > "$P/app/Http/Controllers/FooController.php"
printf -- '---\ntitle: "x"\n---\n' > "$P/docs/ai/frontend/handoff/2026-01-01-x.md"
( cd "$P" && git add -A && git commit -qm "feature + handoff" ) >/dev/null 2>&1
expect "handoff committed with the change" 0 "$P"
printf '<?php\nclass BazController {}\n' > "$P/app/Http/Controllers/BazController.php"
expect "next change after that handoff" 2 "$P"
says   "names only the new file" "BazController.php" "$P"

# 16. Work that is not frontend-facing, after a handoff, stays silent.
Q="$ROOT/after-handoff-internal"; fixture "$Q"
printf -- '---\ntitle: "x"\n---\n' > "$Q/docs/ai/frontend/handoff/2026-01-01-x.md"
( cd "$Q" && git add -A && git commit -qm handoff ) >/dev/null 2>&1
mkdir -p "$Q/tests/Unit"; printf '<?php\n' > "$Q/tests/Unit/BarTest.php"
expect "internal work after a handoff" 0 "$Q"

# 17. A fresh repository whose first commit already changes the contract is still seen: with no
#     upstream, no default branch and no earlier handoff there is no anchor, and the gate must not
#     take that as "nothing happened".
R="$ROOT/first-commit"; mkdir -p "$R/app/Http/Controllers" "$R/docs/ai/frontend"
printf '{ "gates": {} }\n' > "$R/.groundwork.json"
printf '<?php\nclass FooController {}\n' > "$R/app/Http/Controllers/FooController.php"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm first ) >/dev/null 2>&1
expect "first commit is a contract change" 2 "$R"

# 18. A project whose admin panel is server-rendered carves it out — and only it. A model or a
#     migration behind that panel is still frontend-facing, because the storefront reads those fields.
S="$ROOT/exclude"; fixture "$S" '{ "handoff_surface_exclude": "^app/Http/Controllers/Admin/" }'
mkdir -p "$S/app/Http/Controllers/Admin"
printf '<?php\nclass ProductCrudController {}\n' > "$S/app/Http/Controllers/Admin/ProductCrudController.php"
expect "excluded admin controller" 0 "$S"
mkdir -p "$S/app/Models"; printf '<?php\nclass Product {}\n' > "$S/app/Models/Product.php"
expect "model behind that panel" 2 "$S"

echo "-----"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
