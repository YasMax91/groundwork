# Grounding protocol (Groundwork) — read reality, never guess

The most damaging failure mode is confidently guessing instead of checking. It bites hardest on
**external integrations**, where this protocol is mandatory for any work that touches an external
service, SDK, webhook, or third-party API — but reading reality, citing the source, and proving by a
real run apply to internal work too (see rules 3 and 6).

## Sources of ground truth

- **Laravel / framework** — use the Laravel Boost MCP tools **first**: `search-docs` (version-aware
  documentation for the installed packages), `application-info` (installed packages, versions,
  Eloquent models), `database-schema`, `database-query`, `last-error`, log readers. Do not recall
  Laravel APIs from memory when Boost can confirm them.
- **Packages Boost does not index** (a Spatie/Filament version it has no docs for, a provider's PHP
  SDK, a JS build tool) — when the **Context7** MCP is installed, pull the library's own documentation
  through it before falling back to WebFetch. Cite it like any other source; a Context7 excerpt with no
  version behind it is `assumed`, not `verified`.
- **External third-party APIs** (payments, booking, messaging, etc.) — Boost does **not** cover
  these. Fetch the official documentation (WebFetch / WebSearch) and quote the exact capability
  statements.

None of these tools is assumed present. When one is missing, use the next source down and say which
one you used — a missing MCP changes the evidence, never the requirement for evidence.

## Rules

1. **Source of truth.** Every claim about an external capability must be backed by a cited source
   (URL + quote) or explicitly marked `UNKNOWN — must verify`. No capability is assumed just because
   "most providers have it".
2. **Capability matrix before integration code.** Produce a table: *feature needed → supported? →
   evidence (quote/endpoint) → fallback if not*. Resolve every `UNKNOWN` with the user before coding.
3. **Executable proof — external *and* internal.** Nothing is "done" until a real call exercises the
   path against the running app. For an **external integration**: a real sandbox/API call. For an
   **internal feature endpoint**: a real HTTP run against the served app (or a real client via
   `./vendor/bin/sail artisan tinker --execute="…"` — a bare `tinker` waits for a TTY and hangs in a
   non-interactive shell) with realistic input — a green feature test alone is the test kernel, not the
   running app. If you cannot call it, you cannot claim it works; say what stayed
   unverified. (`final-check` drives this — see its Live verification section.)
4. **Confidence labeling.** Separate `verified` (with evidence) from `assumed`. Default to
   "assumed / uncertain" when unsure.
5. **Banned phrasing.** No unqualified "done", "100%", or "fully working" without evidence. Always
   state what was verified and how.
6. **Cite in the answer — and for internal rules too.** When a claim rests on an official source
   (external API docs, or the framework via Boost `search-docs`) or an internal project doc
   (`AGENTS.md` / CRD), name the source + a short quote **in the main answer** — not only in the spec or
   a subagent transcript, where the user never sees it. "Source or `UNKNOWN`" spans internal project
   docs, not just external APIs: a business rule with no doc, code, or explicit decision behind it is
   `assumed`, and must be stated as such rather than asserted as fact.

## How to run it

Use the `ground-integration` skill to drive the capability matrix. Spawn the **grounded-researcher**
agent for the documentation sweep (it must cite sources) and the **adversarial-verifier** agent to
challenge any "it works" claim about an external capability before completion — per the fan-out table in
[ai-sdd-process.md](ai-sdd-process.md), which owns the per-level calibration for both review agents.

Rule 1 stopped being advice for those two agents. A `SubagentStop` gate reads what each returns: a
researcher's report that cites no URL, no repository document, no `file:line` and no `UNKNOWN` is sent
back once to add its evidence, and a verifier that ends without `CONFIRMED` / `REFUTED` / `UNCERTAIN` is
sent back once for its verdict. The gate blocks at most once per run, never touches the other agents,
and is silent outside a Groundwork project (`gates.agent_contract`). It checks that a claim carries
evidence, not that the evidence is good — that judgement stays with the reader.

## Reference case

An agent claimed a payment provider supported card tokenization and declared the work done; the
provider did not support it at all. A capability matrix plus an executable sandbox call would have
caught this before a single line of integration code was written.
