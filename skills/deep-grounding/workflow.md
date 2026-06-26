# deep-grounding — Workflow reference

Adapt `args.capabilities` (the capabilities to confirm) and `args.sources` (official doc URLs), then
run this inline via the `Workflow` tool. Workers are the plugin's agents, spawned by `agentType`.
Read → Verify is a **pipeline** so each row verifies as soon as its read returns (no barrier).

```js
export const meta = {
  name: 'deep-grounding',
  description: 'Verified capability matrix from an external API doc',
  phases: [{ title: 'Read' }, { title: 'Verify' }, { title: 'Synthesize' }],
}
const CAPS = args.capabilities          // e.g. ['tokenize cards', 'refunds', 'webhook signature']
const SOURCES = args.sources || ''      // official doc URLs / sections

const FINDING = { type: 'object', required: ['capability', 'supported', 'evidence'], properties: {
  capability: { type: 'string' },
  supported:  { type: 'string', enum: ['yes', 'no', 'unknown'] },
  evidence:   { type: 'string', description: 'official-doc URL + exact quote, or why unknown' },
  fallback:   { type: 'string' } } }
const VERDICT = { type: 'object', required: ['verdict', 'reason'], properties: {
  verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED', 'UNCERTAIN'] }, reason: { type: 'string' } } }

log(`deep-grounding: ${CAPS.length} capabilities × (1 reader + 2 skeptics)`)

const rows = await pipeline(CAPS,
  cap => agent(
    `Research whether the provider supports "${cap}". Cite an official-docs URL + exact quote, or mark unknown. Sources: ${SOURCES}`,
    { agentType: 'groundwork:grounded-researcher', schema: FINDING, phase: 'Read', label: `read:${cap}` }),
  finding => parallel(['docs-literal', 'edge-cases'].map(lens => () =>
      agent(`Adversarially refute this capability claim via the ${lens} lens; default REFUTED if evidence is absent: ${JSON.stringify(finding)}`,
        { agentType: 'groundwork:adversarial-verifier', schema: VERDICT, phase: 'Verify', label: `verify:${finding.capability}` }))
    .then(vs => ({ ...finding, verdicts: vs.filter(Boolean) })))
)

phase('Synthesize')
const matrix = rows.filter(Boolean).map(r => {
  const vs = r.verdicts || []
  return { capability: r.capability, supported: r.supported, evidence: r.evidence, fallback: r.fallback || '',
    survived: vs.length > 0 && vs.every(v => v.verdict !== 'REFUTED'), verdicts: vs }
})
return { matrix, unknowns: matrix.filter(m => m.supported === 'unknown' || !m.survived) }
```

The result feeds the `integration-change` spec's capability matrix. A row is `verified` only if it has
cited evidence **and** survived the adversarial panel.
