#!/usr/bin/env bash
# Groundwork plugin :: executable proof for wave 40 — the gates judge where the work is, not the session's folder.
# Reproduces otaje, 2026-10-21 (E8): a session opened in `ra-devs-laravel-back`, an empty folder with no git,
# ran `cd <otaje lane> && git push origin HEAD:development` with a changed bootstrap/app.php, and nothing
# checked it. gw_repo.py · session-repos.py · in-cwd.sh · push-gate.py · lane-guard.py · suite-record.py ·
# pre-tool-guard.sh · the Stop gates · the estimate ledger. Run: bash hooks/tests/command-repo.sh
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }
pass=0; fail=0
ROOT="$(mktemp -d)"; ROOT="$(cd "$ROOT" && pwd -P)"; trap 'rm -rf "$ROOT"' EXIT
export GW_SESSIONS_DIR="$ROOT/sessions" GW_ROOT="$ROOT" GW_HOOKS="$HOOKS"
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok   %-60s [%s]\n' "$1" "$(printf '%s' "$3" | head -c 120)"
       else fail=$((fail+1)); printf '  FAIL %-60s\n         want "%s"\n          got "%s"\n' "$1" "$2" "$3"; fi; }
has() { if printf '%s' "$3" | grep -qF -- "$2"; then pass=$((pass+1)); printf '  ok   %-60s\n' "$1"
        else fail=$((fail+1)); printf '  FAIL %-60s no "%s" in: %s\n' "$1" "$2" "$(printf '%s' "$3" | head -c 400)"; fi; }

# --- otaje in miniature: a bare origin, the main checkout, a lane under .claude/worktrees, an empty folder ---
O="$ROOT/origin.git"; git init -q --bare -b development "$O"
P="$ROOT/shop"; git clone -q "$O" "$P" 2>/dev/null
W="$P/.claude/worktrees/admin-session-findings"
E="$ROOT/ra-devs-laravel-back"; mkdir -p "$E"
cd "$P" && git config user.email t@t && git config user.name t && git symbolic-ref HEAD refs/heads/development
mkdir -p app bootstrap bin tests/Feature database/migrations
printf '<?php class A { function a() { return 1; } }\n' > app/A.php
printf '<?php return 1;\n' > bootstrap/app.php
printf '<?php class ATest { function t() { (new A)->a(); } }\n' > tests/Feature/ATest.php
printf '<?php // shipped\n' > database/migrations/2026_01_01_000000_create_a.php
printf '.env\n.claude/\nstorage/\n' > .gitignore
printf '<phpunit><testsuites><testsuite name="F"><directory suffix="Test.php">./tests/Feature</directory></testsuite></testsuites></phpunit>\n' > phpunit.xml
printf '#!/bin/sh\necho "  Tests:    1 passed (1 assertions)"\n' > bin/phpunit
printf '#!/bin/sh\nif [ -f "%s/analyse.fail" ]; then echo "Line 1: A::a() has no return type"; exit 1; fi\necho "[OK] No errors"\n' "$ROOT" > bin/analyse
chmod +x bin/phpunit bin/analyse
printf '{ "runner": "host", "commands": { "test": "./bin/phpunit", "analyse": "./bin/analyse" } }\n' > .groundwork.json
git add -A && git commit -qm init && git push -q -u origin development 2>/dev/null
printf 'COMPOSE_PROJECT_NAME=shop\nDB_DATABASE=shop\n' > .env
python3 "$HOOKS/suite-record.py" --record >/dev/null           # development's code had its green whole run
git worktree add -q "$W" -b worktree-admin-session-findings origin/development 2>/dev/null
( cd "$W" && printf '<?php return 2; // guest pages redirect a signed-in admin\n' > bootstrap/app.php \
  && git commit -qam "E8: redirect a signed-in admin away from guest pages" )

push() { # session folder, command -> allow | deny (push-gate.py as the harness runs it: through in-cwd.sh)
  local out; out="$(jq -nc --arg c "$1" --arg cmd "$2" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$cmd}}' \
    | ( cd "$1" && bash "$HOOKS/in-cwd.sh" push-gate.py ))"
  [ -z "$out" ] && echo allow || printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; }
