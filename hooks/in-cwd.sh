#!/usr/bin/env bash
# Groundwork plugin :: run a hook where the work is, not in the directory the session started in.
#
#   in-cwd.sh [--each-repo|--first-repo] <hook file> — reads the hook payload from stdin, enters the directory
#   the hook should judge, and hands the same payload to the hook on stdin.
#
# Every gate resolves `.groundwork.json` and `.claude/groundwork/…` relative to its working directory. The
# harness starts hook processes in the directory the session was opened in; a session opened in the main
# checkout that then works in a worktree therefore had every gate read the MAIN checkout — another task's
# checkpoint (pre-tool-guard refusing edits «in Discovery mode»), another tree's diff (OpenAPI and handoff
# gates blocking on files the session never touched), another tree's suite. The payload's `cwd` is where the
# session actually is (wave 36).
#
# Wave 40: the session's folder is not where the work is either, when the session works elsewhere through
# `cd <lane> && …` or edits files there by absolute path (project A, 2026-10-21: a push to development from a session
# opened in an empty folder, no check at all). So, through session-repos.py (gw_repo.py):
#   * a Bash / Edit / Write hook runs in the repository the call works in — the line's own `cd` / `git -C`,
#     or the file's path; the payload is passed unchanged;
#   * --each-repo (the Stop gates that judge a working tree) runs the hook in the session's folder and in every
#     Groundwork repository the session changed outside it, in parallel; each verdict from such a repository is
#     headed with its path, and the exit code is the strictest one (2 over 1 over 0) — except from a repository
#     another live session works in now: its changes may be that session's, so its verdict is shown, not blocking;
#   * --first-repo (the gates that judge the reply) runs once: in the session's project, or — when its folder
#     is none — in the first repository it worked in.
# A hook run for another directory gets that directory as the payload's `cwd`.
#
# Wave 43: `--registration <id>` (the UserPromptSubmit command) is the id of the hooks.json this session loaded —
# Claude Code reads that file at a session's start and on /reload-plugins only, this script at every call. When the
# id hooks.json carries on disk is another one, or the command carries none (a list loaded before 0.52.0), the
# prompt's answer gets a notice that the session runs an out-of-date list (gw_registration.py), once per change.
#
# Fail-safe: no payload, no python3, or no answer → the hook runs in the payload's `cwd`, exactly as before; no
# `cwd`, or one that is not a directory → where it was started.
set -uo pipefail

mode=''
loaded=''
while [ $# -gt 0 ]; do
  case "$1" in
    --each-repo|--first-repo) mode="${1#--}"; mode="${mode%-repo}"; shift ;;
    --registration) loaded="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    *) break ;;
  esac
done
hook="${1:-}"
dir="$(cd "$(dirname "$0")" && pwd)"
[ -n "$hook" ] && [ -f "$dir/$hook" ] || exit 0

payload="$(cat 2>/dev/null || true)"
cwd=""
if [ -n "$payload" ]; then
  if command -v jq >/dev/null 2>&1; then
    cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
  else
    cwd="$(printf '%s' "$payload" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd") or "")' 2>/dev/null || true)"
  fi
fi

run() { # payload -> the hook, with its own stdout, stderr and exit code
  case "$hook" in
    *.py) printf '%s' "$1" | python3 "$dir/$hook" ;;
    *)    printf '%s' "$1" | bash "$dir/$hook" ;;
  esac
}

# Wave 43: is the list this session runs the one on disk? Read by bash itself (`$(<file)`, under a millisecond), so a
# current session's prompt starts no program for it; a session already told about this list passes by its marker.
stale=''
sessions="${GW_SESSIONS_DIR:-${HOME:-}/.claude/groundwork/sessions}"
if [ "$hook" = task-intent.sh ] && [ -z "$mode" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -r "$dir/hooks.json" ]; then
  text="$(<"$dir/hooks.json")"; re='--registration ([0-9a-f]+)'
  if [[ $text =~ $re ]] && [ "${BASH_REMATCH[1]}" != "$loaded" ]; then
    stale="${BASH_REMATCH[1]}"
    re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9._-]+)"'
    said=''
    if [[ $payload =~ $re ]]; then
      marker="$sessions/${BASH_REMATCH[1]}.registration"
      [ -r "$marker" ] && { IFS= read -r said < "$marker" || true; }
      [ "$said" = "$stale" ] && stale=''
    fi
  fi
