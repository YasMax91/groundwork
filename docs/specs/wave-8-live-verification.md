# Spec: Wave 8 — live-verification discipline (plugin v0.13.0)

- Type: plugin self-improvement — methodology + templates + one runnable deliverable (prose / templates;
  **no hooks, no scripts** — the Part C hook work is Wave 11). Cross-cutting behavior change → **L3**.
- Author: Max Yastremskyi (YasMax91). Owner: RaDevs.
- Source: the session-mined complaint brief for the v0.12.0 window (2026-07-21 → 2026-07-27, 36 sessions
  across 4 projects). Wave 8 is the first package (the dominant pain, ~16 cases). Extends the
  [enhancement roadmap](plugin-enhancement-roadmap.md), post-Wave 7.
- Status: **draft — awaiting approval**. No files edited until approved.
- Target version: v0.13.0

## Goal

Close the dominant, most-painful failure mode of the window: the plugin declares work **"done / проверено"**
on green gates (phpunit + Pint + `analyse` + OpenAPI), and the user finds a defect the first time they
touch it live. ~16 cases across every project — a 500 in admin order-editing after a new SQL join (an
unqualified `id`), a clone that reported success while silently failing, an `admin.css` that never
loaded, a filter stuck on persisted `localStorage`, `select2` corners the theme overrode, a thumbnail
empty on 32/32 rows, a fix landed in List but not Show, a contract that declared a payment status by a
`uuid` nothing could produce.

Wave 8 adds a **live-proof discipline**: before "done", exercise the changed behavior against the
*running* app the way a user hits it (HTTP for APIs, a real browser for admin/UI), verify **every**
consumer of a touched data shape (not just the one edited), hand the frontend a **runnable** request
package (Postman/curl) instead of prose to retype, turn a user bug report into a **systemic class-audit**
instead of a point patch, and **cite official sources in the answer itself**. Green gates stay necessary
— Wave 8 makes them no longer sufficient.

## Problem (diagnosis)

Confirmed by inspection of the current plugin (v0.12.0):

1. **"Done" rests on the test kernel, never the running app.** `final-check` runs `format:test`,
   `analyse`, phpunit, and OpenAPI generation (`skills/final-check/SKILL.md:11-23`); the handoff only
   asks the agent to *describe* "how to test manually" (`skills/final-check/SKILL.md:50`). Nothing
   exercises the real endpoint or the real screen. A green feature test and a live 500 on the same code
   are both consistent with today's "done".
2. **Executable proof is scoped to external integrations only.** `guidelines/grounding-protocol.md:24`
   demands a real sandbox/API call — but the whole protocol is gated to "any work that touches an
   external service" (`guidelines/grounding-protocol.md:4`). An internal feature endpoint has **no**
   live-run requirement anywhere in the plugin.
3. **No browser verification for UI / admin / CSS work.** The plugin never drives a browser. A CSS or
   admin change that never reaches runtime — asset not registered, theme specificity, a persisted
   `localStorage` filter — passes every gate, because the failure is invisible to phpunit by
   construction. Visual QA is silently handed to the user even when a browser-driving tool is available.
4. **Verification coverage is not required to match the blast radius.** A change to a field or a
   response shape can be "done" after fixing one consumer (List) while another (Show, export, API, a
   denormalized/derived column) still shows the old or empty value. The self-review
   (`skills/final-check/SKILL.md:29-35`) checks contracts and tests, not "did I verify every place this
   data surfaces". The impact map exists in discovery but is never spent as a **verification** checklist.
5. **No runnable request package for the frontend.** `frontend-handoff` documents the contract as prose
   + JSON examples (`templates/frontend/feature.md:33`) but hands over nothing executable — no Postman
   collection, no curl set with real auth and bodies. The frontend retypes the contract by hand.
6. **Citations don't surface in the answer.** `grounding-protocol.md:19` requires URL + quote for an
   external capability, but the evidence lands in the spec or a subagent transcript; the main chat
   answer asserts the behavior without the source, so the user cannot check it. Internal project docs
   (AGENTS.md / CRD) carry no citation discipline at all.

## Boundaries — what "live proof" is and is not

The load-bearing rule: **green gates are necessary, not sufficient.** Live proof is an *addition* to the
gates, never a replacement, and it fails safe.

