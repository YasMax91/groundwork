#!/usr/bin/env bash
# Groundwork plugin :: Stop hook — record what the task took, once, when the checkpoint says it shipped.
#
# Wave 18 built the measurement; writing the row depended on the agent remembering a command in
# skills/final-check/SKILL.md — the exact shape of rule this plugin exists to move into the engine.
# Its own dedup key is the task (slug + `Started:`), so firing on every Stop costs one grep.
#
# Never blocks and never speaks on the happy path: a lost measurement must cost a number, never a turn.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -x "$DIR/estimate-ledger.sh" ] || exit 0
bash "$DIR/estimate-ledger.sh" --record-if-done >/dev/null || true
exit 0
