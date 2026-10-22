#!/usr/bin/env bash
# Groundwork plugin :: executable proof for hooks/lane-idle.py (waves 36, 42). Docker is a stub that logs. ps and lsof
# are stubs too, so a case sees exactly the `claude` processes it names: ps gives the real pid/ppid table with only
# those pids named claude, lsof -p their folders, and lsof -c claude nothing — the kernel names a process by its file,
# and the CLI's file is named by its version.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-44s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-44s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }
REAL_PS="$(command -v ps)"
mkdir -p "$ROOT/bin"; printf '#!/bin/sh\necho "$@" >> "%s/docker.log"\n' "$ROOT" > "$ROOT/bin/docker"
cat > "$ROOT/bin/ps" <<EOF
#!/bin/sh
[ -f "$ROOT/ps.fail" ] && exit 1
"$REAL_PS" -A -o pid=,ppid= | awk -v want=" \$(tr '\n' ' ' < "$ROOT/claude.pids") " '
  { print \$1, \$2, (index(want, " " \$1 " ") ? "/opt/bin/claude" : "/opt/bin/other"); seen[\$1] = 1 }
  END { n = split(want, a, " "); for (i = 1; i <= n; i++) if (!(a[i] in seen)) print a[i], 1, "/opt/bin/claude" }'
EOF
cat > "$ROOT/bin/lsof" <<EOF
#!/bin/sh
list=\$(printf '%s\n' "\$@" | awk 'prev == "-p" { print } { prev = \$0 }')
[ -n "\$list" ] || exit 0
awk -v list=",\$list," '/^p/ { on = index(list, "," substr(\$0, 2) ",") > 0 } on' "$ROOT/lsof.out"
EOF
chmod +x "$ROOT/bin/docker" "$ROOT/bin/ps" "$ROOT/bin/lsof"; : > "$ROOT/claude.pids"; : > "$ROOT/lsof.out"
export GW_SESSIONS_DIR="$ROOT/gw-sessions"; mkdir -p "$GW_SESSIONS_DIR"
M="$ROOT/shop"; mkdir -p "$M" "$ROOT/empty"
( cd "$M" && git init -q && git config user.email t@t && git config user.name t && printf '{}\n' > .groundwork.json \
  && git add -A && git commit -qm init && git worktree add -q "$M/wt" -b lane && git worktree add -q "$M/wt2" -b lane2 )
printf 'COMPOSE_PROJECT_NAME=shop\n' > "$M/.env"
mkdir -p "$M/wt/.claude"; printf '{"compose_project":"shop_wt"}\n' > "$M/wt/.claude/lane.json"
mkdir -p "$M/wt2/.claude"; printf '{"compose_project":"shop_wt2"}\n' > "$M/wt2/.claude/lane.json"
REG="$M/.git/follow-through/sessions"; mkdir -p "$REG"
settle() { # the hook has exited, so every docker it started is running (Popen returns after the exec): let them finish
  if command -v pgrep >/dev/null 2>&1; then
    for _ in $(seq 40); do pgrep -f "$ROOT/bin/docker" >/dev/null || return 0; sleep 0.05; done
  else sleep 1; fi; }
end() { # folder [reason] of the closing session "s-end" → the docker calls its SessionEnd made, sorted, joined by ';'
  : > "$ROOT/docker.log"
  jq -nc --arg c "$1" --arg r "${2:-other}" '{session_id:"s-end", cwd:$c, hook_event_name:"SessionEnd", reason:$r}' \
  | PATH="$ROOT/bin:$PATH" python3 "$HOOKS/lane-idle.py"; settle; sort "$ROOT/docker.log" | paste -sd ';' -; }
entry() { # session tree [age in seconds] — that session's entry in follow-through's registry of the repository
  printf '{"session_id":"%s","cwd":"%s","heartbeat":%s}\n' "$1" "$2" "$(( $(date +%s) - ${3:-0} ))" > "$REG/$1.json"; }
worked() { # session root... — groundwork's registry: where that session changed something outside its folder
  local s="$1"; shift; : > "$GW_SESSIONS_DIR/$s.jsonl"
  for r in "$@"; do printf '{"repo":"%s","transcript":"","cwd":"%s","time":%s}\n' "$r" "$ROOT/empty" "$(date +%s)" \
    >> "$GW_SESSIONS_DIR/$s.jsonl"; done; }
