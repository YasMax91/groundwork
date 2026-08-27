#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/estimate-ledger.sh (W18-AC1..AC6, AC13).
# The ledger is what every estimate will rest on, so its arithmetic and its refusals are pinned
# here against synthetic transcripts with known gaps. Run: bash hooks/tests/estimate-ledger.sh
set -uo pipefail

BIN="$(cd "$(dirname "$0")/.." && pwd)/estimate-ledger.sh"
[ -x "$BIN" ] || { echo "not executable: $BIN"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for these tests"; exit 1; }

pass=0; fail=0
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
export GW_PROJECTS_DIR="$ROOT/transcripts"; mkdir -p "$GW_PROJECTS_DIR"

eq() { # name want got
  if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-38s [%s]\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %-38s want "%s", got "%s"\n' "$1" "$2" "$3"; fi
}
has() { # name needle haystack   (must contain)
  case "$3" in *"$2"*) pass=$((pass+1)); printf '  ok   %-38s\n' "$1" ;;
  *) fail=$((fail+1)); printf '  FAIL %-38s "%s" not found\n' "$1" "$2" ;; esac
}
hasnt() { # name needle haystack (must not contain)
  case "$3" in *"$2"*) fail=$((fail+1)); printf '  FAIL %-38s "%s" leaked\n' "$1" "$2" ;;
  *) pass=$((pass+1)); printf '  ok   %-38s\n' "$1" ;; esac
}

key() { printf '%s' "$1" | sed -e 's#[/._]#-#g'; }

# A transcript of `n` events `step` seconds apart, starting at `start_epoch`, plus a payload string
# that must never reach the ledger.
transcript() { # file start_epoch n step
  local f="$1" t="$2" n="$3" step="$4" i=0
  mkdir -p "$(dirname "$f")"
  while [ "$i" -lt "$n" ]; do
    printf '{"type":"assistant","secret":"CONFIDENTIAL-PAYLOAD","timestamp":"%s"}\n' \
      "$(date -u -r "$t" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$t" +%Y-%m-%dT%H:%M:%S.000Z)" >> "$f"
    t=$((t+step)); i=$((i+1))
  done
  printf '%s' "$t"
}

project() { # dir  -> initialised Groundwork project
  mkdir -p "$1/.claude/groundwork"
  printf '{ "runner": "host" }\n' > "$1/.groundwork.json"
}

checkpoint() { # dir started level task
  printf '# Task: %s\n- Mode: Implementation\n- Level: %s\n- Started: %s\n' "$4" "$3" "$2" \
    > "$1/.claude/groundwork/task-state.md"
}

echo "estimate-ledger:"

# --- AC4: active time is the sum of gaps at or below the threshold, never the span -------------
# 10 events 30 s apart (270 s) · one 3600 s idle gap · 10 more 30 s apart (270 s)
#   -> active 540 s = 9 min · span 4140 s = 69 min
P="$ROOT/proj-a"; project "$P"
# Recent, because --backfill reads `git log --since='6 months ago'`: a fixture dated outside that
# window would test nothing and pass by accident.
T0=$(( $(date +%s) - 7*86400 ))
TD="$GW_PROJECTS_DIR/$(key "$P")"
NEXT="$(transcript "$TD/s1.jsonl" "$T0" 10 30)"
transcript "$TD/s1.jsonl" "$((NEXT+3570))" 10 30 >/dev/null
STARTED="$(date -u -r "$T0" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$T0" +%Y-%m-%dT%H:%M:%SZ)"
export GW_LEDGER="$ROOT/l1.tsv"
checkpoint "$P" "$STARTED" "L2" "Add a status filter"
( cd "$P" && bash "$BIN" --record --kind=crud >/dev/null 2>&1 )
row="$(tail -1 "$GW_LEDGER")"
eq "AC4 active minutes"   "9"  "$(printf '%s' "$row" | cut -f6)"
eq "AC4 calendar minutes" "69" "$(printf '%s' "$row" | cut -f7)"

# --- AC1: the row carries level, kind, slug and source ----------------------------------------
eq "AC1 level"  "L2"                 "$(printf '%s' "$row" | cut -f3)"
eq "AC1 kind"   "crud"               "$(printf '%s' "$row" | cut -f4)"
eq "AC1 slug"   "add-a-status-filter" "$(printf '%s' "$row" | cut -f5)"
eq "AC1 source" "task"               "$(printf '%s' "$row" | cut -f9)"
eq "AC1 project" "proj-a"            "$(printf '%s' "$row" | cut -f2)"

