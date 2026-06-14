# AGENTS.md — <Project Name>

> Process, grounding protocol, and Laravel standards are provided by the **groundwork**
> plugin. Follow its skills (`/groundwork:start-task`, `:spec`, `:implement-approved`,
> `:risk-review`, `:final-check`, `:ground-integration`) and its Definition of Done.
> **This file holds domain facts only** — do not duplicate the generic process here.

## Always-on baseline

- Classify every non-trivial task (L0–L4); start in Discovery; no code before an approved plan.
- Ground external-API claims with cited official docs + a capability matrix + sandbox proof — never
  guess. Use Boost (`search-docs`, `application-info`, `database-schema`) for framework facts.
- Run the gates (format, static analysis, tests) before "done". Never report unqualified "100% done".
- Thin controllers · logic in services · FormRequest validation · JsonResource shape · transactions
  for multi-step writes · external calls behind clients/services.

## Product                              <!-- from code + README · confirm -->

<one paragraph: what this backend does and who uses it>

## Tech stack & runtime                 <!-- from composer / sail / Boost -->

<PHP & Laravel versions, DB, cache/queue, auth, key packages; how to run via Sail>

## Domain entities                      <!-- from db schema + models -->

<core tables/models and how they relate>

## Repo layout                          <!-- from directory tree -->

<where controllers / requests / resources / services / filters / models / migrations / tests live>

## Permissions & financial visibility   <!-- draft · verify -->

<roles, key permissions, and which contexts hide financial fields>

## External integrations                <!-- draft · add capability notes -->

<each external service + its client/service class + grounded capability notes>

## Domain invariants                    <!-- AI proposes · you confirm -->

<business rules that must not be broken>

## CRD / requirements source            <!-- needs you -->

<absolute path to the requirements document — the business source of truth>