reason() { jq -nc --arg c "$1" --arg cmd "$2" '{cwd:$c, hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:$cmd}}' \
  | ( cd "$1" && bash "$HOOKS/in-cwd.sh" push-gate.py ) | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
dirs() { # session folder, command -> "command@directory|…", $ROOT written as R
  python3 -c '
import os, sys
sys.path.insert(0, os.environ["GW_HOOKS"])
import gw_repo as r
out = []
for c in r.commands(sys.argv[2], sys.argv[1]):
    name = os.path.basename(c.argv[0] or "?") if c.argv else "-"
    out.append("%s@%s%s" % (name, (c.dir or "?").replace(os.environ["GW_ROOT"], "R"), "" if r.writes(c) else ":r"))
print("|".join(out))' "$1" "$2"; }
w="R/shop/.claude/worktrees/admin-session-findings"; e="R/ra-devs-laravel-back"; p="R/shop"

echo "the line says where it runs:"
eq "cd <lane> && git push … | tail"                  "cd@$e:r|git@$w|tail@$w:r"     "$(dirs "$E" "cd $W && git push origin HEAD:development 2>&1 | tail -8")"
eq "cd, then a relative cd"                          "cd@$e:r|cd@$p:r|ls@$p/app:r"  "$(dirs "$E" "cd $P; cd app && ls")"
eq "a cd in a pipeline moves nothing after it"       "cd@$e:r|cat@$e:r|ls@$e:r"     "$(dirs "$E" "cd $P | cat; ls")"
eq "a subshell's cd ends with it"                    "cd@$e:r|git@$p:r|ls@$e:r"     "$(dirs "$E" "(cd $P && git status) && ls")"
eq "pushd / popd"                                    "pushd@$e:r|ls@$p:r|popd@$p:r|ls@$e:r" "$(dirs "$E" "pushd $P && ls && popd && ls")"
eq "W=<path>; cd \$W"                                "cd@$e:r|git@$w"               "$(dirs "$E" "L=$W; cd \$L && git push")"
eq "git -C, twice"                                   "git@$p/app:r"                 "$(dirs "$E" "git -C $P -C app status")"
eq "bash -c and bash <<EOF are read"                 "cd@$e:r|git@$w|bash@$e"       "$(dirs "$E" "bash -lc 'cd $W && git push'")"
eq "a here-document's body is not a command"         "cd@$e:r|git@$w|git@$w:r"      "$(dirs "$E" "cd $W && git commit -F - <<'EOF'
git push origin development
EOF
git log")"
eq "stdin-guard's wrapper"                           "true@$e:r|cd@$e:r|git@$w"     "$(dirs "$E" "true | (
cd $W && git push
)")"
eq "the commit template's here-document, a lone quote in it" "cd@$e:r|cat@$w:r|git@$w|git@$w" "$(dirs "$E" "cd $W && git commit -m \"\$(cat <<'EOF'
fix: don't (re)break it
EOF
)\" && git push origin HEAD:development")"
eq "a command substitution runs in the line's directory" "cd@$e:r|git@$w|echo@$w:r"   "$(dirs "$E" "cd $W && out=\$(git push origin HEAD:development 2>&1); echo \"\$out\"")"
eq "a variable the line does not set: unknown"       "cd@$e:r|git@?"                "$(dirs "$E" 'cd "$LANE" && git push')"
eq "a folder the line creates: what && chains after the cd" "cd@$e:r|git@R/nowhere"   "$(dirs "$E" "cd $ROOT/nowhere && git push")"
eq "…after a ; the cd may have failed: unknown"     "cd@$e:r|git@?"                "$(dirs "$E" "cd $ROOT/nowhere; git push")"
eq "cd A || cd B; …: A or B, unknown"                "cd@$e:r|cd@$w:r|git@?:r"      "$(dirs "$E" "cd $W || cd $P; git status")"
eq "[ … ] && cd …; …: unknown"                       "[@$e:r|cd@$e:r|ls@?:r"        "$(dirs "$E" "[ -d /nonexistent ] && cd $P; ls")"
eq "if cd …; then …: there; after fi: unknown"       "cd@$e:r|ls@$p:r|ls@?:r"       "$(dirs "$E" "if cd $P; then ls; fi; ls")"
eq "an else starts where its if started"             "false@$p:r|cd@$p:r|cd@$p:r|ls@$p/bootstrap:r|ls@?:r" "$(dirs "$P" "if false; then cd app; else cd bootstrap && ls; fi; ls")"
eq "a function's body runs where it is called"       "cd@?:r|ls@$e:r"               "$(dirs "$E" "f() { cd $P; }; ls")"
eq "\$(git rev-parse --show-toplevel) is computed"   "cd@$e:r|git@$w/app:r|cd@$w/app:r|git@$w" "$(dirs "$E" "cd $W/app && cd \"\$(git rev-parse --show-toplevel)\" && git push")"
eq "reading is not work; writing into a file is"     "cd@$e:r|grep@$p:r|echo@$p"    "$(dirs "$E" "cd $P && grep -r x app > /dev/null; echo x > note.txt")"

