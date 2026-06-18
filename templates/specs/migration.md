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

## Rollback risk

## Deployment

queue pause? cache/config rebuild? data backfill step?