| Mechanism | Question it answers | Wave 8 |
|---|---|---|
| phpunit / Pint / `analyse` / OpenAPI Stop gates | "does the code satisfy the tests & static rules?" | **unchanged** — still required, still run first |
| `impact-mapper` (discovery) | "what could my change break?" (couplings, *before* code) | **unchanged** — its mid-session refresh is Wave 10; Wave 8 only *spends* its output as a verify checklist |
| **live proof (new)** | **"does the running app actually do it, everywhere it should?"** (*after* code, before done) | **new** — HTTP/browser run + consumer coverage + runnable package |

Two guardrails against the opposite failure (verification ceremony):

- **Surface-typed triggers.** API/route touched → HTTP run. Admin/UI/CSS touched → browser run. Pure
  internal refactor with no user-facing surface → neither. The live path scales with what actually
  changed, exactly like the OpenAPI gate keys off the contract surface.
- **A visible escape, not a silent skip.** When the running app or the browser tool cannot be reached,
  the agent states precisely what stayed unverified and hands over exact reproduction steps — the same
  fail-open-with-a-reason pattern as `- OpenAPI: n/a — <reason>`. It never reports green tests as "works
  live", and never pushes onto the user a visual check it could have driven itself.

## Design — per item

### C1 — Live proof in `final-check` (the core)

A new **"Live verification"** section in `skills/final-check/SKILL.md`, placed **after** the gates and
**before** the self-review — the gates gate the code, this gates reality.

- **API / feature endpoint** → a real run against the **running** app: a request over the served app
  (curl / an HTTP client), or a real client call inside `./vendor/bin/sail artisan tinker`, with
  realistic input; capture the **actual** status + body. A green feature test does **not** satisfy this
  — the point is the wire, the middleware stack, the real DB, and the serialized response a client sees.
  If the app is not served in the session, fall back to the closest real exercise
  (`$this->getJson(...)` against the HTTP kernel) and say explicitly that the wire was not hit.
- **Admin / UI / CSS change** → drive a **real browser** when a browser-driving tool is available (e.g.
  the `claude-in-chrome` MCP). Verify the three things the gates cannot see:
  1. the asset / route **actually loads** (network — the file the edit lives in is really requested, not
     404/ignored by the theme);
  2. the edited style / behavior is the one **in effect** (computed style — not shadowed by theme
     specificity), checked after a hard refresh / cleared persisted state;
  3. no **persisted client state** (`localStorage` / session) masks the change (the Backpack
     persistent-table case).
- **Fail-safe & no offloading.** If the running app or the browser tool is unavailable, state exactly
  what could not be verified and hand over precise reproduction steps. Never report green tests as "works
  live"; never hand the user a visual check the agent could have driven.

Wiring: the self-review checklist gains one line — *"exercised live against the running app: `<how>`"* —
and the handoff summary's "what was verified" must name the **live run and its observed result**, not
just the commands that passed.

### C2 — Coverage: verify every consumer of a touched shape

A rule in `final-check` tied to the change's blast radius. When the change touches a **field, an enum, or
a response shape**, verify it **everywhere it surfaces** — List *and* Show, export, the API
`JsonResource`, notifications — and confirm every **denormalized / derived** value is populated
**end-to-end with real data** (present on a real row, not merely written by code that "should" run). The
`impact-mapper` output from discovery is the checklist: a consumer it lists is either verified or
explicitly noted out of scope. **"Fixed in one place" is not "done"** while the map names other
consumers.

This is the `product_variants.thumbnail` empty-on-32/32 case, the truncated message column, and the
"fix in List, Show untouched" case — one rule covering all three.

### C3 — End-to-end reachability of a declared contract value

A contract value is documented as available only after real data produces it **end-to-end** — the field
exists in the shape **and** something in the system can actually populate it from real inputs. This is the
direct fix for the payment-status-by-`uuid` case: a shape the backend cannot fill is not a contract, and
it must be caught here (backend side) rather than when an independent frontend agent hits the wall. Lives
in `final-check` (as a live-proof check) and in `frontend-handoff` (a documented field must be reachable,
not aspirational).

### C4 — Systemic, not reactive, on a bug report

