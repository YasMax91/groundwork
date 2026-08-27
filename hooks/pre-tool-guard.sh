#!/usr/bin/env bash
# Groundwork plugin :: PreToolUse(Bash|Edit|Write) hook — enforcement gate.
# Turns advisory rules into engine-level denials:
#   (a) Laravel/PHP commands must go through the runner (Sail), not the host.
#   (b) never edit a shipped (git-tracked) migration.
#   (c) optional: no app-code edits while the task is in Discovery/Plan mode (default OFF).
#
# Fail-safe by design — it must never break a tool call on its own bug:
#   * acts only in a Groundwork project (.groundwork.json present); silent no-op otherwise;
#   * every toggle is opt-out via .groundwork.json `gates`;
#   * ALLOW (exit 0) on any missing field, parse error, or uncertainty;
#   * DENY via exit 2 + a stderr reason (the documented PreToolUse blocking path — stderr
#     is fed back to the model so it self-corrects).
set -uo pipefail

# Shared resolvers (runner + canonical mode). Fail-safe: if the library is missing or
# unreadable, the fallbacks below keep the hook behaving exactly as it did without it.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_runner       >/dev/null 2>&1 || gw_runner() { printf 'sail'; }
command -v gw_runner_ready >/dev/null 2>&1 || gw_runner_ready() { [ -x ./vendor/bin/sail ]; }
command -v gw_mode         >/dev/null 2>&1 || gw_mode() {
  grep -iE '^[[:space:]]*-?[[:space:]]*Mode:' "${1:-.claude/groundwork/task-state.md}" 2>/dev/null \
    | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | awk -F'|' '{print $1}' | awk '{print $1}'
}

# --- JSON access -------------------------------------------------------------------------------
# This hook's rules are worth nothing if it cannot read its own input. `jq` is the normal path;
# `python3` (already a dependency of hooks/estimate-ledger.sh, so nothing new is required) is the
# fallback, so a machine without jq keeps the runner lock and the shipped-migration lock. With
# neither parser the hook says so on stderr instead of exiting quietly — see the project gate below.
GW_PARSER=''
if command -v jq >/dev/null 2>&1; then
  GW_PARSER='jq'
elif command -v python3 >/dev/null 2>&1; then
  GW_PARSER='python3'
fi

# gw_get <json> <dotted.path> [more paths…] -> the first non-empty scalar, or nothing.
gw_get() {
  local json="$1"; shift
  [ -n "$json" ] || return 0
  local p v
  case "$GW_PARSER" in
    jq)
      for p in "$@"; do
        # `// empty` cannot be used here: jq's alternative operator also fires on a literal
        # `false`, which would turn `gates.enforce_runner: false` into an empty answer and
        # switch a deliberately disabled gate back on.
        v="$(printf '%s' "$json" | jq -r ".${p}" 2>/dev/null || true)"
        [ "$v" = "null" ] && v=''
        [ -n "$v" ] && { printf '%s' "$v"; return 0; }
      done
      ;;
    python3)
      printf '%s' "$json" | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for path in sys.argv[1:]:
    node = doc
    for key in path.split("."):
        if isinstance(node, dict) and key in node:
            node = node[key]
        else:
            node = None
            break
    if node is None or isinstance(node, (dict, list)):
        continue
    text = node if isinstance(node, str) else ("true" if node is True else "false" if node is False else str(node))
    if text:
        sys.stdout.write(text)
        break
' "$@" 2>/dev/null || true
      ;;
  esac
}

# gw_conf <dotted.path> -> the value from .groundwork.json, or nothing.
gw_conf() { gw_get "$(cat .groundwork.json 2>/dev/null || true)" "$1"; }

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

tool="$(gw_get "$input" 'tool_name')"

deny() { # $1 = reason -> stderr, then block
  printf 'groundwork pre-tool-guard: %s\n' "$1" >&2
  exit 2
}