act() { # session "root age-in-seconds"... — its activity file: when it last called into each project
  local s="$1" now; now=$(date +%s); shift
  { printf '{'; local sep=''; for r in "$@"; do printf '%s"%s":%s' "$sep" "${r% *}" "$(( now - ${r##* } ))"; sep=','; done
    printf '}\n'; } > "$GW_SESSIONS_DIR/$s.activity.json"; }
procs() { # "pid cwd"... — the `claude` processes and their folders; $$, an ancestor of the hook, is the closing session's
  : > "$ROOT/lsof.out"; : > "$ROOT/claude.pids"
  for p in "$@"; do printf 'p%s\nfcwd\nn%s\n' "${p%% *}" "${p#* }" >> "$ROOT/lsof.out"; echo "${p%% *}" >> "$ROOT/claude.pids"; done; }

echo "lane-idle:"
eq "last session closes: lane stopped"      "compose -p shop_wt stop" "$(end "$M/wt")"
entry other "$M/wt"
eq "another live session: lane kept"        ""  "$(end "$M/wt")"
entry other "$M/wt" 7200
eq "stale sibling entry: lane stopped"      "compose -p shop_wt stop" "$(end "$M/wt")"
rm -f "$REG/other.json"
procs "$$ $M/wt"
eq "its own claude process: lane stopped"   "compose -p shop_wt stop" "$(end "$M/wt")"
procs "$$ $M/wt" "999999 $M/wt"
eq "another claude process: lane kept"      ""  "$(end "$M/wt")"
procs "999999 $M/wt"
eq "own process unknown: one taken for it"  "compose -p shop_wt stop" "$(end "$M/wt")"
procs
printf '{"compose_project":"shop"}\n' > "$M/wt/.claude/lane.json"
eq "lane.json naming main stack: kept"      ""  "$(end "$M/wt")"
printf '{"compose_project":"shop_wt"}\n' > "$M/wt/.claude/lane.json"
printf '{"gates":{"lane_idle_stop":false}}\n' > "$M/wt/.groundwork.json"
eq "opt-out honoured"                       ""  "$(end "$M/wt")"
eq "main checkout (no lane.json): nothing"  ""  "$(end "$M")"

echo; echo "lane-idle, a lane the session worked in from outside its folder (wave 42):"
printf '{}\n' > "$M/wt/.groundwork.json"
worked s-end "$M/wt2"
entry s-end "$M"  # its own entry, in the main checkout
eq "closes last in the main checkout: stopped" "compose -p shop_wt2 stop" "$(end "$M")"
entry s-end "$M/wt2"  # its entry from outside: follow-through's SessionEnd, running alongside, may not have removed it
eq "closes last from an empty folder: stopped" "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
entry other "$M/wt2"
eq "another live session there: kept"       ""  "$(end "$ROOT/empty")"
entry other "$M/wt2" 7200
eq "its entry stale: stopped"               "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
mkdir -p "$M/wt2/app"; entry other "$M/wt2/app"
eq "another live session in a folder of it: kept" "" "$(end "$ROOT/empty")"
git -C "$M" worktree add -q "$M/wt2/.claude/worktrees/x" -b nested
mkdir -p "$M/wt2/.claude/worktrees/x/.claude"; printf '{"compose_project":"shop_x"}\n' > "$M/wt2/.claude/worktrees/x/.claude/lane.json"
entry other "$M/wt2/.claude/worktrees/x"
eq "one in a lane nested in it: stopped"    "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
git init -q "$M/wt2/frontend"; entry other "$M/wt2/frontend"
eq "one in a clone inside it: kept"         ""  "$(end "$ROOT/empty")"
rm -f "$REG/other.json"
procs "999999 $M/wt2"
eq "a claude process there: kept"           ""  "$(end "$ROOT/empty")"
procs "999999 $M/wt2/app"
eq "a claude process in a folder of it: kept" "" "$(end "$ROOT/empty")"
procs "$$ $M/wt2"
eq "its own process there: not counted"     "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
procs

