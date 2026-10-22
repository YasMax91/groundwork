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
# Fail-safe: no payload, no python3, or no answer → the hook runs in the payload's `cwd`, exactly as before; no
# `cwd`, or one that is not a directory → where it was started.
set -uo pipefail

mode=''
case "${1:-}" in --each-repo|--first-repo) mode="${1#--}"; mode="${mode%-repo}"; shift ;; esac
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
  run "$payload"
  exit $?
fi

if [ "$(printf '%s\n' "$targets" | grep -c .)" -le 1 ]; then
  t="${targets%%	*}"
  p="$payload"
  [ -n "$mode" ] && [ "$t" != "$cwd" ] && p="$(for_dir "$payload" "$t")"
  cd "$t" 2>/dev/null || cd "$cwd"
  run "$p"
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
