#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/effort.ts (GW39-AC4..AC6) — the decisions the mod makes on
# each request: the checkpoint's level, the tables .groundwork.json asks for, the effort a request carries.
# The hook wiring itself is checked by `claude plugin validate` (it lists the events and calls the module uses).
# Needs Node with type stripping (22.6+); skipped, and said so, on an older one. Run: bash hooks/tests/effort.sh
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
v="$(node -p 'process.versions.node' 2>/dev/null || echo 0)"
major="${v%%.*}"; minor="$(printf '%s' "$v" | cut -d. -f2)"
if [ "${major:-0}" -lt 22 ] || { [ "$major" -eq 22 ] && [ "${minor:-0}" -lt 6 ]; }; then
  echo "  skipped: node $v cannot import TypeScript (needs 22.6+)"; exit 0
fi
flag=""; [ "$major" -lt 23 ] && flag="--experimental-strip-types"
# shellcheck disable=SC2086
node $flag --no-warnings --input-type=module - "$HOOKS/effort.ts" <<'JS'
const { levelOf, tablesOf, decide, note, DEFAULTS } = await import(process.argv[2])
let pass = 0, fail = 0
const eq = (name, want, got) => {
  if (JSON.stringify(want) === JSON.stringify(got)) { pass++; console.log(`  ok   ${name.padEnd(58)} [${got}]`) }
  else { fail++; console.log(`  FAIL ${name.padEnd(58)} want ${JSON.stringify(want)}, got ${JSON.stringify(got)}`) }
}
const cp = (mode, level) => `# Task: x\n- Mode: ${mode}\n\n- Level: ${level}\n- Kind: crud\n`
eq('an open L2 task: level 2', 2, levelOf(cp('Implementation', 'L2')))
eq('a level with a note after it', 1, levelOf(cp('Discovery', 'L1 (documentation-only contract repair)')))
eq('a closed task: no level', undefined, levelOf(cp('Done — shipped', 'L3')))
eq('no Mode line: no level', undefined, levelOf('- Level: L3\n'))
eq('no Level line: no level', undefined, levelOf('- Mode: Spec\n'))
const t = tablesOf({})
eq('main: L0 docs medium', 'medium', decide(0, t, undefined, 'max'))
eq('main: L1 high', 'high', decide(1, t, undefined, 'max'))
eq('main: L2 high', 'high', decide(2, t, undefined, 'medium'))
eq('main: L3 one step below max', 'xhigh', decide(3, t, undefined, 'medium'))
eq('main: L4 max', 'max', decide(4, t, undefined, 'medium'))
eq('main: already right, left alone', undefined, decide(2, t, undefined, 'high'))
eq('no open task: the menu effort stays', undefined, decide(undefined, t, undefined, 'max'))
eq('a model without effort is never given one', undefined, decide(4, t, undefined, undefined))
eq('mapping agent at L2: medium', 'medium', decide(2, t, 'groundwork:impact-mapper', 'high'))
eq('research agent at L4: high', 'high', decide(4, t, 'groundwork:grounded-researcher', 'medium'))
eq('checker at L2: high', 'high', decide(2, t, 'groundwork:conformance-reviewer', 'medium'))
eq('checker at L3: xhigh', 'xhigh', decide(3, t, 'groundwork:adversarial-verifier', 'high'))
eq('checker at L4: max', 'max', decide(4, t, 'groundwork:blind-spot-mapper', 'high'))
eq('a foreign agent is left alone', undefined, decide(4, t, 'Explore', 'medium'))
eq('effort.by_level=false: off', undefined, tablesOf({ effort: { by_level: false } }))
const o = tablesOf({ effort: { table: { main: { L2: 'medium', L9: 'max', L3: 'bogus' } } } })
eq('effort.table overrides a level', 'medium', o.main[2])
eq('…ignores a level that does not exist', undefined, o.main[9])
eq('…and a value that is not an effort', DEFAULTS.main[3], o.main[3])
eq('the line under the answer', 'усилие: высокое — задача с кодом', note(2, 'high'))
console.log(`\n  passed: ${pass}, failed: ${fail}`)
process.exit(fail ? 1 : 0)
JS
