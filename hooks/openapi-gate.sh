#!/usr/bin/env bash
# RaDevs plugin :: Stop hook — the OpenAPI contract gate.
# The published spec must never lag the code: if this task changed the API contract surface
# (routes, controllers, FormRequests, Resources) and nothing in the diff touched the OpenAPI
# spec, "done" is blocked. When annotations DID change, the spec is regenerated so broken
# schemas fail here instead of in the frontend.
#
# Fail-safe by design — it must never block on an environment problem:
#   * acts only in a RaDevs project (.groundwork.json) that actually has OpenAPI tooling;
#   * opt-out via gates.openapi_on_stop=false;
#   * ALLOW (exit 0) on any missing field, parse error, or uncertainty;
#   * escape hatch: declare "OpenAPI: n/a — <reason>" in the task checkpoint when the change
#     provably does not touch the contract (a pure internal refactor);
#   * BLOCK via exit 2 + a stderr reason (fed back to the model so it self-corrects).
set -uo pipefail

# Shared resolvers (runner-aware commands); fail-safe fallback to the Sail default.
# shellcheck source=/dev/null
{ LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib.sh"; [ -r "$LIB" ] && . "$LIB"; } 2>/dev/null || true
command -v gw_cmd          >/dev/null 2>&1 || gw_cmd() { printf './vendor/bin/sail %s %s' "$1" "${2:-}"; }
command -v gw_runner_ready >/dev/null 2>&1 || gw_runner_ready() { [ -x ./vendor/bin/sail ]; }

# Committing must not disarm the gate. The plugin's own flow ends in a commit, so the last Stop of a
# task would otherwise run against an empty working tree and verify nothing at all. Unpushed commits
# still count as "work in progress"; once pushed, the gate lets go.
gw_changed_paths() {
  local wt up committed=""
  wt="$(git status --porcelain -uall 2>/dev/null | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//' || true)"
  if [ "$(jq -r '.gates.check_unpushed' .groundwork.json 2>/dev/null)" != "false" ]; then
    up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
    [ -n "$up" ] && committed="$(git diff --name-only "$up..HEAD" 2>/dev/null || true)"
  fi
  printf '%s\n%s\n' "$wt" "$committed" | grep -v '^$' | sort -u
}

[ -f .groundwork.json ] || exit 0
[ "$(jq -r '.gates.openapi_on_stop' .groundwork.json 2>/dev/null)" = "false" ] && exit 0

# --- does this project document an API at all? explicit config wins, else auto-detect ---
enabled="$(jq -r '.openapi.enabled // empty' .groundwork.json 2>/dev/null || true)"
if [ "$enabled" = "false" ]; then
  exit 0
elif [ "$enabled" != "true" ]; then
  # Auto-detect the toolchain; silent no-op when the project has none.
  grep -qE 'darkaonline/l5-swagger|zircote/swagger-php' composer.json 2>/dev/null || exit 0
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# --- changed paths in the working tree (staged, unstaged, untracked) ---
# `-uall` is required: without it a brand-new directory is reported as the directory itself
# ("?? app/Http/Resources/"), which would hide every file in it from the surface check.
# Then strip the 2-char status + space, and take the target of a rename.
changed="$(gw_changed_paths)"
[ -n "$changed" ] || exit 0

# --- did the change touch the API contract surface? ---
surface="$(jq -r '.openapi.surface[]?' .groundwork.json 2>/dev/null || true)"
[ -n "$surface" ] || surface='routes/
app/Http/Controllers/
app/Http/Requests/
app/Http/Resources/'

touched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *.php) ;; *) continue ;; esac
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    case "$f" in "$dir"*|*/"$dir"*) touched="${touched}${f}"$'\n'; break ;; esac
  done <<< "$surface"
done <<< "$changed"
[ -n "$touched" ] || exit 0

