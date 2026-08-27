#!/usr/bin/env bash
# Groundwork plugin :: shared hook resolvers.
#
# Three things every gate re-derived by hand, so a fix lands in one place:
#   * gw_cmd           — a gate command built for the .groundwork.json `runner`
#   * gw_runner_ready  — can that runner actually be invoked here?
#   * gw_mode          — the task-state `Mode:`, validated against the canon
#
# Sourced, never executed. Every function is pure (no side effects) and answers with the
# safest value it can when anything is missing, because the callers are fail-safe hooks:
# a project without `.groundwork.json`, without jq, or with an unparsable field must
# behave exactly as it did before this library existed.

# Canonical operating modes (guidelines/working-memory.md). Anything else is not a mode.
#
# `Done` is deliberately absent. It is a terminal marker, not a working mode, and two behaviours
# depend on it yielding nothing here: hooks/session-start.sh stops injecting a finished checkpoint's
# body (v0.19.1), and hooks/pre-tool-guard.sh's discovery lock keys on an active mode only. The
# terminal marker is matched where it is actually needed — hooks/estimate-ledger.sh --record-if-done.
GW_MODES='Discovery Spec Plan Implementation Review'

# The configured runner: `sail` (default) or `host`.
gw_runner() {
  local r=''
  if [ -f .groundwork.json ] && command -v jq >/dev/null 2>&1; then
    r="$(jq -r '.runner // empty' .groundwork.json 2>/dev/null || true)"
  fi
  # Normalise, then validate: `Host`, `HOST`, `host ` are honoured; anything else is a typo that
  # would otherwise resolve to sail, find no binary, and switch every gate off in silence.
  r="$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$r" in
    host)   printf 'host' ;;
    sail|'') printf 'sail' ;;
    *)      printf 'invalid' ;;
  esac
}

# Build a gate command for the configured runner: gw_cmd artisan test.
#
# Not a plain prefix — the host forms genuinely differ per tool (`php artisan`, not `artisan`;
# `./vendor/bin/pint`, not `pint`), which is exactly the kind of detail a naive prefix gets wrong.
# An explicit `commands.*` override in .groundwork.json still wins over anything built here.
gw_cmd() {
  local tool="$1"; shift
  local args="$*"
  if [ "$(gw_runner)" = "host" ]; then
    case "$tool" in
      artisan)  printf 'php artisan%s' "${args:+ $args}" ;;
      composer) printf 'composer%s'    "${args:+ $args}" ;;
      pint)     printf './vendor/bin/pint%s' "${args:+ $args}" ;;
      *)        printf '%s%s' "$tool" "${args:+ $args}" ;;
    esac
  else
    case "$tool" in
      pint) printf './vendor/bin/sail pint%s' "${args:+ $args}" ;;
      *)    printf './vendor/bin/sail %s%s' "$tool" "${args:+ $args}" ;;
    esac
  fi
}

# True when the configured runner can actually run something here. A host runner always can;
# Sail needs its binary (a fresh clone before `composer install` must not be blocked).
gw_runner_ready() {
  case "$(gw_runner)" in
    host)    return 0 ;;
    invalid) return 1 ;;
    *)       [ -x ./vendor/bin/sail ] ;;
  esac
}

# The current task mode, or nothing.
#
# Reads the first `Mode:` line of the checkpoint, strips Markdown emphasis and the
# template's `Discovery | Spec | ...` alternatives, then accepts the value ONLY if it
# matches the canon case-insensitively — echoing the canonical spelling. A checkpoint
# reading `- Mode: **COMMITTED**` therefore yields nothing at all, so a gate keyed on the
# mode fails open instead of matching garbage.
gw_mode() {
  local state="${1:-.claude/groundwork/task-state.md}" raw canon
  [ -f "$state" ] || return 0

  raw="$(grep -iE '^[[:space:]]*-?[[:space:]]*Mode:' "$state" 2>/dev/null | head -1 || true)"
  [ -n "$raw" ] || return 0

  # value after the colon -> first alternative -> strip emphasis/backticks -> first word
  raw="${raw#*:}"
  raw="$(printf '%s' "$raw" | awk -F'|' '{print $1}' | tr -d '*_`' | awk '{print $1}')"
  [ -n "$raw" ] || return 0

  for canon in $GW_MODES; do
    if [ "$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$canon" | tr '[:upper:]' '[:lower:]')" ]; then
      printf '%s' "$canon"
      return 0
    fi
  done
  return 0
}
