#!/usr/bin/env bash
# Groundwork plugin :: executable proof for wave 43 — a session running an out-of-date hook list says so
# (hooks/gw_registration.py, hooks/in-cwd.sh --registration). The check cases run a copy of the hooks folder, so
# hooks.json changes under a "session" the way a release changes it under a running one.
# Run: bash hooks/tests/registration.sh
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required for these tests"; exit 1; }
unset CLAUDE_PLUGIN_ROOT                                  # the harness's, if a hook ever runs this
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-60s [%s]\n' "$1" "$3"
       else fail=$((fail+1)); printf '  FAIL %-60s want "%s", got "%s"\n' "$1" "$2" "$3"; fi; }
reg() { python3 "$HOOKS/gw_registration.py" "$@"; }
has() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }
begins() { case "$2" in "$1"*) echo yes ;; *) echo no ;; esac; }
same() { if [ "$1" = "$2" ]; then echo same; else printf 'differs: %s <> %s' "$1" "$2"; fi; }

echo "the id (GW43-AC7):"
eq "hooks.json declares the id of its content"            0 "$(reg check "$HOOKS/hooks.json" >/dev/null; echo $?)"
eq "one command carries an id"                            1 "$(jq '[.hooks[][].hooks[] | select(.command | test("--registration "))] | length' "$HOOKS/hooks.json")"
eq "it is the UserPromptSubmit command, before the hook"  1 "$(jq '[.hooks.UserPromptSubmit[].hooks[] | select(.command | test("in-cwd.sh\" --registration [0-9a-f]{12} task-intent.sh$"))] | length' "$HOOKS/hooks.json")"

J="$ROOT/j"; mkdir -p "$J"
cp "$HOOKS/effort.ts" "$J/"
base="$(reg ident "$HOOKS/hooks.json")"
variant() { jq "$1" "$HOOKS/hooks.json" > "$J/hooks.json"; reg ident "$J/hooks.json"; }
eq "whitespace does not change it"                        "$base" "$(variant '.')"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump(d, open(sys.argv[2], "w"), indent=7, sort_keys=True)' \
  "$HOOKS/hooks.json" "$J/hooks.json"
eq "key order does not change it"                         "$base" "$(reg ident "$J/hooks.json")"
eq "the id's own value does not change it"                "$base" "$(variant '.hooks.UserPromptSubmit[0].hooks[0].command |= sub("--registration [0-9a-f]+"; "--registration 000000000000")')"
eq "a changed flag changes it"                            yes "$([ "$(variant '.hooks.Stop[0].hooks[0].command |= sub("--each-repo"; "--first-repo")')" != "$base" ] && echo yes || echo no)"
eq "a changed matcher changes it"                         yes "$([ "$(variant '.hooks.PreToolUse[0].matcher = "Bash|Edit"')" != "$base" ] && echo yes || echo no)"
eq "a changed status message changes it"                  yes "$([ "$(variant '.hooks.Stop[0].hooks[0].statusMessage = "x"')" != "$base" ] && echo yes || echo no)"
eq "a removed event changes it"                           yes "$([ "$(variant 'del(.hooks.SessionEnd)')" != "$base" ] && echo yes || echo no)"
eq "a hook added changes it"                              yes "$([ "$(variant '.hooks.Stop[1].hooks += [{"type":"command","command":"x"}]')" != "$base" ] && echo yes || echo no)"
cp "$HOOKS/hooks.json" "$J/hooks.json"
eq "the copy gives the same id"                           "$base" "$(reg ident "$J/hooks.json")"
printf '\n// changed\n' >> "$J/effort.ts"
eq "a changed hooks module changes it"                    yes "$([ "$(reg ident "$J/hooks.json")" != "$base" ] && echo yes || echo no)"
rm "$J/effort.ts"
missing="$(reg ident "$J/hooks.json")"
eq "a missing module still gives an id, another one"      yes "$([ -n "$missing" ] && [ "$missing" != "$base" ] && echo yes || echo no)"
cp "$HOOKS/effort.ts" "$J/"
printf 'not json' > "$J/broken.json"
eq "a file that is not JSON gives none"                   "1:" "$(out="$(reg ident "$J/broken.json")"; echo "$?:$out")"

