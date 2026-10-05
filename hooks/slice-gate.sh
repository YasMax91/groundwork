#!/usr/bin/env bash
# Groundwork plugin :: Stop hook — a closed slice must name what proves it (wave 31).
#
# The other Stop gates check the repository. This one checks the task: the checkpoint's slice list.
# A task planned as five slices and built as three passes format, analysis, tests and OpenAPI — all
# four look at what the tree contains, and none of them knows how many slices the plan had.
#
# What it enforces, and nothing more:
#
#   BLOCK  a slice marked [x] that names no proof   — test:, manual: or abandoned:
#   BLOCK  test: <path> whose file does not exist
#   BLOCK  manual: that is empty, or restates the slice title, or is a content-free word
#   BLOCK  a test file with no assertion, or only a tautological one
#   BLOCK  (at Mode: Done) an acceptance criterion the spec carries that no slice claims
#   NOTICE abandoned: <reason>     — HANDOFF REQUIRED; reportable, never complete
#   NOTICE slices carrying no (ACn), so nothing can be reconciled
#
# It EXECUTES NOTHING. Two file reads, no runner, no approval boundary — cheap enough for every
# Stop. Whether a test passes is wave-32's question; whether it exists is answerable now, and the
# audit behind this wave (37 checkpoints, 71 closed slices, 10 carrying a test pointer) says the
# missing half is naming the proof at all, not running it.
#
# Fail-safe like every gate here: inert outside a Groundwork project, without jq, without a
# checkpoint, at L0/L1, and under its opt-out.
set -uo pipefail

STATE=".claude/groundwork/task-state.md"
GUARD=".claude/groundwork/slice-guard"

[ -f .groundwork.json ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

cfg() { jq -r ".$1" .groundwork.json 2>/dev/null | grep -v '^null$' || true; }
[ "$(cfg 'gates.slice_ledger')" = "false" ] && exit 0

# The gate reads the checkpoint, so a project that turned the checkpoint off has disabled this gate
# structurally. Say so once: a silent pass reads exactly like a verified one, which is the failure
# these gates exist to avoid.
if [ "$(cfg 'memory.checkpoint')" = "false" ]; then
  echo "groundwork slice-gate: memory.checkpoint=false — the slice ledger cannot be checked, and nothing here verified that the plan was finished." >&2
  exit 0
fi

[ -f "$STATE" ] || exit 0

# Level scaling: L0/L1 have no spec and often no slice list (guidelines/ai-sdd-process.md).
level="$(grep -iE '^[[:space:]]*-?[[:space:]]*Level:' "$STATE" 2>/dev/null | head -1 | grep -oE 'L[0-4]' | head -1 || true)"
case "$level" in L0|L1) exit 0 ;; esac

payload="$(cat 2>/dev/null || true)"
# Re-entry after a continuation: the previous notice already asked for this message.
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null || printf 'false')" = "true" ] && exit 0

mode="$(grep -iE '^[[:space:]]*-?[[:space:]]*Mode:' "$STATE" 2>/dev/null | head -1 | sed 's/.*://' | tr -d '*_`' | awk '{print $1}' || true)"
is_done=0
[ "$(printf '%s' "$mode" | tr '[:upper:]' '[:lower:]')" = "done" ] && is_done=1

# --- the slice rows -------------------------------------------------------------------------------
# Inside the plan section only, and one slice per output line: a real slice spans several lines, with
# its proof usually on a continuation rather than on the checkbox line itself —
#
#   - [x] S0 dependency + cloud disk + per-APP_ENV bucket prefix —
#         red test: tests/Feature/Content/CloudImageDiskConfigTest — status: green (7 cases)
#
# Reading only the checkbox line would refuse exactly the slices that did name their proof, which is
# what the first run of this gate over eleven real projects did.
slices="$(awk '
  /^##+[[:space:]]*Plan/ { p = 1; next }
  /^##+[[:space:]]/      { p = 0 }
  !p { next }
  /^[[:space:]]*-[[:space:]]*\[[ xX~]\]/ {
    if (cur != "") print cur
    cur = $0
    next
  }
  {
    if (cur != "") {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (line != "") cur = cur " " line
    }
  }
  END { if (cur != "") print cur }
