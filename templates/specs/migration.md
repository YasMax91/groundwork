# Spec: migration — <change>

- Type: migration / schema (L3)
- Status: draft | approved

## Change

## Additive?

Destructive changes (drop/rename column) require explicit approval and a data-migration plan.

## Production data considerations

nullable / backfill / safe defaults for existing rows.

## Indexes / foreign keys / cascade

## Engine-specific (MySQL / Postgres)

Target the project's engine (`.groundwork.json` `database.default`), never SQLite. Call out anything
that differs per engine: column-type changes (`change()` vs drop-recreate), FK enforcement, JSON
columns, `enum`, fullText indexes, `decimal` precision. Verify with Boost `search-docs`.

## Align

model casts & fillable · factories · seeders · resources · tests.

Write tests first for any behavior that depends on the new schema (casts, backfill, constraints) —
see the TDD protocol.

## Acceptance criteria (EARS — schema-dependent behavior only)

Stable IDs; append, never renumber. Pure DDL with no observable behavior needs none — state that.

- [ ] **AC1** WHEN <entity> is read after the migration THE SYSTEM SHALL cast <column> to <type>.
      → test: tests/Unit/<X>Test.php::test_cast
- [ ] **AC2** WHILE existing rows predate the column THE SYSTEM SHALL present <backfilled / default value>.
      → test: tests/Feature/<X>Test.php::test_backfill
- [ ] **AC3** IF a write violates <constraint> THEN THE SYSTEM SHALL reject it at the DB level.
      → test: tests/Feature/<X>Test.php::test_constraint

## Blind spots considered

Dimensions the change did not name but the schema/data demand — existing-row backfill, concurrent
writes during migration, dependent consumers, cascade behavior (per the blind-spot protocol). Material
only; "none" is valid.

- <what was missed> → <consequence if ignored> → <closed here / deferred because …>

## Rollback risk

## Deployment

queue pause? cache/config rebuild? data backfill step?