# The plugin's own working memory needs no human approval — the agent writes the checkpoint on
# every task, and a permission prompt for a file this plugin created itself is pure friction.
# A settings.json rule cannot cover it: `Write(path)` rules are accepted but never matched, and a
# first-time checkpoint is created by Write, not Edit. So authorise it here, narrowly.
# (`deny`/`ask` rules still win over a hook's allow, so this cannot widen anything the user locked.)
#
# This runs BEFORE the `.groundwork.json` gate below: the first checkpoint of a task is written
# while the project is still un-initialized (start-task precedes init), and the prompt showed up
# in exactly those projects.
case "$tool" in
  Edit|Write)
    memory="$(gw_get "$input" 'tool_input.file_path' 'tool_input.path')"
    case "$memory" in
      */.claude/groundwork/*|.claude/groundwork/*)
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"groundwork workflow memory (checkpoint / impact cache) — written by the plugin itself"}}\n'
        exit 0 ;;
    esac
    ;;
esac

# Only enforce in a Groundwork-initialized project; never touch a non-Groundwork repo.
[ -f .groundwork.json ] || exit 0

# A gate that cannot read its input has verified nothing (guidelines/ai-sdd-process.md) — so say it
# on stderr rather than exiting in silence, which is what this hook did before.
if [ -z "$GW_PARSER" ]; then
  printf 'groundwork pre-tool-guard: no jq and no python3 on PATH — the runner lock and the shipped-migration lock did NOT run.\n' >&2
  exit 0
fi

case "$tool" in
  Bash)
    # (a) Runner enforcement.
    [ "$(gw_conf 'gates.enforce_runner')" = "false" ] && exit 0

    # A project that declares `runner: host` runs Laravel/PHP on the host by design —
    # there is nothing to enforce, so this branch is a no-op there.
    [ "$(gw_runner)" = "host" ] && exit 0

    cmd="$(gw_get "$input" 'tool_input.command')"
    [ -n "$cmd" ] || exit 0

    # Bootstrap fail-open: if the runner isn't installed yet (fresh clone before
    # `composer install`), do not block host composer/php.
    gw_runner_ready || exit 0

    # Already routed through the runner? allow.
    case "$cmd" in
      *vendor/bin/sail*) exit 0 ;;
    esac

    # Check EVERY segment, not just the first: `cd sub && php artisan …` would otherwise be read
    # as the verb `cd` and sail straight past the guard.
    # A `while` in a pipeline runs in a subshell and would lose the flag, so iterate in-process.
    host_verb=0
    old_ifs="$IFS"; IFS='
'
    for seg in $(printf '%s' "$cmd" | tr ';|&' '\n'); do
      verb="$(printf '%s' "$seg" \
        | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' \
        | awk '{print $1}')"
      case "$verb" in
        php|composer|artisan|./artisan|phpunit|pest) host_verb=1 ;;
      esac
    done
    IFS="$old_ifs"
    [ "$host_verb" -eq 1 ] && deny "run Laravel/PHP through the runner, not the host — e.g. './vendor/bin/sail artisan …' or './vendor/bin/sail composer …'. (disable with gates.enforce_runner=false)"
    exit 0
    ;;

  Edit|Write)
    path="$(gw_get "$input" 'tool_input.file_path' 'tool_input.path')"
    [ -n "$path" ] || exit 0

    # (Workflow-memory paths already returned `allow` above, before the .groundwork.json gate.)

    # (b) Shipped-migration lock: deny edits to a git-tracked migration.
    if [ "$(gw_conf 'gates.lock_shipped_migrations')" != "false" ]; then
      case "$path" in
        *database/migrations/*)
          if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
             && git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
            deny "'${path}' is a shipped (committed) migration — add a NEW migration instead of editing it. (disable with gates.lock_shipped_migrations=false)"
          fi
          ;;
      esac
    fi

    # (c) Discovery edit-lock (OFF by default): no app-code edits while planning.
    if [ "$(gw_conf 'gates.lock_edits_in_discovery')" = "true" ]; then
      state=".claude/groundwork/task-state.md"
      if [ -f "$state" ]; then
        # Canonical modes only — a non-canonical value yields nothing, so the lock fails open
        # rather than matching garbage in a hand-edited checkpoint.
        mode="$(gw_mode "$state")"
        case "$mode" in
          Discovery|Plan)
            # Planning artifacts are always allowed; only app code is locked.
            case "$path" in
              *.claude/groundwork/*|*docs/*) : ;;
              *) deny "task is in ${mode} mode — approve the plan before editing app code (${path}). (disable with gates.lock_edits_in_discovery=false)" ;;
            esac
            ;;
        esac
      fi
    fi
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
