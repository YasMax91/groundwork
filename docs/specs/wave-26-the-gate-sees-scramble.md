# Spec: Wave 26 — the OpenAPI gate stops being blind to Scramble, and the document must be usable (v0.36.0)

- Type: plugin self-improvement → **L3** (a gate branches by toolchain, one protocol rewritten, one
  skill step, seven tests).
- Author: Max Yastremskyi (YasMax91).
- Source: item E33 in [market-scan-2026-08-27.md](market-scan-2026-08-27.md).
- Status: **implemented** (2026-08-27). Gate behaviour proven by tests: `openapi-gate.sh` 36 cases
  (7 new), all suites green. The consumability check was executed against a real broken document.
- Target version: **v0.36.0**.

## Problem (diagnosis)

`hooks/openapi-gate.sh:45` detected `darkaonline/l5-swagger|zircote/swagger-php` and exited 0 on
anything else. A project on `dedoc/scramble` — a document inferred from types rather than annotations —
therefore got **no gate at all**; and if it set `openapi.enabled: true` to force one, it got a block
whose instruction ("update the annotations") describes something that project can never have. Every
positive-evidence branch searched for `@?OA\[A-Z]`, which such a project never contains.

Separately, the gate's second half proves the *generator ran*. It does not prove the document is usable:
an unresolvable `$ref` generates fine and breaks every downstream client generator.

## Design

**A `flavour`, resolved once.** `annotation` (l5-swagger / swagger-php) or `inference` (Scramble),
overridable with `openapi.generator`. With both packages present the project is annotation-driven —
annotations are the explicit statement, and a project carrying them is maintaining them.

**A branch for the evidence.** Annotation projects prove the contract moved by an annotation changing.
Inference projects prove it by the exported document at `openapi.spec_path` changing — the only
positive evidence such a project can produce. Default path `storage/api-docs/api-docs.json`, matching
the key wave 25 added to the project template.

**A branch for the instruction.** A blocked Scramble project is told to re-export and commit, and told
what an empty diff means: the types the document is inferred from did not change, so the fix is a typed
request/resource, not a document edit.

**A branch for the generation command.** `artisan scramble:export --path=<spec_path>` instead of
`artisan l5-swagger:generate`, both through the configured runner.

**`guidelines/openapi-protocol.md`** now opens with the two toolchains and what "the spec moved with
the code" means in each, including the two consequences an inference project carries.

**Consumability, in `final-check` only.** `npx -y openapi-typescript <spec>` must exit 0; without node
the handoff says the check did not run. Deliberately not in the Stop hook: a cold `npx` costs seconds
on every turn.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | A Scramble project with a changed controller and no export is blocked | met — `W26 scramble w/o export` (exit 2; before this wave: 0) |
| AC2 | Its message names the export and never asks for annotations | met — `W26 message fits the tool`, `W26 no annotation advice` |
| AC3 | The same project with the document re-exported passes | met — `W26 scramble with export` |
| AC4 | Both toolchains present → annotation rules apply | met — `W26 both -> annotations` |
| AC5 | `openapi.generator` overrides detection, and `openapi.spec_path` is honoured | met — `W26 explicit inference`, `W26 explicit spec_path ok` |
| AC6 | Existing l5-swagger behaviour is unchanged | met — the 29 pre-existing cases pass without any expectation being edited |
| AC7 | A structurally broken document fails the consumability check | **met, executed** — `openapi-typescript` 7.13.0 exits 1 on an unresolvable `$ref`, 0 on a valid document |
| AC8 | Without node, the absence is stated rather than passed over | met — structural, written into the `final-check` step |

## Deliberately not done

- **`openapi.spec_version`** — the premise was refuted by running the tools (see wave 25).
- **`oasdiff` in the gate** — it needs a committed baseline; wave 25 only just created one, and a
  breaking-change gate deserves its own wave and its own fixtures.
