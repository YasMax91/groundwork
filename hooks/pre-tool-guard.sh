#!/usr/bin/env bash
# RaDevs plugin :: PreToolUse(Bash|Edit|Write) hook — enforcement gate.
# Turns advisory rules into engine-level denials:
#   (a) Laravel/PHP commands must go through the runner (Sail), not the host.
#   (b) never edit a shipped (git-tracked) migration.
#   (c) optional: no app-code edits while the task is in Discovery/Plan mode (default OFF).
#
# Fail-safe by design — it must never break a tool call on its own bug:
#   * acts only in a RaDevs project (.groundwork.json present); silent no-op otherwise;
#   * every toggle is opt-out via .groundwork.json `gates`;
#   * ALLOW (exit 0) on any missing field, parse error, or uncertainty;
#   * DENY via exit 2 + a stderr reason (the documented PreToolUse blocking path — stderr
#     is fed back to the model so it self-corrects).
set -uo pipefail

# Only enforce in a RaDevs-initialized project; never touch a non-RaDevs repo.
[ -f .groundwork.json ] || exit 0

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"

deny() { # $1 = reason -> stderr, then block
  printf 'groundwork pre-tool-guard: %s\n' "$1" >&2
  exit 2
}

case "$tool" in
  Bash)
    # (a) Runner enforcement.
    [ "$(jq -r '.gates.enforce_runner' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    [ -n "$cmd" ] || exit 0

    # Bootstrap fail-open: if the runner isn't installed yet (fresh clone before
    # `composer install`), do not block host composer/php.
    [ -x ./vendor/bin/sail ] || exit 0

    # Already routed through the runner? allow.
    case "$cmd" in
      *vendor/bin/sail*) exit 0 ;;
    esac

    # First real verb, after any leading VAR=val environment assignments.
    verb="$(printf '%s' "$cmd" \
      | sed -E 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' \
      | awk '{print $1}')"
    case "$verb" in
      php|composer|artisan|./artisan|phpunit|pest)
        deny "run Laravel/PHP through the runner, not the host — e.g. './vendor/bin/sail artisan …' or './vendor/bin/sail composer …'. (disable with gates.enforce_runner=false)" ;;
    esac
    exit 0
    ;;

  Edit|Write)
    path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
    [ -n "$path" ] || exit 0

    # (b) Shipped-migration lock: deny edits to a git-tracked migration.
    if [ "$(jq -r '.gates.lock_shipped_migrations' .groundwork.json 2>/dev/null)" != "false" ]; then
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
    if [ "$(jq -r '.gates.lock_edits_in_discovery' .groundwork.json 2>/dev/null)" = "true" ]; then
      state=".claude/groundwork/task-state.md"
      if [ -f "$state" ]; then
        mode="$(grep -iE '^[[:space:]]*-?[[:space:]]*Mode:' "$state" 2>/dev/null \
          | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | awk -F'|' '{print $1}' | awk '{print $1}')"
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