fi

run_checked() { # payload -> the hook; its answer carries the notice when the list is out of date and not yet told
  [ -n "$stale" ] || { run "$1"; return $?; }
  local out rc merged=''
  out="$(run "$1")"; rc=$?
  [ "$rc" -eq 0 ] && merged="$(printf '%s' "$1" | GW_HOOK_OUTPUT="$out" \
    python3 "$dir/gw_registration.py" warn groundwork "$dir/hooks.json" "$loaded" "$sessions" 2>/dev/null)"
  [ -n "$merged" ] || merged="$out"
  [ -z "$merged" ] || printf '%s\n' "$merged"
  return "$rc"
}

# The payload as the hook in another directory should see it: that directory is its `cwd`.
for_dir() { # payload dir
  printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["cwd"]=sys.argv[1]; print(json.dumps(d))' "$2" 2>/dev/null \
    || printf '%s' "$1"
}

targets=''
if [ -n "$cwd" ] && [ -d "$cwd" ] && command -v python3 >/dev/null 2>&1; then
  targets="$(printf '%s' "$payload" | python3 "$dir/session-repos.py" --hook-dirs "${mode:-tool}" 2>/dev/null || true)"
fi

if [ -z "$targets" ]; then
  [ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"
  run_checked "$payload"
  exit $?
fi

if [ "$(printf '%s\n' "$targets" | grep -c .)" -le 1 ]; then
  t="${targets%%	*}"
  p="$payload"
  [ -n "$mode" ] && [ "$t" != "$cwd" ] && p="$(for_dir "$payload" "$t")"
  cd "$t" 2>/dev/null || cd "$cwd"
  run_checked "$p"
  exit $?
fi

# More than one directory (--each-repo only): the session's folder first, then each remembered repository.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/gw-in-cwd.XXXXXX" 2>/dev/null)" || { cd "$cwd"; run "$payload"; exit $?; }
trap 'rm -rf "$tmp"' EXIT
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  t="${line%%	*}"; note=''
  [ "$t" != "$line" ] && note="${line#*	}"
  p="$payload"
  [ "$t" != "$cwd" ] && p="$(for_dir "$payload" "$t")"
  printf '%s\n' "$t" > "$tmp/$n.dir"
  printf '%s' "$note" > "$tmp/$n.note"
  ( cd "$t" 2>/dev/null || exit 0
    run "$p" > "$tmp/$n.out" 2> "$tmp/$n.err"
    echo $? > "$tmp/$n.rc" ) &
  n=$((n + 1))
done <<EOF
$targets
EOF
wait

rc=0; i=0
while [ "$i" -lt "$n" ]; do
  cat "$tmp/$i.out" 2>/dev/null
  note="$(cat "$tmp/$i.note" 2>/dev/null || true)"
  if [ -s "$tmp/$i.err" ]; then
    if [ "$i" -gt 0 ] && [ -n "$note" ]; then
      printf 'groundwork: in %s — a repository this session changed from outside its folder; %s, so its changes may be that session'"'"'s and this verdict does not block:\n' "$(cat "$tmp/$i.dir")" "$note" >&2
    elif [ "$i" -gt 0 ]; then
      printf 'groundwork: in %s — a repository this session changed from outside its folder:\n' "$(cat "$tmp/$i.dir")" >&2
    fi
    cat "$tmp/$i.err" >&2
  fi
  r="$(cat "$tmp/$i.rc" 2>/dev/null || echo 0)"
  [ -n "$note" ] && [ "$r" = 2 ] && r=1
  case "$r" in
    0) ;;
    2) rc=2 ;;
    *) [ "$rc" -eq 0 ] && rc=1 ;;
  esac
  i=$((i + 1))
done
exit "$rc"