A new rule in `final-check` and a line in `guidelines/ai-sdd-process.md` (Review mode): a UI or behavior
defect reported by the user triggers an **audit of the whole class**, not a patch of the single instance.
Enumerate every sibling site — every model with an image field, every column that truncates, every screen
using that partial, every dashboard link's clickability — and fix + verify the **class** in one pass. One
user-found defect is evidence the class was never verified, not a lone typo to spot-fix. (The reference
behavior is the `getBoundingClientRect` sweep the agent later did once prompted — Wave 8 makes it the
first move, not the second.)

### C5 — Runnable request package for the frontend (B-4)

`skills/frontend-handoff/SKILL.md` produces, alongside the prose contract, an **executable** package
under `ai/frontend/` covering every touched endpoint:

- a **Postman collection** (`ai/frontend/<area>.postman_collection.json`) **or** a `.http` / curl file
  (`ai/frontend/<area>.http`) — the skill picks one per project and stays consistent;
- each request carries: **method, URL, headers (incl. the auth header), and a request body derived from
  the `FormRequest` rules**;
- each request is annotated with a **captured example success + error response** taken from the C1 live
  run — so the examples are real, not invented.

`templates/frontend/handoff.md` and `templates/frontend/feature.md` gain a one-line pointer to the
package (a location line, not a second copy of the contract). The frontend developer **runs** the
contract instead of retyping it.

### C6 — `grounding-protocol`: broaden live proof + surface citations (B-4 + B-5)

Two edits to `guidelines/grounding-protocol.md`:

- **Broaden executable proof.** The "real sandbox/API call before done" rule (rule 3) explicitly covers
  **internal feature endpoints** too — the running-app exercise from C1 — not only external
  integrations. The anti-guessing principle is identical; only the current scoping is too narrow. The
  external-integration matrix and adversarial verification stay exactly as they are.
- **Surface citations in the answer.** When a claim rests on an **official source** (external API docs,
  or the framework via Boost `search-docs`) **or an internal project doc** (AGENTS.md / CRD), cite it —
  source + a short quote — **in the main chat answer**, not only in the spec or a subagent transcript, or
  mark it `UNKNOWN — must verify`. "Source or UNKNOWN" now spans internal project docs, not just external
  APIs.

### C7 — Definition of Done + rollout

- `guidelines/ai-sdd-process.md` — the **Definition of Done** and the **Self-review checklist** gain the
  live-proof line (exercised live against the running app for the touched surface) and the coverage line
  (every consumer of a touched shape verified or noted out of scope).
- `README.md` — "What's inside" documents the live-verification discipline and the runnable request
  package; the Layout mentions the new template pointers.
- `.claude-plugin/plugin.json` → `0.13.0`; the roadmap records Wave 8.

## Acceptance criteria (EARS)

Verification is structural (inspect the Markdown / templates) plus a live dogfood: one real feature task
whose `final-check` captures an HTTP run, and — for a UI task — a browser drive.

- [ ] **W8-AC1** WHEN a change touches a feature / API endpoint, THE `final-check` skill SHALL require a
      real run against the **running** app (HTTP over the served app, or a real client in `tinker`) with
      realistic input, capturing the actual status + body, AND SHALL state that a green feature test
      alone does not satisfy it. → check: skills/final-check/SKILL.md
- [ ] **W8-AC2** WHEN a change touches admin / UI / CSS, THE skill SHALL require driving a real browser
      when a browser-driving tool is available, verifying (a) the asset/route actually loads (network),
      (b) the edited style/behavior is the effective computed one, and (c) persisted client state does
      not mask it. → check: skills/final-check/SKILL.md
- [ ] **W8-AC3** WHEN the running app or the browser tool is unavailable, THE skill SHALL require stating
      exactly what was not verified plus precise reproduction steps, AND SHALL forbid both reporting green
      tests as "works live" and offloading a drivable visual check onto the user.
      → check: skills/final-check/SKILL.md + guidelines/grounding-protocol.md
- [ ] **W8-AC4** WHEN a change touches a field / enum / response shape, THE skill SHALL require verifying
      every consumer named by the impact map (List, Show, export, API resource, notifications) and every
      denormalized / derived value populated end-to-end with real data, OR noting a consumer explicitly
      out of scope. → check: skills/final-check/SKILL.md
- [ ] **W8-AC5** THE skill SHALL require that a declared contract value be produced by real data
      end-to-end before it is documented as available — no field the backend cannot actually populate.
      → check: skills/final-check/SKILL.md + skills/frontend-handoff/SKILL.md
