# deep-discovery — Workflow reference

Adapt `args.seeds` (the files/symbols/tables to map) and optional `args.integration`, then run inline
via the `Workflow` tool. The map stage is a **barrier** (`parallel`) because the dedup needs all seed
maps at once; edge verification then fans out.

```js
export const meta = {
  name: 'deep-discovery',
  description: 'Consolidated blast radius from many seeds',
  phases: [{ title: 'Map' }, { title: 'Verify edges' }],
}
const SEEDS = args.seeds                 // ['app/Models/Order.php', 'orders (table)', 'OrderService::ship']
const INTEGRATION = args.integration || null

const MAP = { type: 'object', required: ['seed', 'connections'], properties: {
  seed:         { type: 'string' },
  connections:  { type: 'array', items: { type: 'object' } },
  hotspots:     { type: 'array', items: { type: 'string' } },
  dynamicEdges: { type: 'array', items: { type: 'string' } } } }

log(`deep-discovery: ${SEEDS.length} seeds${INTEGRATION ? ' + 1 integration researcher' : ''}`)

phase('Map')
const maps = await parallel([
  ...SEEDS.map(s => () => agent(
    `Map the FULL blast radius of seed "${s}" across the whole project — callers/consumers, events/listeners, observers, jobs, scheduled commands, policies/Gates, FK/cascades, the JsonResource shape and its API consumers, and covering tests. Flag dynamic edges grep cannot prove.`,
    { agentType: 'groundwork:impact-mapper', schema: MAP, phase: 'Map', label: `map:${s}` })),
  ...(INTEGRATION ? [() => agent(
    `Research the external integration touched by this change: ${INTEGRATION}. Cite official sources.`,
    { agentType: 'groundwork:grounded-researcher', phase: 'Map', label: 'research' })] : []),
])

phase('Verify edges')
const seedMaps = maps.filter(Boolean).filter(m => m && m.seed)
const edges = seedMaps.flatMap(m => (m.dynamicEdges || []).map(e => ({ seed: m.seed, edge: e })))
const checked = await parallel(edges.slice(0, 12).map(e => () => agent(
  `Confirm or refute this dynamic edge against the real code; cite file:line: ${JSON.stringify(e)}`,
  { agentType: 'groundwork:adversarial-verifier', phase: 'Verify edges', label: 'edge' })))

const hotspots = [...new Set(seedMaps.flatMap(m => m.hotspots || []))]
return { maps: seedMaps, hotspots, dynamicEdges: checked.filter(Boolean), seedCount: SEEDS.length }
```

Write the returned map to `.claude/groundwork/impact/<slug>.md` with the `BASE_COMMIT` / `SEEDS` header so
later sessions reuse it instead of re-running this fan-out.
