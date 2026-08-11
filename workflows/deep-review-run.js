export const meta = {
  name: 'deep-review-run',
  description: 'Adversarially-verified risk review of a diff, dimension by dimension',
  whenToUse: 'Driven by the groundwork:deep-review skill for L3/L4 diffs. Each dimension finds risks, every finding is refuted by two independent skeptics, and only survivors are reported.',
  phases: [
    { title: 'Find', detail: 'one agent per risk dimension over the working diff' },
    { title: 'Verify', detail: 'two adversarial lenses per finding' },
    { title: 'Conform', detail: 'diff vs the spec acceptance criteria' },
  ],
}

// Each dimension is a pipeline: find -> verify as soon as THAT dimension's findings land. No barrier
// between dimensions, so a slow dimension never holds up verification of a fast one.
const DIMENSIONS = [
  { key: 'api-contract',         prompt: 'renamed/removed/retyped fields, enum/pagination/error-shape/route/method/authz changes on existing endpoints' },
  { key: 'rbac',                 prompt: 'every write endpoint authorized; no reliance on frontend visibility; allowed- and forbidden-user tests' },
  { key: 'financial-visibility', prompt: 'hidden financial fields stay hidden in production/station contexts; money keeps decimal-string behavior' },
  { key: 'migrations',           prompt: 'additive & production-safe; indexes for new query patterns; casts/factories/resources/tests aligned; rollback risk' },
  { key: 'workflow-state',       prompt: 'transitions go through guards; no bypass of state rules; scan/movement sequence preserved' },
  { key: 'queues-scheduler',     prompt: 'side effects behind jobs/events; cache is not the source of truth; deploy accounts for cache/config rebuild' },
  { key: 'n+1',                  prompt: 'list endpoints eager-load relationships intentionally' },
  { key: 'integration',          prompt: 'behind clients/services; capability claims grounded; errors/retries handled and tested with fakes' },
  { key: 'other-consequences',   prompt: 'anything the fixed dimensions miss: a domain/product mismatch (right problem? meets the stated goal?), a broken user expectation, an unintended side effect — walk the blind-spot taxonomy, including unconfirmed assumptions about the domain the reader is not expert in' },
]

const FINDING = { type: 'object', required: ['dimension', 'findings'], properties: {
  dimension: { type: 'string' },
  findings:  { type: 'array', items: { type: 'object', required: ['title', 'file'], properties: {
    title: { type: 'string' }, file: { type: 'string' }, detail: { type: 'string' } } } } } }
const VERDICT = { type: 'object', required: ['real', 'reason'], properties: {
  real: { type: 'boolean' }, reason: { type: 'string' } } }

const scope = (args && args.scope) || 'the working diff (git diff)'
const criteria = (args && args.criteria) || 'the spec acceptance-criterion IDs, if a spec exists'

log(`deep-review: ${DIMENSIONS.length} измерений риска по диффу, каждая находка проверяется двумя скептиками`)

const results = await pipeline(DIMENSIONS,
  d => agent(
    `Review ${scope} for the ${d.key} risk: ${d.prompt}. Report concrete findings with file:line, or none.`,
    { schema: FINDING, phase: 'Find', label: `find:${d.key}` }),
  review => parallel(((review && review.findings) || []).map(f => () =>
    parallel(['exploit-path', 'false-alarm'].map(lens => () =>
      agent(`Adversarially verify this risk via the ${lens} lens — is it REAL or a false alarm? Cite evidence: ${JSON.stringify(f)}`,
        { agentType: 'groundwork:adversarial-verifier', schema: VERDICT, phase: 'Verify', label: `verify:${review.dimension}` })))
      .then(vs => ({ ...f, dimension: review.dimension, verdicts: vs.filter(Boolean),
        real: vs.filter(Boolean).some(v => v.real) }))))
)

phase('Conform')
const conformance = await agent(
  `Judge ${scope} against ${criteria}. Report only correctness/requirement gaps, each with file:line + the unmet AC ID. A verification claim carrying no denominator is itself a gap.`,
  { agentType: 'groundwork:conformance-reviewer', phase: 'Conform', label: 'conformance' })

const all = results.flat().filter(Boolean)
const confirmed = all.filter(f => f.real)
log(`deep-review: подтверждено ${confirmed.length} из ${all.length} находок; остальные отброшены как ложная тревога`)

// Only what survived adversarial verification reaches the report. The counts travel with it so the
// report can state its denominator instead of saying "found some risks".
return { confirmed, examined: all.length, dropped: all.length - confirmed.length, conformance }