- [ ] **W8-AC6** WHEN the user reports a UI / behavior defect, THE workflow SHALL audit the whole class of
      sibling sites and fix + verify the class, not only the reported instance.
      → check: skills/final-check/SKILL.md + guidelines/ai-sdd-process.md
- [ ] **W8-AC7** WHEN a frontend-facing change ships, THE `frontend-handoff` skill SHALL produce a
      runnable request package (a Postman collection or a curl/`.http` file) under `ai/frontend/` covering
      each touched endpoint — method, URL, auth header, body from the `FormRequest`, and a captured
      example success + error response — AND the frontend templates SHALL point to it.
      → check: skills/frontend-handoff/SKILL.md + templates/frontend/handoff.md + templates/frontend/feature.md
- [ ] **W8-AC8** THE grounding protocol's executable-proof rule SHALL cover internal feature endpoints
      (a running-app exercise), not only external integrations. → check: guidelines/grounding-protocol.md
- [ ] **W8-AC9** WHEN a claim rests on an official source (external docs or Boost `search-docs`) or an
      internal project doc (AGENTS.md / CRD), THE agent SHALL cite it (source + short quote) in the main
      answer, not only in the spec or a subagent transcript, OR mark it `UNKNOWN`.
      → check: guidelines/grounding-protocol.md
- [ ] **W8-AC10** THE Definition of Done and the Self-review checklist in `guidelines/ai-sdd-process.md`
      SHALL include the live-proof and consumer-coverage checks; `.claude-plugin/plugin.json` SHALL be
      `0.13.0`; `README.md` SHALL document the live-verification discipline and the runnable request
      package; AND the roadmap SHALL record Wave 8.
      → check: guidelines/ai-sdd-process.md + .claude-plugin/plugin.json + README.md + plugin-enhancement-roadmap.md

## Risks / assumptions

- **Browser tool not universal (primary risk).** A browser-driving MCP (`claude-in-chrome`) may be absent
  in a given project or harness. Mitigation: the requirement is conditional ("when available") plus the
  AC3 fail-safe — no hard dependency, matching the plugin's fail-open philosophy. The brief confirms it
  was available and used in the user's environment, but the plugin must never *require* it.
- **App not served in the session.** Live HTTP needs `sail up`. Mitigation: fall back to the HTTP-kernel
  exercise (`$this->getJson`) with an explicit "wire not hit" note — still stronger than the test kernel
  alone, and honest about what it did not cover.
- **Verification ceremony.** The opposite failure — every trivial edit demanding a browser dance.
  Mitigation: surface-typed triggers (pure internal change → no live path) and coverage keyed to the
  impact map, so the cost scales with the real blast radius, not with every keystroke.
- **Latency / token cost.** Live runs and browser drives add turns. Accepted deliberately: this is the
  most frequent and most expensive failure mode of the window; the discipline pays verification cost
  before the user pays defect cost.
- **Request-package staleness.** A generated collection can drift from the contract. Mitigation: it is
  produced/updated in the **same** handoff as the contract, and its examples come from the live run — so
  it reflects reality at ship time. Keeping it current later is the same discipline as the living
  reference doc.
- **Assumption.** The user-facing surface is knowable from routes / controllers / resources / Backpack
  config, so "surface-typed triggers" can be decided mechanically. Where a change is ambiguous
  (internal-only vs user-facing), the agent errs toward running the live path.

## Rollout

- Version **v0.13.0**. **Additive** — prose, skills, and templates only; **no hook or script behavior
  changes** (Part C is Wave 11). No change to the approval gate, test-first, or the existing Stop gates
  (Part D — do not disturb what works).
- Commit (single line, no AI attribution):
  `feat: v0.13.0 — live verification discipline (HTTP + browser proof, consumer coverage, runnable request package)`.

## Verification plan

Inspect each touched file against W8-AC1–AC10. Dogfood on one real feature task: confirm `final-check`
captures a live HTTP run (status + body) and, for a UI task, a browser drive (network + computed style +
persisted state), and that a runnable request package lands in `ai/frontend/`. Run `conformance-reviewer`
on the diff against these ACs. Structural + one live dogfood; methodology and prose, no scripts.