echo "push-gate — the push from an empty folder is the lane's push:"
r_lane="$(reason "$W" 'git push origin HEAD:development')"
eq "a session in the lane: deny"                     deny "$(push "$W" 'git push origin HEAD:development')"
has "…for the whole suite, naming bootstrap/app.php"  "shared files changed since the last verified code: bootstrap/app.php" "$r_lane"
eq "from the empty folder, cd <lane> && git push: deny" deny "$(push "$E" "cd $W && git push origin HEAD:development")"
eq "…with the same denial"                           "$r_lane" "$(reason "$E" "cd $W && git push origin HEAD:development")"
eq "the incident's own line (… 2>&1 | tail -8): the same denial" "$r_lane" "$(reason "$E" "cd $W && git push origin HEAD:development 2>&1 | tail -8")"
eq "git -C <lane> push: the same denial"             "$r_lane" "$(reason "$E" "git -C $W push origin HEAD:development")"
eq "L=<lane>; cd \$L && git push: the same denial"   "$r_lane" "$(reason "$E" "L=$W; cd \$L && git push origin HEAD:development")"
eq "the main checkout's own push is verified code"   allow "$(push "$P" 'git push origin HEAD:development')"
eq "…but cd <lane> from there pushes the lane's: the same denial" "$r_lane" "$(reason "$P" "cd $W && git push origin HEAD:development")"
eq "a feature branch from the lane: allowed"         allow "$(push "$E" "cd $W && git push -u origin feat/x")"
eq "a commit message naming a push is not a push"    allow "$(push "$E" "cd $W && git commit --allow-empty -qF - <<'EOF'
then git push origin HEAD:development
EOF")"
eq "commit by the template, a quote in its message, then push: the same denial" "$r_lane" "$(reason "$E" "cd $W && git commit --allow-empty -qm \"\$(cat <<'EOF'
fix: don't redirect twice
EOF
)\" && git push origin HEAD:development")"
eq "a push inside \$(…): the same denial"            "$r_lane" "$(reason "$E" "cd $W && out=\$(git push origin HEAD:development 2>&1); echo \"\$out\"")"
eq "a directory the line does not name: deny"        deny "$(push "$E" 'cd "$LANE" && git push origin HEAD:development')"
has "…asking for the path"                           'does not say which repository it runs in (after `cd "$LANE"`)' "$(reason "$E" 'cd "$LANE" && git push origin HEAD:development')"
eq "…from inside a project too"                      deny "$(push "$P" 'cd "$LANE" && git push origin HEAD:development')"
eq "…a bare git push after it: the branch is unknown" deny "$(push "$E" 'cd "$LANE" && git push')"
eq "…a feature branch after it: allowed"             allow "$(push "$E" 'cd "$LANE" && git push -u origin feat/x')"
eq "a push from a folder that is no repository: allowed" allow "$(push "$E" 'git push origin HEAD:development')"
( cd "$W" && python3 "$HOOKS/test-run.py" --for-push HEAD >/dev/null 2>&1 ); rc=$?
eq "test-run.py --for-push in the lane: green"       0 "$rc"
eq "…and the push from the empty folder is allowed"  allow "$(push "$E" "cd $W && git push origin HEAD:development")"
printf '<?php return 3;\n' > bootstrap/app.php; git commit -qam "bootstrap again"
eq "git push origin HEAD on development: deny"       deny "$(push "$P" 'git push origin HEAD')"
eq "cd A || cd <no repo>; git push: deny, not a guess" deny "$(push "$P" "cd $W || cd $E; git push origin HEAD:development")"
eq "a cd in a function never called: the push is here's" deny "$(push "$P" "f() { cd $E; }; git push origin development")"
eq "sudo git push: deny"                             deny "$(push "$P" 'sudo git push origin development')"
eq "gtimeout 60 git push: deny"                      deny "$(push "$P" 'gtimeout 60 git push origin development')"
eq "… | xargs git push origin: deny"                 deny "$(push "$P" 'echo development | xargs git push origin')"
eq "a branch the line does not name: judged as shared" deny "$(push "$P" 'git push origin "$BR"')"
eq "(( 1 << 2 )) is no here-document"                deny "$(push "$P" '(( x = 1 << 2 ))
git push origin development')"
eq "a repository the line creates, pushed: allowed"  allow "$(push "$E" "mkdir -p $ROOT/fresh && cd $ROOT/fresh && git init -q && git push -u origin main")"
eq "a bare git push on development: deny"            deny "$(push "$P" 'git push')"
git reset -q --hard HEAD~1

