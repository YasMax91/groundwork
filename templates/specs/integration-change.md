# Spec: integration — <provider>

- Type: external integration (L4)
- Status: draft | approved

## Provider / product / API version

## Capability matrix

Run the `ground-integration` skill first. Mark unconfirmed rows `UNKNOWN`.

| Feature needed | Supported? | Evidence (URL + quote) | Fallback |
|---|---|---|---|

## Unknowns to resolve before coding

## Approach

client/service · error handling · retries · idempotency · secrets/config.

## Executable proof

The sandbox/API call that must succeed before this is "done".

## Acceptance criteria (EARS — each maps to a red test)

Stable IDs; append, never renumber. AC1 is the executable proof.

- [ ] **AC1** WHEN the happy-path call runs against the sandbox THE SYSTEM SHALL succeed and persist <result>.
      → test: tests/Feature/<X>Test.php::test_happy_path (the executable proof)
- [ ] **AC2** IF the provider returns <error> THEN THE SYSTEM SHALL <handle / retry / surface> it.
      → test: tests/Feature/<X>Test.php::test_error_path
- [ ] **AC3** WHEN the same request is retried THE SYSTEM SHALL remain idempotent.
      → test: tests/Feature/<X>Test.php::test_idempotency

## Tests (write first — red list)

Faked integration, written before the code; each names its AC ID(s): dispatch · error paths · retries
· side effects — covers: AC1, AC2, AC3. The executable proof (AC1) is the first red test.

## Blind spots considered

Dimensions the request did not name but the integration demands — webhook ordering/retries/idempotency,
partial failure, external-vs-local state drift, secret rotation (per the blind-spot protocol). Material
only; "none" is valid.

- <what was missed> → <consequence if ignored> → <closed here / deferred because …>

## Risks
