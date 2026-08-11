#!/usr/bin/env bash
# Groundwork plugin :: SubagentStop hook — the review agents' output contract, enforced by the engine.
#
# The grounding protocol's central rule ("never guess; every claim carries a source or is marked
# UNKNOWN") and the verifier's required verdict were both enforced only by the agents' own prompts.
# A prompt is an instruction; this is a gate. Verified on Claude Code 2.1.212 by spike: SubagentStop
# receives `last_assistant_message` and `agent_type`, a `decision: "block"` sends the subagent back to
# fix its answer, and the re-entry arrives with `stop_hook_active: true`.
#
# Blocks at most once per subagent run, and only for the two agents whose contract is checkable.
set -uo pipefail

# Evidence that a research claim is grounded: a URL, a repository document, a file:line citation, or
# the explicit admission that the answer is not known. Anything else is a bare assertion.
GW_SOURCE_MARKERS='https?://|\.md\b|\.php:[0-9]|\.json\b|UNKNOWN|unknown|неизвестно'
# The verdict vocabulary the adversarial-verifier is required to end on.
GW_VERDICT_MARKERS='CONFIRMED|REFUTED|UNCERTAIN'

[ -f .groundwork.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ "$(jq -r '.gates.agent_contract' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# The loop guard: this Stop is the answer a previous block asked for. Judging it again would loop.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || printf 'false')" = "true" ] && exit 0

agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty' 2>/dev/null || true)"
msg="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
[ -n "$agent_type" ] || exit 0
[ -n "$msg" ] || exit 0

# Blocking still exits 0: the decision travels in the JSON, not in the exit code.
block() { jq -nc --arg r "$1" '{decision:"block", reason:$r}' 2>/dev/null || true; exit 0; }

case "$agent_type" in
  *grounded-researcher)
    printf '%s' "$msg" | grep -qE "$GW_SOURCE_MARKERS" && exit 0
    block "groundwork: this research carries no source. The grounding protocol requires every claim to cite an official URL, a repository document, or a file:line — or to be marked UNKNOWN. Add the citation to each claim, or mark it UNKNOWN and say what would settle it. Do not guess instead of checking." ;;
  *adversarial-verifier)
    printf '%s' "$msg" | grep -qE "$GW_VERDICT_MARKERS" && exit 0
    block "groundwork: this verification returns no verdict. End on CONFIRMED (with the evidence you cite), REFUTED (with the specific contradiction), or UNCERTAIN (stating exactly what evidence is missing). Default to REFUTED or UNCERTAIN when evidence is absent — an agreeable summary is not a verification." ;;
esac

exit 0