jq '.hooks.Stop[0].hooks[0].statusMessage = "x"' "$HOOKS/hooks.json" > "$J/hooks.json"
eq "a changed list with the old id fails check"           1 "$(reg check "$J/hooks.json" >/dev/null; echo $?)"
eq "check names the command that fixes it"                yes "$(has "gw_registration.py stamp" "$(reg check "$J/hooks.json")")"
new="$(reg stamp "$J/hooks.json")"
eq "stamp writes the content's id"                        "$(reg ident "$J/hooks.json")" "$new"
eq "after stamp, check passes"                            0 "$(reg check "$J/hooks.json" >/dev/null; echo $?)"
cp "$J/hooks.json" "$J/stamped.json"; reg stamp "$J/hooks.json" >/dev/null
eq "stamp twice: the same file"                           same "$(cmp -s "$J/hooks.json" "$J/stamped.json" && echo same || echo differs)"
eq "stamp touched only the id"                            same "$(same \
  "$(jq -c 'walk(if type == "string" then sub("--registration [0-9a-f]+"; "--registration ID") else . end)' "$J/hooks.json")" \
  "$(jq -c '.hooks.Stop[0].hooks[0].statusMessage = "x" | walk(if type == "string" then sub("--registration [0-9a-f]+"; "--registration ID") else . end)' "$HOOKS/hooks.json")")"
jq '.hooks.Stop[0].hooks[0].command += " --registration 0"' "$HOOKS/hooks.json" > "$J/two.json"; reg stamp "$J/two.json" >/dev/null
eq "two commands with the content's id pass check"        0 "$(reg check "$J/two.json" >/dev/null; echo $?)"
sed -E 's/(done-gate.sh --registration )[0-9a-f]+/\10123456789ab/' "$J/two.json" > "$J/two-ids.json"
eq "two commands with two ids fail it"                    1 "$(reg check "$J/two-ids.json" >/dev/null; echo $?)"

# --- the check, on a copy of the plugin ---------------------------------------------------------------------------
P="$ROOT/plugin"; mkdir -p "$P"; cp -R "$HOOKS" "$P/hooks"; rm -rf "$P/hooks/tests"; H="$P/hooks"
ID="$(reg ident "$H/hooks.json")"
export GW_SESSIONS_DIR="$ROOT/sessions"
PLAIN="$ROOT/plain"; mkdir -p "$PLAIN"                     # no git, no .groundwork.json
G="$ROOT/proj"; mkdir -p "$G"; ( cd "$G" && git init -q && printf '{ "runner": "host" }\n' > .groundwork.json )
TASK="Сделай отчёт по заказам за прошлый месяц для бухгалтерии"

