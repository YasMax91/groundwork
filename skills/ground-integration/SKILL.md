---
description: Ground an external/third-party API integration before coding — fetch official docs, build a capability matrix, mark unknowns, and require sandbox proof. Use whenever a task touches an external service, SDK, webhook, or a payment/booking/messaging provider.
effort: high
---

# Ground an external integration

External integrations are where guessing does the most damage. Do this **before** writing
integration code. Boost does not cover third-party APIs — go to their official documentation.

For an **L3/L4** integration with a large or critical API, escalate to **`deep-grounding`** — a
multi-agent Workflow that builds an adversarially-verified capability matrix (each row refuted-or-
survived). This single-agent flow stays the default for L0–L2.

## Steps

1. **Identify the exact provider, product, and API version** in use (or to be used).
2. **Fetch the official documentation** with WebFetch/WebSearch (and the provider's own MCP if one
   exists). For a deep sweep, spawn the **grounded-researcher** agent.
3. **Build a capability matrix** — one row per feature the task needs:

   | Feature needed | Supported? | Evidence (URL + quote / endpoint) | Fallback if not |
   |---|---|---|---|

   Mark anything you cannot confirm as `UNKNOWN — must verify`. Never assume a capability exists
   because similar providers have it.

   Three rows are **mandatory** for every provider, because the answers decide whether the integration
   can be made safe at all — and none of them is guessable:

   - does the provider accept an **idempotency key** on an outgoing call (header name, scope, TTL)?
   - is webhook/callback delivery **at-least-once or at-most-once**, and does it retry?
   - does an event carry a **stable id** that is identical across redeliveries?

   A provider with no webhooks answers row two and three with `N/A — no callbacks`, with the evidence
   URL. `UNKNOWN` on any of the three blocks coding, same as any other unresolved row.
4. **Resolve every `UNKNOWN` with the user** before writing code. If a needed capability is not
   supported, surface it and propose the fallback — do not silently work around it.
5. **Plan the executable proof**: a real sandbox/API call that exercises the path. The integration
   is not "done" until that call succeeds.
6. Before completion, have the **adversarial-verifier** agent challenge each "it works" claim against
   the cited evidence and the sandbox result.

## Output

The capability matrix, the list of resolved/blocking unknowns, the chosen approach, and the planned
executable proof. Label every cell `verified` (with evidence) or `assumed`.