# --- comment-only changes cannot alter the contract ---
# An L0 typo fix inside a controller comment must not demand an annotation update plus a checkpoint
# that an L0 task never creates. But "looks like a comment" is a dangerous test in PHP, so this is
# deliberately narrow — three ways it could be fooled, each closed:
#   * `#[Attribute]` opens with '#' and is CODE (routing/middleware/policy) -> never comment-only;
#   * anything after a closing `*/` is code, however the line starts -> covers both
#     `/* a */ realCode(); /* b */` and a `*/ realCode();` block closer;
#   (an `OA\` token is handled earlier by spec_touched, so it never reaches this branch).
# It waives only the "annotations must change" demand. It exits early *because* nothing was
# documented and nothing needs regenerating; whenever the spec WAS touched, control reaches the
# generation check below as usual. Anything uncertain (no diff, untracked file) falls through to
# the normal path — a false block is recoverable, a false pass is not.
comment_only=0
files_arr=()
while IFS= read -r f; do [ -n "$f" ] && files_arr+=("$f"); done <<< "$touched"

untracked_touched=0
for f in "${files_arr[@]}"; do
  git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 || untracked_touched=1
done

if [ "$untracked_touched" -eq 0 ] && [ "${#files_arr[@]}" -gt 0 ]; then
  diff_base="HEAD"; up="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  [ -n "$up" ] && diff_base="$up"
  changed_lines="$(git diff "$diff_base" -- "${files_arr[@]}" 2>/dev/null \
    | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' || true)"
  # A line carrying anything after a closing `*/` is code, however it starts. This one check closes
  # both `/* a */ realCode(); /* b */` (a greedy one-line block) and a `*/ realCode();` block closer.
  code_after_close=0
  printf '%s\n' "$changed_lines" | sed -E 's/^[+-]//' | grep -qE '\*/[[:space:]]*[^[:space:]]' && code_after_close=1

  if [ -n "$changed_lines" ] && [ "$code_after_close" -eq 0 ] && ! printf '%s\n' "$changed_lines" | grep -q 'OA\\'; then
    # Strip the +/- marker, then hunt for any line that is NOT purely a comment or blank.
    #   allowed: blank · `// …` · `# …` (but not `#[`) · `* …` · `*/` · `/* … */` complete on one
    #            line with nothing after it · `/**` or `/*` alone opening a block
    code_line="$(printf '%s\n' "$changed_lines" | sed -E 's/^[+-]//' | grep -vE \
      '^[[:space:]]*$|^[[:space:]]*//|^[[:space:]]*#([^[]|$)|^[[:space:]]*\*|^[[:space:]]*/\*+[[:space:]]*$|^[[:space:]]*/\*.*\*/[[:space:]]*$' \
      || true)"
    [ -z "$code_line" ] && comment_only=1
  fi
fi

# --- was the spec touched in the same change? ---
# Annotations may live outside the surface files (dedicated schema classes), and some projects
# keep a static document — so look across the whole diff, not just the touched endpoints.
spec_touched=0

# (a) tracked files: an added/removed line carrying a REAL OA annotation — `OA\Get(`, `@OA\Schema(`
# and so on. A bare mention such as `// TODO OA\ later` is not documentation and must not pass.
if git diff "${diff_base:-HEAD}" 2>/dev/null | grep -qE '^[+-].*@?OA\\[A-Z][A-Za-z]*[[:space:]]*\('; then
  spec_touched=1
fi

