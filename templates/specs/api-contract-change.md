# Spec: API contract change — <endpoint>

- Type: API contract change (L3)
- Status: draft | approved

## Current contract

route · method · request fields · response resource · OpenAPI schema

## Proposed change

## Additive or breaking?

Breaking changes (rename/remove/retype fields, enum/pagination/error-shape/route/method/authz
changes) require explicit approval.

## Migration path for clients

## OpenAPI updates

## Acceptance criteria (EARS — each maps to a red test)

Stable IDs; append, never renumber.

- [ ] **AC1** WHEN a valid request hits <route> THE SYSTEM SHALL return <status> with <new shape>.
      → test: tests/Feature/<X>Test.php::test_response_shape
- [ ] **AC2** IF the request is invalid THEN THE SYSTEM SHALL return 422 with the <field> errors.
      → test: tests/Feature/<X>Test.php::test_validation
- [ ] **AC3** WHERE the change is breaking THE SYSTEM SHALL preserve the old contract until <deprecation>.
      → test: tests/Feature/<X>Test.php::test_back_compat

## Tests (write first — red list)

Feature-first, written before the code; each names its AC ID(s): request validation (valid + invalid)
and response shape — covers: AC1, AC2, AC3.

## Risks
