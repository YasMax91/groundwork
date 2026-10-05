#!/usr/bin/env bash
# Groundwork plugin :: PreToolUse(Bash) hook — give every command an empty stdin.
#
# The Bash tool leaves stdin open, so a command that reads it and was handed nothing — `python3 -`
# with the heredoc bound to another command, `cat > file` without one, `artisan tinker file.php`
# (it runs the file, then waits for the REPL), a hook script run by hand (`payload="$(cat)"`) —
# waits forever. After 120 s the tool moves it to the background, where it stays alive, and the
# session's turns keep ending on a task that will never finish until a human kills it. Measured
# before this hook: five such tasks across sessions, alive from 4 to 84 hours each.
#
# The rewrite is `true | (\n<command>\n)`:
#   * the empty pipe ends every stray stdin read at once; a heredoc inside still wins, because a
#     command's own redirection overrides the inherited stdin;
#   * a pipe, not `< /dev/null` — an input redirect is checked against Read rules, and /dev/null
#     sits outside the working directories, which would prompt on every command without a Read allow;
#   * a subshell, not a `{ }` group — permission ask/deny rules are documented to reach into
#     subshells, and Claude Code evaluates them against the rewritten command. The cost: a `cd`
#     inside the command no longer carries over to the next call.
#
# Not tied to a Groundwork project: the hang is a property of the tool, not of the repo.
# Fail-safe: any parse problem → exit 0 with no output, and the command runs unchanged.
# Opt out per project with `gates.isolate_stdin: false` in .groundwork.json.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0

if [ -f .groundwork.json ]; then
  [ "$(jq -r '.gates.isolate_stdin' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
fi

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Already wrapped (a retried or replayed call) — wrapping twice changes nothing but the noise.
case "$cmd" in
  'true | ('*) exit 0 ;;
esac

printf '%s' "$input" | jq -c --arg cmd "true | (
${cmd}
)" '{hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput: (.tool_input + {command: $cmd})
    }}' 2>/dev/null || true
exit 0
