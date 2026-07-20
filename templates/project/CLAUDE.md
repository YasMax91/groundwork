# CLAUDE.md

Project instructions for Claude Code. **Read `AGENTS.md` first** — it is the domain contract.

Generic process, the grounding protocol, and Laravel standards come from the **groundwork**
plugin (installed via the `yasmax` marketplace). Do not duplicate them here.

Quick rules: classify tasks (L0–L4); Discovery before code; test-first for L2+ and bug fixes; ground
external-API claims with cited docs + sandbox proof; run the gates before "done"; keep changes scoped
and production-safe.

The OpenAPI/Swagger spec is part of the contract, not documentation written afterwards: every change
to an endpoint ships with its annotations updated **in the same change**, complete to the last detail
(every reachable response code, the request body from the FormRequest, the response schema from the
JsonResource). The `openapi` Stop gate enforces this.

Communicate with the user in Russian by default. Keep all repository artifacts (code, names,
comments, tests, docs, specs, API/validation messages, OpenAPI text) in English unless explicitly
requested otherwise.