echo "lane-guard and the runner lock follow the line:"
lane() { local out; out="$(jq -nc --arg c "$1" --arg cmd "$2" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}' \
  | python3 "$HOOKS/lane-guard.py")"; [ -z "$out" ] && echo allow || printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; }
eq "cd <lane with no .env> && sail: deny"            deny  "$(lane "$E" "cd $W && ./vendor/bin/sail artisan test")"
eq "…without the cd, from the empty folder: allowed" allow "$(lane "$E" "./vendor/bin/sail artisan test")"
eq "…from the main checkout: allowed"                allow "$(lane "$E" "cd $P && ./vendor/bin/sail artisan test")"
Q="$ROOT/sailshop"; mkdir -p "$Q/vendor/bin" "$Q/database/migrations"
( cd "$Q" && git init -q && git config user.email t@t && git config user.name t
  printf '{ "runner": "sail" }\n' > .groundwork.json; printf '#!/bin/sh\nexit 0\n' > vendor/bin/sail; chmod +x vendor/bin/sail
  printf '<?php // shipped\n' > database/migrations/2026_01_01_000000_x.php; git add -A; git commit -qm init )
guard() { # session folder, payload -> exit code of pre-tool-guard.sh through in-cwd.sh
  printf '%s' "$2" | ( cd "$1" && bash "$HOOKS/in-cwd.sh" pre-tool-guard.sh >/dev/null 2>&1 ); echo $?; }
eq "cd <sail project> && php artisan: denied"        2 "$(guard "$E" "$(jq -nc --arg c "$E" --arg cmd "cd $Q && php artisan migrate" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}')")"
eq "…php in the empty folder itself: allowed"        0 "$(guard "$E" "$(jq -nc --arg c "$E" '{cwd:$c, tool_name:"Bash", tool_input:{command:"php -v"}}')")"
eq "an Edit of its shipped migration by path: denied" 2 "$(guard "$E" "$(jq -nc --arg c "$E" --arg f "$Q/database/migrations/2026_01_01_000000_x.php" '{cwd:$c, tool_name:"Edit", tool_input:{file_path:$f}}')")"
eq "cd <sail project> from inside another project: denied" 2 "$(guard "$P" "$(jq -nc --arg c "$P" --arg cmd "cd $Q && php artisan migrate" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}}')")"