echo; echo "lane-idle, who still calls into the lane (wave 42):"
act main-s "$M/wt2 300"
eq "another session called there 5 min ago: kept" "" "$(end "$ROOT/empty")"
act main-s "$M/wt2 2700"
eq "…45 min ago: stopped"                   "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
act main-s "$M/wt2 3600" "$M/wt 0"
eq "an hour ago, in another lane now: stopped" "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
entry main-s "$M"; worked main-s "$M/wt2"; act main-s "$M/wt2 3600" "$M 0"
eq "registry names it, no call for an hour: stopped" "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
entry main-s "$M" 7200; act main-s "$M/wt2 60"  # its subagent's calls: the entry is quiet, the file is not
eq "a quiet entry, a call a minute ago: kept" "" "$(end "$ROOT/empty")"
act main-s "$M/wt2/app 0"
eq "a call in a folder of it: kept"         ""  "$(end "$ROOT/empty")"
act main-s "$M/wt2/.claude/worktrees/x 0"
eq "a call in a lane nested in it: stopped" "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
rm -f "$GW_SESSIONS_DIR/main-s.activity.json" "$REG/main-s.json"
eq "that session ended (no file): stopped"  "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
printf '{"%s":"soon","x":1,"":5}\n' "$M/wt2" > "$GW_SESSIONS_DIR/junk.activity.json"; printf '[1]\n' > "$GW_SESSIONS_DIR/list.activity.json"
eq "broken activity files: ignored"         "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
rm -f "$GW_SESSIONS_DIR/junk.activity.json" "$GW_SESSIONS_DIR/list.activity.json"

echo; echo "lane-idle, the closing session's own lanes (wave 42):"
act s-end "$M/wt2 0"
eq "its own calls there are no other's: stopped" "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
eq "…and its activity file is gone"         "gone" "$([ -e "$GW_SESSIONS_DIR/s-end.activity.json" ] && echo kept || echo gone)"
worked s-end; act s-end "$M/wt2 600" "$M 0"
eq "a lane it moved into, then left: stopped" "compose -p shop_wt2 stop" "$(end "$M")"
worked s-end "$M/wt2"; printf '{"repo":5}\n{"repo":"%s/gone"}\n' "$ROOT" >> "$GW_SESSIONS_DIR/s-end.jsonl"
eq "broken registry lines: skipped"         "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
printf '{"%s":"soon"}\n' "$M/wt" > "$GW_SESSIONS_DIR/s-end.activity.json"
eq "its own broken activity file: ignored"  "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
act s-end "$M/wt2 0"; chmod a-w "$GW_SESSIONS_DIR"
eq "its own file left behind: no other's"   "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
chmod u+w "$GW_SESSIONS_DIR"; rm -f "$GW_SESSIONS_DIR/s-end.activity.json"
worked s-end "$M/wt2"
eq "/clear: its folder's lane kept, the other judged" "compose -p shop_wt2 stop" "$(end "$M/wt" clear)"
eq "/resume: the same"                      "compose -p shop_wt2 stop" "$(end "$M/wt" resume)"
procs "$$ $M/wt2"
eq "/clear: its process goes on, as anyone's" "" "$(end "$M" clear)"
procs; touch "$ROOT/ps.fail"
eq "processes cannot be read: nothing stopped" "" "$(end "$ROOT/empty")"
rm -f "$ROOT/ps.fail"
worked s-end "$M"
eq "remembered main checkout: nothing"      ""  "$(end "$ROOT/empty")"
worked s-end "$ROOT/gone" "$M/wt2"
eq "remembered folder gone: skipped"        "compose -p shop_wt2 stop" "$(end "$ROOT/empty")"
printf '{"compose_project":"shop"}\n' > "$M/wt2/.claude/lane.json"
eq "lane naming the main stack: kept"       ""  "$(end "$ROOT/empty")"
printf '{"compose_project":"shop_wt2"}\n' > "$M/wt2/.claude/lane.json"
printf '{"gates":{"lane_idle_stop":false}}\n' > "$M/wt2/.groundwork.json"
eq "the lane's own opt-out: kept"           ""  "$(end "$ROOT/empty")"
printf '{}\n' > "$M/wt2/.groundwork.json"
worked s-end "$M/wt2" "$M/wt"
eq "its folder's lane and the other: both"  "compose -p shop_wt stop;compose -p shop_wt2 stop" "$(end "$M/wt")"
printf '{"gates":{"lane_idle_stop":false}}\n' > "$M/wt/.groundwork.json"
eq "its folder's opt-out: that lane only"   "compose -p shop_wt2 stop" "$(end "$M/wt")"
echo; echo "  passed: $pass, failed: $fail"; [ "$fail" -eq 0 ]