ask() { # plugin-hooks session folder prompt [in-cwd args] -> in-cwd.sh's stdout, then rc=<code>
  local h="$1" sid="$2" d="$3" text="$4"; shift 4
  jq -nc --arg s "$sid" --arg c "$d" --arg p "$text" '{session_id:$s, cwd:$c, hook_event_name:"UserPromptSubmit", prompt:$p}' \
    | ( cd "$d" && CLAUDE_PLUGIN_ROOT="$(dirname "$h")" bash "$h/in-cwd.sh" "$@" task-intent.sh ); echo "rc=$?"
}
body()   { printf '%s\n' "$1" | sed '$d'; }
rcof()   { printf '%s\n' "$1" | tail -1; }
sysmsg() { body "$1" | jq -r '.systemMessage // empty' 2>/dev/null; }
ctx()    { body "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
marker() { cat "$GW_SESSIONS_DIR/$1.registration" 2>/dev/null || echo none; }

echo
echo "a current list (GW43-AC1):"
out="$(ask "$H" c1 "$PLAIN" hi --registration "$ID")"
eq "no answer outside a project"                          "" "$(body "$out")"
eq "exit 0"                                               rc=0 "$(rcof "$out")"
eq "no marker written"                                    none "$(marker c1)"
plain_answer="$(jq -nc --arg c "$G" --arg p "$TASK" '{session_id:"c2", cwd:$c, hook_event_name:"UserPromptSubmit", prompt:$p}' \
  | ( cd "$G" && bash "$H/in-cwd.sh" task-intent.sh ))"
out="$(ask "$H" c3 "$G" "$TASK" --registration "$ID")"
eq "task-intent's answer as it was"                       same "$(same "$plain_answer" "$(body "$out")")"
eq "and it is task-intent's reminder"                     yes "$(has "reads like a task statement" "$plain_answer")"

echo
echo "an out-of-date list (GW43-AC2, AC3):"
out="$(ask "$H" s1 "$PLAIN" hi)"
eq "a list with no id: the user is told"                  yes "$(has "Run /reload-plugins in this session, or reopen it." "$(sysmsg "$out")")"
eq "the user's line names the plugin"                     yes "$(has "groundwork's hooks changed" "$(sysmsg "$out")")"
eq "the agent is told, with both ids"                     yes "$(has "(loaded: none, a list from before this check existed; on disk: $ID)" "$(ctx "$out")")"
eq "the agent is told to tell the user"                   yes "$(has "Tell the user in one line, before anything else" "$(ctx "$out")")"
eq "exit 0"                                               rc=0 "$(rcof "$out")"
eq "the marker holds the id on disk"                      "$ID" "$(marker s1)"
eq "the same session's next prompt: nothing"              "" "$(body "$(ask "$H" s1 "$PLAIN" hi)")"
eq "and the one after"                                    "" "$(body "$(ask "$H" s1 "$PLAIN" again)")"
out="$(ask "$H" s2 "$PLAIN" hi --registration 0123456789ab)"
eq "another id loaded: told, naming it"                   yes "$(has "(loaded: 0123456789ab; on disk: $ID)" "$(ctx "$out")")"
eq "after /reload-plugins (the id on disk): nothing"      "" "$(body "$(ask "$H" s2 "$PLAIN" hi --registration "$ID")")"
eq "another session: told once"                           yes "$(has "/reload-plugins" "$(sysmsg "$(ask "$H" s3 "$PLAIN" hi)")")"
eq "then nothing"                                         "" "$(body "$(ask "$H" s3 "$PLAIN" hi)")"
jq '.hooks.Stop[0].hooks[0].statusMessage = "changed again"' "$H/hooks.json" > "$H/hooks.json.new" && mv "$H/hooks.json.new" "$H/hooks.json"
ID2="$(reg stamp "$H/hooks.json")"
out="$(ask "$H" s1 "$PLAIN" hi)"
eq "another change on disk: told again"                   yes "$(has "on disk: $ID2" "$(ctx "$out")")"
eq "the marker follows it"                                "$ID2" "$(marker s1)"
out="$(ask "$H" s4 "$PLAIN" hi --registration "$ID")"
eq "a session that loaded the first id: told"             yes "$(has "(loaded: $ID; on disk: $ID2)" "$(ctx "$out")")"
eq "a session that reloaded: nothing"                     "" "$(body "$(ask "$H" s5 "$PLAIN" hi --registration "$ID2")")"
ask "$H" s6 "$PLAIN" hi >/dev/null; ask "$H" s7 "$PLAIN" hi >/dev/null
eq "two sessions told: the first stays told"              "" "$(body "$(ask "$H" s6 "$PLAIN" hi)")"
printf '%s\n' "$ID" > "$GW_SESSIONS_DIR/old.registration"
python3 -c 'import os, sys, time; t = time.time() - 40 * 86400; os.utime(sys.argv[1], (t, t))' "$GW_SESSIONS_DIR/old.registration"
ask "$H" s8 "$PLAIN" hi >/dev/null
eq "a new notice drops a month-old marker, keeps the rest" none:"$ID2" "$(marker old):$(marker s6)"
out="$(jq -nc --arg c "$G" '{session_id:"o1", cwd:$c, hook_event_name:"SessionStart", source:"startup"}' \
  | ( cd "$G" && CLAUDE_PLUGIN_ROOT="$P" bash "$H/in-cwd.sh" session-start.sh ))"
want="$(jq -nc --arg c "$G" '{session_id:"o1", cwd:$c, hook_event_name:"SessionStart", source:"startup"}' \
  | ( cd "$G" && bash "$H/in-cwd.sh" session-start.sh ))"
eq "another hook on an old list: its answer as it was"    same "$(same "$want" "$out")"

echo
echo "the hook's own answer survives (GW43-AC4):"
out="$(ask "$H" m1 "$G" "$TASK")"
c="$(ctx "$out")"
eq "the notice and task-intent's reminder, both"          yes:yes "$(has "out-of-date list of groundwork's hooks" "$c"):$(has "reads like a task statement" "$c")"
eq "the notice first"                                     yes "$(begins "groundwork: this session runs an out-of-date list" "$c")"
eq "the event is named"                                   UserPromptSubmit "$(body "$out" | jq -r '.hookSpecificOutput.hookEventName')"
S="$ROOT/stub"; mkdir -p "$S"; cp -R "$H" "$S/hooks"
printf 'echo "plain words"\n' > "$S/hooks/task-intent.sh"
out="$(ask "$S/hooks" p1 "$PLAIN" hi)"
eq "plain stdout from the hook: kept as context"          yes:yes "$(has "out-of-date list" "$(ctx "$out")"):$(has "plain words" "$(ctx "$out")")"
printf 'echo "it broke"; exit 3\n' > "$S/hooks/task-intent.sh"
out="$(ask "$S/hooks" p2 "$PLAIN" hi)"
eq "a hook that fails keeps its exit code"                rc=3 "$(rcof "$out")"
eq "and its output, with no notice"                       "it broke" "$(body "$out")"
eq "and is not marked as told"                            none "$(marker p2)"
printf '%s\n' '{"decision":"block","reason":"r","systemMessage":"own"}' > "$S/hooks/answer.json"
printf 'cat "%s"\n' "$S/hooks/answer.json" > "$S/hooks/task-intent.sh"
out="$(ask "$S/hooks" p3 "$PLAIN" hi)"
eq "the hook's decision and message are kept"             "block:yes" "$(body "$out" | jq -r '.decision'):$(has "own" "$(sysmsg "$out")")"

echo
echo "fail-open (GW43-AC5):"
out="$(printf '{"session_id":"f1","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$PLAIN" | ( cd "$PLAIN" && bash "$H/in-cwd.sh" task-intent.sh ); echo "rc=$?")"
eq "not started by the harness (no CLAUDE_PLUGIN_ROOT)"   rc=0 "$out"
out="$(printf '{"cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$PLAIN" | ( cd "$PLAIN" && CLAUDE_PLUGIN_ROOT="$P" bash "$H/in-cwd.sh" task-intent.sh ); echo "rc=$?")"
eq "no session id: nothing"                               rc=0 "$out"
out="$(printf 'not json' | ( cd "$PLAIN" && CLAUDE_PLUGIN_ROOT="$P" bash "$H/in-cwd.sh" task-intent.sh ); echo "rc=$?")"
eq "a payload that is not JSON: nothing"                  rc=0 "$out"
N="$ROOT/noid"; mkdir -p "$N"; cp -R "$HOOKS" "$N/hooks"; rm -rf "$N/hooks/tests"
sed 's/ --registration [0-9a-f]*//' "$HOOKS/hooks.json" > "$N/hooks/hooks.json"
eq "no id in hooks.json: nothing"                         rc=0 "$(ask "$N/hooks" f2 "$PLAIN" hi)"
rm "$N/hooks/hooks.json"
eq "no hooks.json: nothing"                               rc=0 "$(ask "$N/hooks" f3 "$PLAIN" hi)"
NP="$ROOT/nopython"; mkdir -p "$NP"; printf '#!/bin/sh\nexit 127\n' > "$NP/python3"; chmod +x "$NP/python3"
out="$(PATH="$NP:$PATH" ask "$H" f4 "$G" "$TASK")"
eq "no python3: the hook's answer as it was"              same "$(same "$plain_answer" "$(body "$out")")"
eq "exit 0"                                               rc=0 "$(rcof "$out")"
printf 'a file' > "$ROOT/not-a-folder"
out="$(GW_SESSIONS_DIR="$ROOT/not-a-folder" ask "$H" f5 "$PLAIN" hi)"
eq "an unwritable marker folder: told all the same"       yes:rc=0 "$(has "/reload-plugins" "$(sysmsg "$out")"):$(rcof "$out")"
out="$(printf '{"session_id":"f6","hook_event_name":"Stop"}' | GW_HOOK_OUTPUT='{"a":1}' CLAUDE_PLUGIN_ROOT="$P" \
  python3 "$H/gw_registration.py" warn groundwork "$H/hooks.json" "" "$ROOT/sessions")"
eq "warn on another event: the output as it was"          '{"a":1}' "$out"
out="$(printf '{"session_id":"../x","hook_event_name":"UserPromptSubmit"}' | GW_HOOK_OUTPUT='' CLAUDE_PLUGIN_ROOT="$P" \
  python3 "$H/gw_registration.py" warn groundwork "$H/hooks.json" "" "$ROOT/sessions")"
eq "a session id that is no file name: nothing written"   ":no" "$out:$([ -e "$ROOT/x.registration" ] && echo yes || echo no)"

echo
echo "cost (GW43-AC6) — programs a prompt starts:"
SHIM="$ROOT/shim"; mkdir -p "$SHIM"; LOG="$ROOT/exec.log"
for t in python3 jq cat grep sed awk head tail tr wc cut cmp shasum md5 openssl cksum sha256sum stat; do
  real="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$t" "$LOG" "$real" > "$SHIM/$t"; chmod +x "$SHIM/$t"
done
starts() { # session [in-cwd args] -> how many of those programs one prompt started (HOOK_FOR_RUN: another hook)
  local sid="$1"; shift
  local payload; payload="$(jq -nc --arg s "$sid" --arg c "$PLAIN" '{session_id:$s, cwd:$c, hook_event_name:"UserPromptSubmit", prompt:"hi"}')"
  : > "$LOG"
  printf '%s' "$payload" | ( cd "$PLAIN" && PATH="$SHIM:$PATH" CLAUDE_PLUGIN_ROOT="${ROOT_FOR_RUN-$P}" bash "$H/in-cwd.sh" "$@" "${HOOK_FOR_RUN:-task-intent.sh}" ) >/dev/null
  wc -l < "$LOG" | tr -d ' '
}
off="$(ROOT_FOR_RUN='' starts k1 --registration "$ID2")"
eq "a current list starts nothing more than no check"     "$off" "$(starts k2 --registration "$ID2")"
starts k3 >/dev/null                                       # told once
eq "a list already told starts nothing more either"       "$off" "$(starts k3)"
eq "the first notice starts python3 once"                 "$((off + 1))" "$(starts k4)"
eq "no CLAUDE_PLUGIN_ROOT, an old list: nothing more"     "$off" "$(ROOT_FOR_RUN='' starts k5)"
eq "another hook on an old list: nothing more"            "$(ROOT_FOR_RUN='' HOOK_FOR_RUN=session-start.sh starts k6)" "$(HOOK_FOR_RUN=session-start.sh starts k7)"

echo
echo "  passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