' "$STATE" 2>/dev/null || true)"
[ -n "$slices" ] || exit 0

# Compare on content only: case, punctuation, spacing and the (ACn) reference all drop out, so
# "refusal wording (AC1)" and "refusal wording" are recognised as the same sentence.
# No \b here: it is a GNU extension that BSD sed (macOS) does not honour, and this silently
# left "ac1" in the string, so a manual proof restating its title compared as different. Padding
# with spaces and looping is what both seds agree on.
norm() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | tr -s '[:space:]' ' ' \
    | sed -E 's/^/ /; s/$/ /' | sed -E -e ':a' -e 's/ ac[0-9]+ / /g' -e 'ta' | sed -E 's/^ +//; s/ +$//'
}

# A row that records a commit, a document, or a live check is a work journal entry, not a slice.
# The audit found these in most real checkpoints; refusing on them would train the user to switch
# the gate off. A documentation slice is misread as a journal row here — an accepted cost, because
# the alternative refuses on rows that were never slices.
is_journal() { # row
  local r="$1"
  printf '%s' "$r" | grep -qiE 'commit[^a-z]+[0-9a-f]{7,40}' && return 0
  printf '%s' "$r" | grep -qiE '^\s*-\s*\[[xX]\]\s*([A-Z]\.\s*)?(live[ -]check|живая проверка)' && return 0
  # doc-only: mentions .md, and no code or test path anywhere
  if printf '%s' "$r" | grep -qE '\.md\b' && ! printf '%s' "$r" | grep -qE '\.php\b|tests?/'; then return 0; fi
  return 1
}

# A manual proof that says nothing. "verified" is the word the audit found standing in for evidence.
EMPTY_WORDS='verified|done|ok|okay|checked|fine|works|working|passed|yes|готово|сделано|проверено|провере?но|норм|ага'