echo "suite-record — a green run counts for the code it ran on:"
post() { jq -nc --arg c "$1" --arg cmd "$2" '{cwd:$c, tool_name:"Bash", tool_input:{command:$cmd}, tool_response:{stdout:"  Tests:    1 passed (1 assertions)", stderr:""}}' \
  | python3 "$HOOKS/suite-record.py"; }
printf '<?php class A { function a() { return 5; } }\n' > "$W/app/A.php"
printf '<?php class A { function a() { return 6; } }\n' > "$P/app/A.php"
post "$P" "cd $W && ./vendor/bin/sail artisan test"
check() { ( cd "$1" && python3 "$HOOKS/suite-record.py" --check WORKTREE >/dev/null; echo $? ); }
eq "from the main checkout, cd <lane> && artisan test: the lane's code" 0 "$(check "$W")"
eq "…not the main checkout's"                        1 "$(check "$P")"
post "$E" 'cd "$LANE" && ./vendor/bin/sail artisan test'
eq "a run whose directory is unknown records nothing" 1 "$(check "$P")"
git -C "$W" checkout -q -- app/A.php; git -C "$P" checkout -q -- app/A.php

echo "the registry — what the session changed outside its folder:"
pre() { # session, session folder, payload fields (jq) -> runs session-repos.py through in-cwd.sh
  jq -nc --arg s "$1" --arg c "$2" --arg t "$ROOT/projects/-x-ra-devs-laravel-back/$1.jsonl" "$3 + {session_id:\$s, cwd:\$c, transcript_path:\$t, hook_event_name:\"PreToolUse\"}" \
    | ( cd "$2" && bash "$HOOKS/in-cwd.sh" session-repos.py ); }
listed() { python3 "$HOOKS/session-repos.py" --list "$1" | sed "s#$ROOT#R#g" | tr '\n' ' ' | sed 's/ $//'; }
pre s-read "$E" "{tool_name:\"Bash\", tool_input:{command:\"cd $W && git status && git log -1 && ls\"}}"
eq "reading the lane is not remembered"              "" "$(listed s-read)"
pre s-edit "$E" "{tool_name:\"Edit\", tool_input:{file_path:\"$W/app/A.php\"}}"
eq "an Edit by absolute path is"                     "$w" "$(listed s-edit)"
pre s-bash "$E" "{tool_name:\"Bash\", tool_input:{command:\"cd $W && python3 -c pass\"}}"
eq "so is a command run there"                       "$w" "$(listed s-bash)"
pre s-bash "$E" "{tool_name:\"Write\", tool_input:{file_path:\"$W/app/B.php\"}}"
eq "…once"                                           "$w" "$(listed s-bash)"
pre s-home "$W" "{tool_name:\"Edit\", tool_input:{file_path:\"$W/app/A.php\"}}"
eq "the session's own folder is not"                 "" "$(listed s-home)"
pre s-other "$E" "{tool_name:\"Write\", tool_input:{file_path:\"$E/notes.md\"}}"
eq "nor a folder that is no Groundwork project"      "" "$(listed s-other)"