# --- AC2: durations and identifiers only ------------------------------------------------------
hasnt "AC2 no transcript content" "CONFIDENTIAL-PAYLOAD" "$(cat "$GW_LEDGER")"
eq "AC2 column count" "10" "$(printf '%s' "$row" | awk -F'\t' '{print NF}')"

# --- AC1: a promised number is recorded next to the actual ------------------------------------
export GW_LEDGER="$ROOT/l2.tsv"
( cd "$P" && bash "$BIN" --record --kind=crud --promised=25 >/dev/null 2>&1 )
eq "AC1 promised recorded" "25" "$(tail -1 "$GW_LEDGER" | cut -f8)"

# --- AC5: no `Started:` means no row, and no inferred start -----------------------------------
export GW_LEDGER="$ROOT/l3.tsv"
printf '# Task: x\n- Mode: Implementation\n- Level: L2\n' > "$P/.claude/groundwork/task-state.md"
( cd "$P" && bash "$BIN" --record >/dev/null 2>&1 )
eq "AC5 no Started, no row" "0" "$( [ -f "$GW_LEDGER" ] && grep -c 'task' "$GW_LEDGER" || echo 0 )"

# --- AC3: a worktree transcript counts toward the parent project ------------------------------
P2="$ROOT/proj-b"; project "$P2"
WT="$GW_PROJECTS_DIR/$(key "$P2")--claude-worktrees-eager-noyce-1a2b3c"
transcript "$WT/s1.jsonl" "$T0" 10 30 >/dev/null
export GW_LEDGER="$ROOT/l4.tsv"
checkpoint "$P2" "$STARTED" "L1" "Worktree task"
( cd "$P2" && bash "$BIN" --record >/dev/null 2>&1 )
eq "AC3 worktree counted" "4" "$(tail -1 "$GW_LEDGER" | cut -f6)"

# --- AC13: silent no-op without config, and under the opt-out ---------------------------------
P3="$ROOT/proj-c"; mkdir -p "$P3/.claude/groundwork"      # no .groundwork.json at all
export GW_LEDGER="$ROOT/l5.tsv"
out="$( cd "$P3" && bash "$BIN" --record 2>&1 )"; rc=$?
eq "AC13 no config: exit 0" "0" "$rc"
eq "AC13 no config: silent" ""  "$out"
eq "AC13 no config: no file" "absent" "$( [ -f "$GW_LEDGER" ] && echo present || echo absent )"

printf '{ "estimates": { "ledger": false } }\n' > "$P/.groundwork.json"
checkpoint "$P" "$STARTED" "L2" "Opted out"
export GW_LEDGER="$ROOT/l6.tsv"
( cd "$P" && bash "$BIN" --record >/dev/null 2>&1 )
eq "AC13 opt-out: no file" "absent" "$( [ -f "$GW_LEDGER" ] && echo present || echo absent )"
printf '{ "runner": "host" }\n' > "$P/.groundwork.json"

# --- AC4: the idle threshold is configurable --------------------------------------------------
# With a 4000 s threshold the 3600 s idle gap becomes work: 540 s + 3600 s = 69 min.
printf '{ "estimates": { "idle_seconds": 4000 } }\n' > "$P/.groundwork.json"
checkpoint "$P" "$STARTED" "L2" "Wide threshold"
export GW_LEDGER="$ROOT/l7.tsv"
( cd "$P" && bash "$BIN" --record >/dev/null 2>&1 )
eq "AC4 idle_seconds honoured" "69" "$(tail -1 "$GW_LEDGER" | cut -f6)"
printf '{ "runner": "host" }\n' > "$P/.groundwork.json"

# --- AC6: backfill marks its rows, and the report separates the sources -----------------------
R="$ROOT/repos"; mkdir -p "$R/repo-x"; project "$R/repo-x"
git -C "$R/repo-x" init -q 2>/dev/null
git -C "$R/repo-x" config user.email t@t; git -C "$R/repo-x" config user.name t
TDX="$GW_PROJECTS_DIR/$(key "$R/repo-x")"
transcript "$TDX/s1.jsonl" "$T0" 40 30 >/dev/null      # 39 gaps of 30 s spanning 1170 s
for i in 1 2; do
  printf 'x%s\n' "$i" > "$R/repo-x/f$i.txt"
  git -C "$R/repo-x" add -A
  GIT_AUTHOR_DATE="@$((T0 + (i-1)*1170))" GIT_COMMITTER_DATE="@$((T0 + (i-1)*1170))" \
    git -C "$R/repo-x" commit -qm "Commit number $i" 2>/dev/null
