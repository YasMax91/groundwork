# Spec: <feature name>

- Type: feature (L2)
- CRD / source: <link or "user decision: ...">
- Status: draft | approved

## Goal

<business outcome in 1–2 sentences>

## Scope (Stage A / MVP)

<what is in>

## Out of scope / future

<deliberately deferred>

## Design

- Routes / methods:
- Request (FormRequest) + validation:
- Service logic:
- Response (JsonResource) shape:
- Data / migrations:
- Permissions:

## Acceptance criteria (EARS — each maps to a red test)

Stable IDs; append, never renumber. Each criterion is an EARS statement
(`WHEN` / `WHILE` / `IF…THEN` / `WHERE` / `THE SYSTEM SHALL`) linked to the test that proves it.

- [ ] **AC1** WHEN an authenticated user with <permission> POSTs <valid payload> to <route>
      THE SYSTEM SHALL persist <entity> and return 201 with <resource shape>.
      → test: tests/Feature/<X>Test.php::test_creates_entity
- [ ] **AC2** IF the payload fails <rule> THEN THE SYSTEM SHALL return 422 with the <field> error.
      → test: tests/Feature/<X>Test.php::test_validation
- [ ] **AC3** WHEN the caller lacks <permission> THE SYSTEM SHALL return 403.
      → test: tests/Feature/<X>Test.php::test_authorization

## Tests (write first — the red list)

Each test names the AC ID(s) it proves; written fail-first before the code. Match the layer:

- feature (contract / validation / authz / response shape) — covers: AC1, AC2, AC3
- unit (services / calculations / state transitions) — covers: <AC ids>

## Risks / assumptions / deployment notes
