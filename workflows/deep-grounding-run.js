export const meta = {
  name: 'deep-grounding-run',
  description: 'Verified capability matrix for an external API, every row adversarially checked',
  whenToUse: 'Driven by the groundwork:deep-grounding skill for L3/L4 integrations. Pass args.capabilities (what must be confirmed) and args.sources (official doc URLs).',
  phases: [
    { title: 'Read', detail: 'one cited reader per capability' },
    { title: 'Verify', detail: 'two adversarial lenses per row' },
    { title: 'Synthesize', detail: 'assemble the matrix and separate the unknowns' },
  ],
}

// Read -> Verify is a pipeline: each row verifies the moment its read returns, so a slow capability
// never blocks a fast one.
const CAPS = (args && args.capabilities) || []
const SOURCES = (args && args.sources) || ''

if (!Array.isArray(CAPS) || CAPS.length === 0) {
  throw new Error('deep-grounding-run requires args.capabilities: an array of capabilities to confirm, e.g. ["tokenize cards", "refunds", "webhook signature"]')
}

const FINDING = { type: 'object', required: ['capability', 'supported', 'evidence'], properties: {
  capability: { type: 'string' },
  supported:  { type: 'string', enum: ['yes', 'no', 'unknown'] },
  evidence:   { type: 'string', description: 'official-doc URL + exact quote, or why unknown' },
  fallback:   { type: 'string' } } }
const VERDICT = { type: 'object', required: ['verdict', 'reason'], properties: {
  verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED', 'UNCERTAIN'] }, reason: { type: 'string' } } }

log(`deep-grounding: ${CAPS.length} возможностей × (1 читатель + 2 скептика)`)

const rows = await pipeline(CAPS,
  cap => agent(
    `Research whether the provider supports "${cap}". Cite an official-docs URL + exact quote, or mark unknown. Never guess: an absent source is "unknown", not "no". Sources: ${SOURCES}`,
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

const unknowns = matrix.filter(m => m.supported === 'unknown' || !m.survived)
const lost = CAPS.length - matrix.length
log(`deep-grounding: ${matrix.length - unknowns.length} из ${CAPS.length} возможностей подтверждены и пережили панель; ${unknowns.length} остаются неизвестными${lost ? `, ${lost} не вернули результат` : ''}`)

// A row is `verified` only with cited evidence AND survival of the panel. Everything else is an
// unknown that the integration spec must carry as such.
return { matrix, unknowns, requested: CAPS.length, returned: matrix.length }
