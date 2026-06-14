---
description: Run the final AI-SDD self-review before handing off backend work — run format, static analysis, and targeted tests, verify the Definition of Done, and produce the handoff summary.
---

# Final check

Run the gates and the self-review before declaring the work done. Use the project's commands
(from `.groundwork.json`, defaulting to Sail).

## Run the gates

- Format: `./vendor/bin/sail composer format:test` (or `format` to apply).
- Static analysis: `./vendor/bin/sail composer analyse`.
- Tests: the narrowest relevant first, then broader — e.g.
  `./vendor/bin/sail artisan test --filter=...`, then `./vendor/bin/sail composer test`.

Report results honestly. If a gate could not run (Sail/services unavailable), say so explicitly.

## Self-review checklist

followed the spec? · only related files changed? · API contracts preserved? · controllers thin? ·
logic in services? · validation in FormRequest? · authorization present? · multi-step writes
transactional? · resources preserve shape? · N+1 handled? · migrations production-safe? · tests
added/updated? · OpenAPI updated when contracts changed? · gates run or skip-reason stated?

## Handoff summary

1. Behavior change first (not just files).
2. Key files changed and why.
3. What was verified, with the exact commands run.
4. How to test manually or with targeted automated tests.
5. Risks, deployment notes, migrations, cache/config/queue/scheduler impact, API-contract changes.
6. Anything skipped, deferred, or not run.
7. Assumptions or CRD/code conflicts.

Never report unqualified "100% done". State what is `verified` vs `assumed`.
