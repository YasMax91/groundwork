#!/usr/bin/env bash
# Groundwork plugin :: Stop hook — the defect classes a rule already forbade and prose did not prevent.
#
# Every check here comes from a defect found in this author's own repositories on 2026-08-27, where the
# standard said one thing and the code did another for months. Prose is what failed; this is the retry.
#
#   BLOCK  env() outside config/          — returns null under `config:cache`; works locally, not in prod
#   BLOCK  money as float/double          — the standards' oldest rule, violated in a live payments table
#   WARN   irreversible effect in a transaction — a rolled-back transaction does not un-send an email
#   WARN   queued/broadcast event in a transaction without ShouldDispatchAfterCommit
#   WARN   a Job with no retry or failure handling — a failed job disappears silently
#
# Fail-safe like every gate here: inert outside a Groundwork project, silent when nothing changed,
# opt-out via `gates.defect_scan: false`, and it never inspects a file the change did not touch.
set -uo pipefail

[ -f .groundwork.json ] || exit 0
cfg() { # dotted key -> value ('' when jq is absent or the key is missing)
  command -v jq >/dev/null 2>&1 || return 0
  jq -r ".$1" .groundwork.json 2>/dev/null | grep -v '^null$' || true
}
[ "$(cfg 'gates.defect_scan')" = "false" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

gw_changed_paths() {
  local wt up committed=""
  wt="$(git status --porcelain -uall 2>/dev/null | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//' || true)"
  if [ "$(cfg 'gates.check_unpushed')" != "false" ]; then
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    [ -n "$up" ] && committed="$(git diff --name-only "$up..HEAD" 2>/dev/null || true)"
  fi
  printf '%s\n%s\n' "$wt" "$committed" | grep -v '^$' | sort -u
}

changed="$(gw_changed_paths | grep -E '\.php$' || true)"
[ -n "$changed" ] || exit 0

blocking=''; warning=''
add_block() { blocking="${blocking}  $1
"; }
add_warn()  { warning="${warning}  $1
"; }

# Lines that are comments are not code. Keeps a documented example from failing its own project.
code_lines() { grep -nvE '^[[:space:]]*(\*|//|#)' "$1" 2>/dev/null; }

# Does the default queue connection already defer every dispatch past the commit?
after_commit_globally=0
if [ -f config/queue.php ] && grep -A4 "'after_commit'" config/queue.php 2>/dev/null | grep -q "true"; then
  after_commit_globally=1
fi

while IFS= read -r f; do
  [ -f "$f" ] || continue

  # --- BLOCK 1: env() outside config/ -----------------------------------------------------------
  case "$f" in
    config/*) : ;;
    *)
      hits="$(code_lines "$f" | grep -E "(^|[^A-Za-z_>\$'\"])env\(" | head -5 || true)"
      [ -n "$hits" ] && while IFS= read -r h; do
        add_block "${f}:$(printf '%s' "$h" | cut -d: -f1) — env() outside config/ returns null once 'config:cache' has run. Move the value into config/ and read it with config()."
      done <<< "$hits"
      ;;
  esac

  # --- BLOCK 2: money as float/double in a migration ---------------------------------------------
  case "$f" in
    *database/migrations/*)
      hits="$(code_lines "$f" | grep -E '\->(float|double)\(' | grep -iE "price|amount|total|sum|cost|balance|payment|discount|tax|salary|fee|refund" | head -5 || true)"
      [ -n "$hits" ] && while IFS= read -r h; do
        add_block "${f}:$(printf '%s' "$h" | cut -d: -f1) — money as float/double. Use decimal or integer cents (guidelines/laravel-standards.md)."
      done <<< "$hits"
      ;;
  esac

  # --- WARN 1 & 2: what happens inside a transaction ---------------------------------------------
  grep -q "transaction(" "$f" 2>/dev/null || continue
  window="$(grep -n -A20 "transaction(" "$f" 2>/dev/null || true)"

  effects="$(printf '%s' "$window" | grep -E "Mail::to\(|Mail::send\(|Notification::send\(|Notification::route\(|->dispatchSync\(|Http::(get|post|put|patch|delete)\(" | head -3 || true)"
  [ -n "$effects" ] && while IFS= read -r h; do
    add_warn "${f}: an irreversible side effect runs inside a transaction — '$(printf '%s' "$h" | sed -E 's/^[0-9-]+[:-]//' | sed -E 's/^[[:space:]]+//' | cut -c1-60)'. A rollback does not un-send it; move it past the commit."
  done <<< "$effects"

  if [ "$after_commit_globally" -eq 0 ]; then
    for cls in $(printf '%s' "$window" | grep -oE "event\(new [A-Z][A-Za-z0-9_]*|[A-Z][A-Za-z0-9_]*::dispatch\(" \
                 | sed -E 's/event\(new //; s/::dispatch\(//' | sort -u); do
      src="$(grep -rl "class ${cls}\b" app 2>/dev/null | head -1 || true)"
      [ -n "$src" ] || continue
      grep -qE "ShouldDispatchAfterCommit|\\\$afterCommit" "$src" && continue
      grep -qE "ShouldQueue|ShouldBroadcast" "$src" || continue
      add_warn "${f}: ${cls} is dispatched inside a transaction and is queued/broadcast without ShouldDispatchAfterCommit (${src}). The listener can run before the commit lands."
    done
  fi
done <<< "$changed"

# --- WARN 3: a changed Job with no retry or failure handling --------------------------------------
while IFS= read -r f; do
  case "$f" in
    *app/Jobs/*|*/Jobs/*) ;;
    *) continue ;;
  esac
  [ -f "$f" ] || continue
  grep -q "class " "$f" 2>/dev/null || continue
  grep -qE '\$tries|\$backoff|function failed\(|retryUntil|ShouldBeUnique' "$f" 2>/dev/null && continue
  add_warn "${f}: this job declares no \$tries, \$backoff, retryUntil or failed() — a failure leaves no trace and no retry."
done <<< "$changed"

[ -z "$blocking$warning" ] && exit 0

{
  [ -n "$blocking" ] && { echo "groundwork defect-scan: these run differently than the code says — not done yet."; printf '%s' "$blocking"; }
  [ -n "$warning" ]  && { echo "groundwork defect-scan: worth a decision before this ships:"; printf '%s' "$warning"; }
  echo "(disable with gates.defect_scan=false)"
} >&2

[ -n "$blocking" ] && exit 2
exit 1
