---
description: Create or update an implementation spec under docs/specs/ for a backend feature, bug fix, API/contract change, migration, or risky domain change. Use after discovery, before implementation.
---

# Write/update a spec

Specs live in the project's `docs/specs/`. Keep them short, concrete, and implementation-oriented —
a useful spec beats a perfect document.

## Steps

1. **Pick the closest template** from this plugin's `templates/specs/`:
   `feature.md`, `bugfix.md`, `api-contract-change.md`, `migration.md`, `workflow-change.md`,
   `integration-change.md`.
2. **Link the spec** back to the CRD section, existing docs, code behavior, or the explicit user
   decision that justifies it.
3. **Separate Stage A / MVP scope from future-stage notes.** Future notes guide naming and
   boundaries; they do not expand the current implementation.
4. **Write acceptance criteria** that are testable and map to the verification plan — each becomes a
   fail-first test (the red list) for L2+/bug fixes.
5. **Record the technical approach and tradeoffs** — if the CRD intent is right but a different
   technical shape is safer, document why.
6. **List risks, assumptions, and the verification plan** (which tests — written test-first — and
   which gates). See the TDD protocol (`guidelines/tdd-protocol.md`).
7. **Hand off with a Russian summary (выжимка).** After the spec file is saved, post a short Russian
   digest to chat so the user grasps the essentials without reading the full English document — cover
   что строим (goal), что входит в MVP и что отложено, ключевые технические решения и компромиссы,
   главные риски/допущения, и как будем проверять (acceptance + тесты). Include the spec file path.

## Rules

- If the spec is incomplete, clarify the missing business rule or state the assumption explicitly.
- Update the spec if implementation discovers a material constraint, conflict, or safer approach.
- Keep all spec text in English. The chat выжимка is the one exception — it is always Russian. The
  English spec file is the source of truth; the Russian summary is the digest. Never make the user
  read the full spec to get the gist.
