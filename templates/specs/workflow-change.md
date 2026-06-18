# Spec: workflow change — <area>

- Type: workflow / state change (L3 / L4)
- CRD / source:
- Status: draft | approved

## Current states & transitions

## Proposed states & transitions

Explicit allowed-transition map.

## Guards

What is rejected, and why.

## Side effects

events / broadcasts / notifications dispatched on transition.

## Tests (write first — red list)

Unit-first for the transition map (allowed transitions · blocked transitions); feature for
endpoint-level side effects. Written before the code.

## Risks

Must not bypass existing workflow/state guards.