done
export GW_LEDGER="$ROOT/l8.tsv"
( cd "$R/repo-x" && bash "$BIN" --backfill --root="$R" >/dev/null 2>&1 )
eq "AC6 backfill source" "commit-window" "$(tail -1 "$GW_LEDGER" | cut -f9)"
eq "AC6 backfill slug"   "commit-number-2" "$(tail -1 "$GW_LEDGER" | cut -f5)"
rep="$( cd "$R/repo-x" && bash "$BIN" --report 2>&1 )"
has "AC6 report names the seed unit" "seed unit" "$rep"
has "AC6 report shows n"             "n=1"       "$rep"

# A task sample below min_sample is labelled rather than presented as a median.
printf '{ "estimates": { "min_sample": 5 } }\n' > "$R/repo-x/.groundwork.json"
cat "$ROOT/l1.tsv" | tail -1 | sed 's/\tproj-a\t/\trepo-x\t/' >> "$GW_LEDGER"
rep="$( cd "$R/repo-x" && bash "$BIN" --report 2>&1 )"
has "AC6 small task sample flagged" "small sample" "$rep"

# --- wave 24: the engine records the row, once, when the checkpoint says the task shipped ---------
# A fresh project so the marker file and the checkpoint belong to this case alone.
D="$ROOT/proj-done"; project "$D"
DT="$GW_PROJECTS_DIR/$(key "$D")"
D0=$(( $(date +%s) - 3*86400 ))
transcript "$DT/s1.jsonl" "$D0" 10 30 >/dev/null
DSTARTED="$(date -u -r "$D0" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$D0" +%Y-%m-%dT%H:%M:%SZ)"
export GW_LEDGER="$ROOT/l9.tsv"

rows() { [ -f "$GW_LEDGER" ] && grep -c '	task	' "$GW_LEDGER" 2>/dev/null || printf '0'; }
state() { printf '# Task: Ship the receipt\n- Mode: %s\n- Level: L2\n- Started: %s\n' "$1" "$DSTARTED" \
  > "$D/.claude/groundwork/task-state.md"; }

state "Implementation"
( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
eq "W24 unfinished task, no row" "0" "$(rows)"

state "Done — shipped the receipt"
( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
eq "W24 done records once"       "1" "$(rows)"

( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
eq "W24 never twice"             "1" "$(rows)"

# The terminal marker is written in several shapes by hand; all of them mean the same thing.
printf '# Task: Ship the receipt\n- Mode: **DONE** — committed\n- Level: L2\n- Started: %s\n' "$DSTARTED" \
  > "$D/.claude/groundwork/task-state.md"
rm -f "$D/.claude/groundwork/ledger-recorded"
export GW_LEDGER="$ROOT/l10.tsv"
( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
eq "W24 emphasised DONE counts"  "1" "$(rows)"

# A new task with the same title is a new key, so its row is not swallowed by the old marker.
D1=$(( $(date +%s) - 2*86400 ))
transcript "$DT/s2.jsonl" "$D1" 10 30 >/dev/null
D1STARTED="$(date -u -r "$D1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$D1" +%Y-%m-%dT%H:%M:%SZ)"
printf '# Task: Ship the receipt\n- Mode: Done\n- Level: L2\n- Started: %s\n' "$D1STARTED" \
  > "$D/.claude/groundwork/task-state.md"
( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
eq "W24 second task, own row"    "2" "$(rows)"

# The opt-out and the fail-safe paths stay exactly as they are for every other mode.
printf '{ "runner": "host", "estimates": { "ledger": false } }\n' > "$D/.groundwork.json"
rm -f "$D/.claude/groundwork/ledger-recorded"
export GW_LEDGER="$ROOT/l11.tsv"
( cd "$D" && bash "$BIN" --record-if-done >/dev/null 2>&1 )
eq "W24 estimates.ledger=false"  "0" "$(rows)"

echo

echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
