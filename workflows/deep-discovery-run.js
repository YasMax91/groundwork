export const meta = {
  name: 'deep-discovery-run',
  description: 'Consolidated blast radius mapped from many seeds in parallel',
  whenToUse: 'Driven by the groundwork:deep-discovery skill for L3/L4 changes touching many seeds. Pass args.seeds (files/symbols/tables) and optionally args.integration.',
  phases: [
    { title: 'Map', detail: 'one impact-mapper per seed, plus an optional integration researcher' },
    { title: 'Verify edges', detail: 'adversarial check of the edges grep cannot prove' },
  ],
}

// The map stage is a genuine barrier: the dedup below needs every seed map at once. Edge
// verification then fans out over the union.
const SEEDS = (args && args.seeds) || []
const INTEGRATION = (args && args.integration) || null
const MAX_EDGES = (args && args.maxEdges) || 12

if (!Array.isArray(SEEDS) || SEEDS.length === 0) {
  throw new Error('deep-discovery-run requires args.seeds: an array of files, symbols or tables to map, e.g. ["app/Models/Order.php", "orders (table)"]')
}

const MAP = { type: 'object', required: ['seed', 'connections'], properties: {
  seed:         { type: 'string' },
  connections:  { type: 'array', items: { type: 'object' } },
  hotspots:     { type: 'array', items: { type: 'string' } },
  dynamicEdges: { type: 'array', items: { type: 'string' } } } }

log(`deep-discovery: ${SEEDS.length} сидов${INTEGRATION ? ' + 1 исследователь интеграции' : ''}`)

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
const examined = edges.slice(0, MAX_EDGES)

// No silent caps: when the edge list is longer than the budget, say what was left unchecked rather
// than letting the report read as if everything was verified.
if (edges.length > examined.length) {
  log(`deep-discovery: динамических рёбер ${edges.length}, проверяется ${examined.length}; остальные ${edges.length - examined.length} остаются непроверенными`)
}

const checked = await parallel(examined.map(e => () => agent(
  `Confirm or refute this dynamic edge against the real code; cite file:line: ${JSON.stringify(e)}`,
  { agentType: 'groundwork:adversarial-verifier', phase: 'Verify edges', label: 'edge' })))

const hotspots = [...new Set(seedMaps.flatMap(m => m.hotspots || []))]
const failedSeeds = SEEDS.length - seedMaps.length

return {
  maps: seedMaps,
  hotspots,
  dynamicEdges: checked.filter(Boolean),
  seedCount: SEEDS.length,
  mappedSeeds: seedMaps.length,
  failedSeeds,
  edgesFound: edges.length,
  edgesVerified: examined.length,
}
