# CLAUDE.md

Project instructions for Claude Code. **Read `AGENTS.md` first** — it is the domain contract.

Generic process, the grounding protocol, and Laravel standards come from the **groundwork**
plugin (installed via the `yasmax` marketplace). Do not duplicate them here.

Quick rules: classify tasks (L0–L4); Discovery before code; ground external-API claims with cited
docs + sandbox proof; run the gates before "done"; keep changes scoped and production-safe.

Communicate with the user in Russian by default. Keep all repository artifacts (code, names,
comments, tests, docs, specs, API/validation messages, OpenAPI text) in English unless explicitly
requested otherwise.
