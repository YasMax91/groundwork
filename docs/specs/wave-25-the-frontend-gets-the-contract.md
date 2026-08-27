# Spec: Wave 25 — the frontend receives the contract, not a description of it (v0.35.0)

- Type: plugin self-improvement → **L2** (one skill, two templates, one config key).
- Author: Max Yastremskyi (YasMax91).
- Source: item E32 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). One criterion executed (the mock), the rest structural.
- Target version: **v0.35.0**.

## Goal

The frontend boundary is core product for this plugin, and the frontend never got the OpenAPI document.
`grep -i 'openapi\|swagger' skills/frontend-handoff/SKILL.md` returned **0**: the handoff shipped Russian
prose and a Postman collection, both written *about* a contract that already exists as a file.

## Design

**A fourth document type: the contract snapshot.** `ai/frontend/openapi/<YYYY-MM-DD>-<slug>.yaml|json`,
copied from the project's `openapi.spec_path` after the generator has run, linked from the handoff
header, and **committed with the work** — the frontend generates types from it, and a later contract
diff needs a base that exists in git. If the generator did not run in this task, `frontend-handoff` runs
it first: a snapshot older than the code is a contract that lies.

**A mock before the backend is deployed.** The handoff template carries
`npx -y @stoplight/prism-cli mock <snapshot>` next to the existing runnable-request line, so the
frontend can start against the contract instead of waiting for an environment.

**`openapi.spec_path` in `templates/project/.groundwork.json`.** `hooks/openapi-gate.sh:40` already reads
`.openapi.enabled`, but the template shipped no `openapi` block at all, so the key existed only in the
hook's imagination. Default `storage/api-docs/api-docs.json` — l5-swagger's own default. Wave 26 needs
this key for the inference-driven branch.

**Absence is stated.** A project that documents no API skips the snapshot and says so in the handoff
doc; without node, the snapshot is still committed and the mock line is marked untried.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | The handoff produces the document itself, not only prose | met — doc type 4 plus step 5 in `skills/frontend-handoff/SKILL.md` (`openapi` appears 5 times; 0 before) |
| AC2 | The snapshot is dated, slugged and committed | met — `ai/frontend/openapi/<YYYY-MM-DD>-<slug>`, stated as committed in the skill and the template |
| AC3 | The frontend can serve the snapshot as a mock | **met, executed** — `npx -y @stoplight/prism-cli@5 mock` on a 3.1.0 fixture answered `GET /orders/{id}` with `200` and `{"id":"01J8Z","total":"19.90","status":"new"}`, generated from the schema's examples |
| AC4 | `openapi.spec_path` exists in the project template and a project without it behaves as before | met — key added; every hook still reads it through `// empty`-style lookups that treat absence as "unset" |
| AC5 | A project with no API states the absence | met — structural, written into doc type 4 |

## Deliberately not done

- **`openapi.spec_version`.** The premise behind it was refuted during the market scan:
  `openapi-typescript` 7.13.0 emits `string | null` for both 3.0.0 and 3.1.0, and
  `artisan l5-swagger:generate` takes no `--version` flag.
- **`oasdiff` breaking-change detection.** It needs a committed baseline; now that AC2 commits one,
  this becomes possible — and it is a wave of its own, not a line in this one.
- **Prism in proxy mode as a gate.** Its violation-report format was never verified; a gate on an
  unverified format is a gate that can invent a red.
