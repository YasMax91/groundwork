---
description: Ground an external/third-party API integration before coding — fetch official docs, build a capability matrix, mark unknowns, and require sandbox proof. Use whenever a task touches an external service, SDK, webhook, or a payment/booking/messaging provider.
---

# Ground an external integration

External integrations are where guessing does the most damage. Do this **before** writing
integration code. Boost does not cover third-party APIs — go to their official documentation.

## Steps

1. **Identify the exact provider, product, and API version** in use (or to be used).
2. **Fetch the official documentation** with WebFetch/WebSearch (and the provider's own MCP if one
   exists). For a deep sweep, spawn the **grounded-researcher** agent.
3. **Build a capability matrix** — one row per feature the task needs:

   | Feature needed | Supported? | Evidence (URL + quote / endpoint) | Fallback if not |
   |---|---|---|---|

   Mark anything you cannot confirm as `UNKNOWN — must verify`. Never assume a capability exists
   because similar providers have it.
4. **Resolve every `UNKNOWN` with the user** before writing code. If a needed capability is not
   supported, surface it and propose the fallback — do not silently work around it.
5. **Plan the executable proof**: a real sandbox/API call that exercises the path. The integration
   is not "done" until that call succeeds.
6. Before completion, have the **adversarial-verifier** agent challenge each "it works" claim against
   the cited evidence and the sandbox result.

## Output

The capability matrix, the list of resolved/blocking unknowns, the chosen approach, and the planned
executable proof. Label every cell `verified` (with evidence) or `assumed`.
