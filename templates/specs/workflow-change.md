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

## Acceptance criteria (EARS — each maps to a red test)

Stable IDs; append, never renumber.

- [ ] **AC1** WHEN <entity> is in <state> AND <event> occurs THE SYSTEM SHALL transition to <next state>.
      → test: tests/Unit/<X>Test.php::test_allowed_transition
- [ ] **AC2** IF a transition from <state> to <target> is not allowed THEN THE SYSTEM SHALL reject it.
      → test: tests/Unit/<X>Test.php::test_blocked_transition
- [ ] **AC3** WHEN the transition succeeds THE SYSTEM SHALL dispatch <event / notification>.
      → test: tests/Feature/<X>Test.php::test_side_effect

## Tests (write first — red list)

Unit-first for the transition map (allowed · blocked); feature for endpoint-level side effects.
Written before the code; each names its AC ID(s) — covers: AC1, AC2, AC3.

## Risks

Must not bypass existing workflow/state guards.
