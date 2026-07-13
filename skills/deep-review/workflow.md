# deep-review — Workflow reference

Run inline via the `Workflow` tool against the current `git diff`. Each dimension is a **pipeline**:
find → verify as soon as that dimension's findings land (no barrier between dimensions).

```js
export const meta = {
  name: 'deep-review',
  description: 'Adversarially-verified risk review of a diff',
  phases: [{ title: 'Find' }, { title: 'Verify' }, { title: 'Conform' }],
}
const DIMENSIONS = [
  { key: 'api-contract',         prompt: 'renamed/removed/retyped fields, enum/pagination/error-shape/route/method/authz changes on existing endpoints' },
  { key: 'rbac',                 prompt: 'every write endpoint authorized; no reliance on frontend visibility; allowed- and forbidden-user tests' },
  { key: 'financial-visibility', prompt: 'hidden financial fields stay hidden in production/station contexts; money keeps decimal-string behavior' },
  { key: 'migrations',           prompt: 'additive & production-safe; indexes for new query patterns; casts/factories/resources/tests aligned; rollback risk' },
  { key: 'workflow-state',       prompt: 'transitions go through guards; no bypass of state rules; scan/movement sequence preserved' },
  { key: 'queues-scheduler',     prompt: 'side effects behind jobs/events; cache is not the source of truth; deploy accounts for cache/config rebuild' },
  { key: 'n+1',                  prompt: 'list endpoints eager-load relationships intentionally' },
  { key: 'integration',          prompt: 'behind clients/services; capability claims grounded; errors/retries handled and tested with fakes' },
  { key: 'other-consequences',   prompt: 'anything the fixed dimensions miss: a domain/product mismatch (right problem? meets the stated goal?), a broken user expectation, an unintended side effect — walk the blind-spot taxonomy' },
]
const FINDING = { type: 'object', required: ['dimension', 'findings'], properties: {
  dimension: { type: 'string' },
  findings:  { type: 'array', items: { type: 'object', required: ['title', 'file'], properties: {
    title: { type: 'string' }, file: { type: 'string' }, detail: { type: 'string' } } } } } }
const VERDICT = { type: 'object', required: ['real', 'reason'], properties: {
  real: { type: 'boolean' }, reason: { type: 'string' } } }

log(`deep-review: ${DIMENSIONS.length} dimensions over the diff`)

const results = await pipeline(DIMENSIONS,
  d => agent(`Review the working diff (git diff) for the ${d.key} risk: ${d.prompt}. Report concrete findings with file:line, or none.`,
    { schema: FINDING, phase: 'Find', label: `find:${d.key}` }),
  review => parallel((review.findings || []).map(f => () =>
    parallel(['exploit-path', 'false-alarm'].map(lens => () =>
      agent(`Adversarially verify this risk via the ${lens} lens — is it REAL or a false alarm? Cite evidence: ${JSON.stringify(f)}`,
        { agentType: 'groundwork:adversarial-verifier', schema: VERDICT, phase: 'Verify', label: `verify:${review.dimension}` })))
      .then(vs => ({ ...f, dimension: review.dimension, verdicts: vs.filter(Boolean),
        real: vs.filter(Boolean).some(v => v.real) }))))
)

phase('Conform')
const conformance = await agent(
  `Judge the working diff (git diff) against the spec's acceptance-criterion IDs. Report only correctness/requirement gaps, each with file:line + the unmet AC ID.`,
  { agentType: 'groundwork:conformance-reviewer', phase: 'Conform', label: 'conformance' })

const confirmed = results.flat().filter(Boolean).filter(f => f.real)
return { confirmed, conformance }
```

Only `confirmed` (survived adversarial verification) reaches the report; the rest are dropped as false
alarms. `conformance` is the diff-vs-spec gap list.