block=''; notice=''; proven=''; journal=0; noac=0; total=0
add_block()  { block="${block}  $1
"; }
add_notice() { notice="${notice}  $1
"; }

while IFS= read -r row; do
  [ -n "$row" ] || continue
  if is_journal "$row"; then journal=$((journal+1)); continue; fi
  total=$((total+1))

  # the slice title: after the checkbox, before the first proof label
  title="$(printf '%s' "$row" | sed -E 's/^[[:space:]]*-[[:space:]]*\[[ xX~]\][[:space:]]*//' \
           | sed -E 's/(—|--|-)?[[:space:]]*(red test|test|manual|abandoned|check):.*$//' \
           | sed -E 's/[[:space:]]*—[[:space:]]*status:.*$//' | sed 's/[[:space:]]*$//')"
  short="$(printf '%s' "$title" | cut -c1-60)"

  acs="$(printf '%s' "$row" | grep -oE '\bAC[0-9]+\b' | sort -u | tr '\n' ' ' || true)"
  [ -z "$acs" ] && noac=$((noac+1))

  # --- abandoned: terminal, reportable, never complete ------------------------------------------
  if printf '%s' "$row" | grep -qE 'abandoned:'; then
    reason="$(printf '%s' "$row" | sed -E 's/.*abandoned:[[:space:]]*//' | sed 's/[[:space:]]*$//')"
    if [ -z "$(norm "$reason")" ]; then
      add_block "«${short}» — abandoned: with no reason. An abandonment states why, or it is a deletion with a marker on it."
    else
      add_notice "«${short}» — abandoned: ${reason}"
      proven="${proven}${acs}"
    fi
    continue
  fi

  # Only closed slices must carry a proof. An open [ ] slice is work in progress.
  case "$row" in *'[x]'*|*'[X]'*) ;; *) continue ;; esac

  # --- test: / tests: (legacy `red test:` reads the same; `status:` is parsed and ignored) --------
  # The corpus writes all of these, so all of them parse:
  #   test: tests/Feature/X.php      tests: A (10), B (7)      red test: XTest (12) — status: green
  # A bare class name is resolved under tests/ — writing the class rather than the path is what the
  # real checkpoints do, and refusing it would refuse correctly-worked slices.
  if printf '%s' "$row" | grep -qE '(red[[:space:]]+)?tests?:'; then
    # Stop at the first em dash: on a joined multi-line slice the prose that follows ("— green (7
    # cases) X was RENAMED to Y and ...") would otherwise be read as more test names.
    list="$(printf '%s' "$row" | sed -E 's/.*(red[[:space:]]+)?tests?:[[:space:]]*//' \
            | sed -E 's/[[:space:]]*(—|--).*$//' | sed -E 's/[[:space:]]*status:.*$//' | sed -E 's/\([^)]*\)//g')"
    # Only tokens that look like a test survive — a path, a .php file, or a *Test class name. Prose
    # words ("which", "so") reached the checker before this filter existed.
    names="$(printf '%s' "$list" | tr ',+' '\n\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]].*$//' \
             | tr -d '`;' | grep -v '^$' | grep -E 'Test(\.php)?$|\.php$|/' || true)"
    if [ -z "$names" ]; then
      add_block "«${short}» — test: names no file."
      continue
    fi
    slice_ok=1
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      # A path may be written without its extension, and a class name without its path. Both are
      # what the real checkpoints contain, so both resolve.
      path=''
      if [ -f "$name" ]; then
        path="$name"
      elif [ -f "${name}.php" ]; then
        path="${name}.php"
      else
        case "$name" in
          */*) : ;;
          *) path="$(find tests -type f -name "${name}.php" 2>/dev/null | head -1 || true)" ;;
        esac
      fi
      if [ -z "$path" ] || [ ! -f "$path" ]; then
        add_block "«${short}» — ${name} does not exist under tests/. The slice is closed against a file that is not there."
        slice_ok=0; continue
      fi
      # Oracle lint: a check that cannot fail is not a check.
      if ! grep -qE '\$this->assert|assert[A-Z][A-Za-z]*\(|->assert|expect\(' "$path" 2>/dev/null; then
        add_block "«${short}» — ${path} contains no assertion [no-assertion]. It cannot fail, so it proves nothing."
        slice_ok=0
      elif grep -qE 'assertTrue\([[:space:]]*true[[:space:]]*\)|assertEquals\([[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*\1[[:space:]]*\)|assertSame\([[:space:]]*true[[:space:]]*,[[:space:]]*true[[:space:]]*\)' "$path" 2>/dev/null; then
        add_block "«${short}» — ${path} asserts a tautology [tautological-assert]. It cannot fail, so it proves nothing."
        slice_ok=0
      elif grep -qE 'markTestSkipped|markTestIncomplete' "$path" 2>/dev/null \
           && ! grep -qE '\$this->assert|assert[A-Z][A-Za-z]*\(' "$path" 2>/dev/null; then
        add_block "«${short}» — ${path} only skips [no-assertion]."
        slice_ok=0
      fi
    done <<< "$names"
    [ "$slice_ok" -eq 1 ] && proven="${proven}${acs}"
    continue
  fi

  # --- manual: <what a person observed> ----------------------------------------------------------
  if printf '%s' "$row" | grep -qE 'manual:'; then
    text="$(printf '%s' "$row" | sed -E 's/.*manual:[[:space:]]*//' | sed -E 's/[[:space:]]*—[[:space:]]*status:.*$//' | sed 's/[[:space:]]*$//')"
    n_text="$(norm "$text")"; n_title="$(norm "$title")"
    if [ -z "$n_text" ]; then
      add_block "«${short}» — manual: with no text. Name what a person observed."
    elif [ "$n_text" = "$n_title" ]; then
      add_block "«${short}» — manual: restates the slice title. Name what a person observed, not what the slice wanted."
    elif printf '%s' "$n_text" | grep -qE "^($EMPTY_WORDS)( (it|this|все|всё))?$"; then
      add_block "«${short}» — manual: «${text}» proves nothing. Name what was observed, where, and when."
    else
      proven="${proven}${acs}"
    fi
    continue
  fi

  # --- a test named without the label --------------------------------------------------------------
  # The corpus writes `red: tests/Feature/X.php` and bare `— tests/Unit/XTest.php` as often as it
  # writes the label. The label is syntax; naming the proof is the substance, so a slice that points
  # at a real test file has met the rule. Without this, 2 of 36 real checkpoints were refused for
  # having named their evidence in a shape the parser did not recognise.
  implicit="$(printf '%s' "$row" | tr ' ,;`()' '\n\n\n\n\n\n' | grep -E 'Test(\.php)?$|tests?/[A-Za-z0-9_/]+\.php$' | head -3 || true)"
  if [ -n "$implicit" ]; then
    found=0
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      path=''
      if [ -f "$name" ]; then path="$name"
      elif [ -f "${name}.php" ]; then path="${name}.php"
      else
        case "$name" in
          */*) : ;;
          *) path="$(find tests -type f -name "${name}.php" 2>/dev/null | head -1 || true)" ;;
        esac
      fi
      [ -n "$path" ] && [ -f "$path" ] && { found=1; break; }
    done <<< "$implicit"
    if [ "$found" -eq 1 ]; then
      proven="${proven}${acs}"
      continue
    fi
  fi

  # --- nothing named ------------------------------------------------------------------------------
  add_block "«${short}» — closed with no proof. Name one: test: <path>, manual: <what a person observed>, or abandoned: <reason>."
done <<< "$slices"

# --- reconciliation against the spec, at Mode: Done only -------------------------------------------
# A gate over a list the agent maintains cannot see a removed line. This is what sees it: the
# obligation lives in the approved spec, so deleting the slice no longer deletes the obligation.
if [ "$is_done" -eq 1 ]; then
  spec="$(grep -iE '^[[:space:]]*-?[[:space:]]*Spec:' "$STATE" 2>/dev/null | head -1 | sed 's/.*://' | tr -d '`' | awk '{print $1}' || true)"
  # With no (ACn) anywhere there is nothing to subtract from — listing every criterion the spec
  # carries would be noise, and the notice below already reports that nothing was reconciled.
  if [ -n "$spec" ] && [ -f "$spec" ] && [ "$noac" -lt "$total" ]; then
    missing=''
    for ac in $(grep -oE '\bAC[0-9]+\b' "$spec" 2>/dev/null | sort -u); do
      printf '%s' "$proven" | grep -qE "\b${ac}\b" || missing="${missing}${ac} "
    done
    [ -n "$missing" ] && add_block "the spec carries $(printf '%s' "$missing" | wc -w | tr -d ' ') acceptance criteria no slice claims and no abandonment names: ${missing%% }"
  fi
fi

# --- the source requirements, at Mode: Done only (GW34-AC3) ----------------------------------------
# Acceptance criteria are the agent's restatement of the task; the requirements the person wrote are
# the task. The 2026-10-05 sweep found ~70 complaints of a subtask, a note at the end of the brief, or
# an adjacent surface dropped while every AC was green. So the spec quotes each item verbatim as R<n>,
# and "done" needs a proof cell — or an agreed `out of scope: <reason>` — on every row.
if [ "$is_done" -eq 1 ] && [ -n "${spec:-}" ] && [ -f "${spec:-}" ]; then
  unproven="$(awk '
    /^##[[:space:]]+Source requirements/ { on=1; next }
    on && /^##[[:space:]]/ { on=0 }
    on && /^[[:space:]]*\|[[:space:]]*R[0-9]+[[:space:]]*\|/ {
      line=$0; sub(/^[[:space:]]*\|/, "", line); sub(/\|[[:space:]]*$/, "", line)
      n=split(line, cell, "|"); id=cell[1]; proof=cell[n]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", id); gsub(/^[[:space:]]+|[[:space:]]+$/, "", proof)
      if (proof == "" || proof ~ /^(-|—|TBD|todo|\?|pending)$/) printf "%s ", id
    }' "$spec" 2>/dev/null || true)"
  [ -n "$unproven" ] && add_block "the spec's source requirements have no proof on: ${unproven%% }. Each row needs a test, an HTTP/browser run, a screenshot — or «out of scope: <reason agreed with the user>»."
fi

[ "$noac" -gt 0 ] && [ "$noac" -eq "$total" ] && add_notice "none of the ${total} slices carries an (ACn) reference, so nothing was reconciled against the spec."

# --- the migration boundary -------------------------------------------------------------------------
# A checkpoint that uses no part of this grammar — no (ACn) anywhere, no test:/manual:/abandoned:
# anywhere — was written before the grammar existed. Refusing it blocks the first Stop after an
# upgrade on work that was finished under the old rules; two of this author's eleven projects were in
# exactly that state when the gate was first run over them. Tell it instead, and let the gate arm
# itself the moment one slice speaks the new format.
if [ -n "$block" ] && [ "$noac" -eq "$total" ] \
   && ! printf '%s' "$slices" | grep -qE '(red[[:space:]]+)?test:|manual:|abandoned:'; then
  {
    echo "groundwork slice-gate: this checkpoint predates the v0.41.0 slice grammar — ${total} closed slices name no proof, and it is NOT refused for that."
    echo "  From the next checkpoint on, a closed slice carries test: <path>, manual: <what a person observed>, or abandoned: <reason>, plus its (ACn)."
    echo "  guidelines/working-memory.md has the format. This notice stops as soon as one slice uses it."
  } >&2
  rm -f "$GUARD" 2>/dev/null || true
  exit 0
fi

# --- the progress guard ----------------------------------------------------------------------------
# The eighth Stop hook, and the fourth that can refuse. A gate that strands a session gets uninstalled;
# one that lets go and says what stays unproven does not.
if [ -n "$block" ]; then
  fingerprint="$(printf '%s' "$proven" | tr -d '[:space:]')"
  prev_fp=''; prev_n=0
  if [ -r "$GUARD" ]; then
    prev_fp="$(sed -n '1p' "$GUARD" 2>/dev/null || true)"
    prev_n="$(sed -n '2p' "$GUARD" 2>/dev/null | grep -oE '^[0-9]+' || printf '0')"
  fi
  if [ "$fingerprint" = "$prev_fp" ]; then n=$((prev_n+1)); else n=1; fi
  { mkdir -p "$(dirname "$GUARD")" 2>/dev/null || true; printf '%s\n%s\n' "$fingerprint" "$n" > "$GUARD"; } 2>/dev/null || true
  if [ "$n" -gt 3 ]; then
    {
      echo "groundwork slice-gate: released after ${prev_n} refusals with no slice newly proven. These stay unproven:"
      printf '%s' "$block"
    } >&2
    exit 0
  fi
else
  rm -f "$GUARD" 2>/dev/null || true
fi

[ -z "$block$notice" ] && exit 0

{
  [ -n "$block" ] && {
    echo "groundwork slice-gate: a closed slice must name what proves it — not done yet."
    printf '%s' "$block"
  }
  [ -n "$notice" ] && {
    # grep -q, never -c: `grep -c` prints "0" on no match, and [ -n "0" ] is true, which printed
    # HANDOFF REQUIRED over every ordinary notice. Caught by running the gate over 36 real checkpoints.
    printf '%s' "$notice" | grep -q 'abandoned:' && echo "groundwork slice-gate: HANDOFF REQUIRED — reportable, not complete:"
    printf '%s' "$notice"
  }
  echo "(disable with gates.slice_ledger=false)"
} >&2

[ -n "$block" ] && exit 2
exit 1