# (b) untracked files that already carry annotations (a brand-new documented controller/schema)
if [ "$spec_touched" -eq 0 ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    if grep -qE '@?OA\\[A-Z][A-Za-z]*[[:space:]]*\(' "$f" 2>/dev/null; then spec_touched=1; break; fi
  done <<< "$changed"
fi

# (c) a static spec document changed (projects that hand-maintain the YAML/JSON)
if [ "$spec_touched" -eq 0 ]; then
  # A hand-maintained document counts only if it actually has content — an empty file named
  # swagger-notes.yaml is not a spec change.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s' "$f" | grep -qiE '(openapi|swagger|api-docs).*\.(ya?ml|json)$' || continue
    if [ -s "$f" ] && grep -qiE 'paths|openapi|swagger|components' "$f" 2>/dev/null; then
      spec_touched=1; break
    fi
  done <<< "$changed"
fi

# --- escape hatch: the task declared the contract untouched ---
if [ "$spec_touched" -eq 0 ] && [ -f .claude/groundwork/task-state.md ]; then
  if grep -qiE '^[[:space:]]*-?[[:space:]]*OpenAPI:[[:space:]]*n/?a' .claude/groundwork/task-state.md 2>/dev/null; then
    exit 0
  fi
fi

if [ "$spec_touched" -eq 0 ] && [ "$comment_only" -eq 1 ]; then
  # Comments only: nothing to document, but the generation check below still applies.
  exit 0
fi

if [ "$spec_touched" -eq 0 ]; then
  {
    echo "groundwork openapi-gate: the API contract surface changed but the OpenAPI spec did not — not done yet."
    echo "Changed contract files:"
    printf '%s' "$touched" | sed 's/^/  /'
    echo "Update the annotations for every touched endpoint — each response code the endpoint can return"
    echo "(incl. 401/403/404/422), the request body from the FormRequest rules, and the response schema from"
    echo "the JsonResource. See guidelines/openapi-protocol.md."
    echo "If this change provably does not touch the contract (pure internal refactor), record"
    echo "'- OpenAPI: n/a — <reason>' in .claude/groundwork/task-state.md. (disable with gates.openapi_on_stop=false)"
  } >&2
  exit 2
fi

# --- the spec was touched: prove it still generates cleanly ---
gen="$(jq -r '.commands.openapi_generate // empty' .groundwork.json 2>/dev/null || true)"
gen_overridden=1
# Runner-aware default: on a `runner: host` project this resolves to a reachable host command,
# so the "does the spec still generate cleanly?" half actually runs instead of silently skipping.
[ -n "$gen" ] || { gen="$(gw_cmd artisan l5-swagger:generate)"; gen_overridden=0; }

# Environment problems must not block: skip when the runner is unavailable.
# An explicit `commands.openapi_generate` override wins: only its own Sail dependency is checked.
if [ "$gen_overridden" = "1" ]; then
  case "$gen" in *vendor/bin/sail*) [ -x ./vendor/bin/sail ] || exit 0 ;; esac
else
  gw_runner_ready || exit 0
fi
command -v timeout >/dev/null 2>&1 && gen="timeout 120 $gen"

# shellcheck disable=SC2086
out="$($gen 2>&1)"; status=$?
if [ "$status" -ne 0 ]; then
  # A missing artisan command / container down is an env issue, not a bad spec — do not block.
  # Same rule the other two gates use: a command that never RAN is an environment problem; a
  # substring inside real generator output is not. Exit 127 is conclusive; otherwise the phrase
  # counts only when nothing indicates the generator actually produced results.
  gen_ran='@OA|\$ref|operationId|schemas?|Generating|Regenerating|annotation'
  gen_env='is not defined|Could not open input file|command not found|No such container|Cannot connect|Is the docker daemon running'
  if [ "$status" -eq 127 ] || { printf '%s' "$out" | grep -qE "$gen_env" \
       && ! printf '%s' "$out" | grep -qiE "$gen_ran"; }; then
    echo "groundwork openapi-gate: the generate command could not run — the spec was NOT verified." >&2
    exit 1
  fi
  {
    echo "groundwork openapi-gate: OpenAPI generation FAILED — the spec is broken, not done yet."
    printf '%s\n' "$out" | tail -30
  } >&2
  exit 2
fi

# swagger-php reports schema problems as warnings on a zero exit — treat them as failures.
if printf '%s' "$out" | grep -qiE '(warning|error|deprecated).*(@OA|OA\\|\$ref|operationid|schema)' \
   || printf '%s' "$out" | grep -qiE '\$ref .*not (found|defined)|Required @OA\\[A-Za-z]+\(\) not found|same operationId|failed to generate|multiple @OA'; then
  {
    echo "groundwork openapi-gate: OpenAPI generated with warnings — unresolved refs / duplicate operationIds / malformed schemas."
    printf '%s\n' "$out" | grep -iE 'warning|error' | tail -20
  } >&2
  exit 2
fi

exit 0
