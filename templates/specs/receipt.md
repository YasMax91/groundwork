# Receipt: <task title>

- Spec: `docs/specs/<slug>.md` · Level: `<L0..L4>` · Branch: `<branch>` · Date: `<YYYY-MM-DD>`

## Measured

Every cell below is the output of a command that ran. Nothing here is written from memory: if a command
did not run, the row says so instead of being filled in.

| What | Command | Result |
|---|---|---|
| Commit | `git rev-parse --short HEAD` | `<sha>` |
| Static analysis | `<the command the done-gate ran>` | exit `<code>` |
| Test suite | `<the command the test-gate ran>` | exit `<code>` · `<N passed, M assertions>` |
| OpenAPI | `<generation command>` | `<regenerated / n-a — this project documents no API>` |
| Agent time | `hooks/estimate-ledger.sh --report` | `<active minutes>` for this task |

## Claimed by the agent

**Not measured.** Written by the model from the diff and the conformance review. The suite's exit code
says the suite passed; it does not say which test closed which criterion — that mapping is a claim.

| AC | Status | Evidence `file:line` | Covering test |
|---|---|---|---|
| AC1 | met / partial / unmet | `<path:line>` | `<test path::name>` |

- Conformance verdict (`agents/conformance-reviewer`): `<CONFORMS / GAPS — AC… / INSUFFICIENT>`
- Left uncovered: `<what no test exercises, or "nothing">`
- Not run: `<any gate that did not run, and why>`

## Reviewed by

| Reviewer | Date |
|---|---|
| `<name>` | `<YYYY-MM-DD>` |

Until a person fills this in, this document records what an agent did and what it says about its own
work. It is not a review, and it is not an attestation.