echo "the Stop gates run where the session worked:"
stop() { # mode hook session folder session [extra jq] -> stderr/stdout, then "rc=N"
  local out extra="${5:-}"; [ -n "$extra" ] || extra='{}'
  out="$(jq -nc --arg s "$4" --arg c "$3" --arg t "$ROOT/projects/-x-ra-devs-laravel-back/$4.jsonl" \
    "{session_id:\$s, cwd:\$c, transcript_path:\$t, hook_event_name:\"Stop\", stop_hook_active:false} + $extra" \
    | ( cd "$3" && bash "$HOOKS/in-cwd.sh" "$1" "$2" 2>&1 ); echo "rc=$?")"; printf '%s' "$out"; }
touch "$ROOT/analyse.fail"; printf '<?php class A { function a() { return 7; } }\n' > "$W/app/A.php"
out="$(stop --each-repo done-gate.sh "$E" s-edit)"
has "an unanalysable change in the lane blocks the session that made it" "rc=2" "$out"
has "…naming the lane"                               "groundwork: in $W — a repository this session changed from outside its folder:" "$out"
has "…with the gate's own verdict"                   "static analysis FAILED" "$out"
eq "a session that never touched the lane: nothing, as before" "rc=0" "$(stop --each-repo done-gate.sh "$E" s-read)"
printf '<?php class A { function a() { return 8; } }\n' > "$P/app/A.php"
out="$(stop --each-repo done-gate.sh "$P" s-edit)"
has "a session in a project, its own folder and the lane: both judged" "rc=2" "$out"
eq "…the lane's verdict headed, its own not"         "1" "$(printf '%s\n' "$out" | grep -c '^groundwork: in ')"
eq "…two verdicts"                                   "2" "$(printf '%s\n' "$out" | grep -c 'static analysis FAILED')"
rm -f "$ROOT/analyse.fail"; git -C "$P" checkout -q -- app/A.php
printf '<?php class A { function a() { return 9; } }\n' > "$W/app/A.php"; touch "$ROOT/analyse.fail"
FT="$(git -C "$W" rev-parse --path-format=absolute --git-common-dir)/follow-through/sessions"; mkdir -p "$FT"
printf '{"session_id":"other","cwd":"%s","heartbeat":%s}\n' "$(cd "$W" && pwd -P)" "$(date +%s)" > "$FT/other.json"
out="$(stop --each-repo done-gate.sh "$E" s-edit)"
has "another live session works in the lane now: its verdict is shown…" "another live session works there now" "$out"
has "…and does not block"                            "rc=1" "$out"
rm -rf "$FT" "$ROOT/analyse.fail"
eq "green in the lane: the stop goes through"        "rc=0" "$(stop --each-repo done-gate.sh "$E" s-edit)"
git -C "$W" checkout -q -- app/A.php
out="$(stop --first-repo coverage-claim.sh "$E" s-edit '{last_assistant_message:"Проверил выборочно, всё работает."}')"
has "a reply gate runs for a session outside any project" '"decision":"block"' "$out"
eq "…not for one that never worked in a project"    "rc=0" "$(stop --first-repo coverage-claim.sh "$E" s-read '{last_assistant_message:"Проверил выборочно, всё работает."}')"

echo "the estimate ledger finds the session's transcript where it is:"
export GW_LEDGER="$ROOT/ledger.tsv" GW_PROJECTS_DIR="$ROOT/projects"
now="$(date +%s)"; iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
T="$ROOT/projects/-x-ra-devs-laravel-back/s-edit.jsonl"; mkdir -p "$(dirname "$T")"
i=0; while [ "$i" -lt 41 ]; do printf '{"type":"assistant","timestamp":"%s.000Z"}\n' "$(iso $((now - 2400 + i * 30)) | sed 's/Z$//')" >> "$T"; i=$((i + 1)); done
mkdir -p "$W/.claude/groundwork"
printf '# Task: E8 guest pages\n- Mode: Done\n- Level: L2\n- Kind: fix\n- Started: %s\n' "$(iso $((now - 3600)))" > "$W/.claude/groundwork/task-state.md"
( cd "$W" && GW_SESSIONS_DIR="$ROOT/no-sessions" bash "$HOOKS/estimate-ledger.sh" --record-if-done 2>/dev/null )
eq "the lane's own transcript folders alone: nothing (as on 2026-10-21)" 0 "$( [ -f "$GW_LEDGER" ] && grep -c 'e8-guest-pages' "$GW_LEDGER" || echo 0)"
stop --each-repo ledger-record.sh "$E" s-edit >/dev/null
eq "the Stop of the session that did it records the task" "20" "$(grep 'e8-guest-pages' "$GW_LEDGER" | tail -1 | cut -f6)"
eq "…once"                                           "1" "$(grep -c 'e8-guest-pages' "$GW_LEDGER")"
( cd "$W" && bash "$HOOKS/estimate-ledger.sh" --record --kind=fix >/dev/null 2>&1 )
eq "--record run in the lane by hand finds it through the registry" "20" "$(grep 'e8-guest-pages' "$GW_LEDGER" | tail -1 | cut -f6)"

echo; echo "  passed: $pass, failed: $fail"; [ "$fail" -eq 0 ]
