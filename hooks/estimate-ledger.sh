#!/usr/bin/env bash
# Groundwork plugin :: the estimate ledger — measured agent time, not an opinion.
#
# Wave 18. Every other rule in this plugin that survived contact with real use has a mechanism
# behind it; estimates had exhortation only, and nothing ever recorded what the work actually took.
# This records it.
#
# The measurement: Claude Code writes one JSONL line per event to ~/.claude/projects/<slug>/, each
# carrying a `timestamp`. Active agent time is the sum of inter-event gaps at or below the idle
# threshold — gaps above it are the human reading, deciding, or away. Calendar span overstates the
# work by roughly 3× and is recorded alongside, never instead.
#
# Modes:
#   --record    append one row for the task the checkpoint describes (called by final-check)
#   --report    medians, p75 and sample size, per source, for this project and the whole corpus
#   --backfill  seed the corpus from git history, segmenting on commit windows
#
# Only durations and identifiers are ever written. No transcript content enters the ledger.
#
# Silent and exit-0 on every failure, exactly like every other hook here: a missing python3, an
# unreadable transcript or a hand-edited checkpoint must cost a measurement, never a session.
set -uo pipefail

LEDGER="${GW_LEDGER:-$HOME/.claude/groundwork/estimates.tsv}"
PROJECTS_DIR="${GW_PROJECTS_DIR:-$HOME/.claude/projects}"
HEADER='finished_at	project	level	kind	slug	active_min	calendar_min	promised_min	source	branch'

# --- configuration (absent keys mean the defaults) -------------------------------------------
cfg() { # key default
  local v=''
  if [ -f .groundwork.json ] && command -v jq >/dev/null 2>&1; then
    v="$(jq -r "$1 // empty" .groundwork.json 2>/dev/null || true)"
  fi
  [ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}

IDLE="$(cfg '.estimates.idle_seconds' 120)"
MIN_SAMPLE="$(cfg '.estimates.min_sample' 5)"
case "$IDLE" in ''|*[!0-9]*) IDLE=120 ;; esac
case "$MIN_SAMPLE" in ''|*[!0-9]*) MIN_SAMPLE=5 ;; esac

# --- project identity ------------------------------------------------------------------------
#
# Claude Code names a transcript directory after the working directory with the separators
# flattened to `-`. A worktree gets its own sibling directory, `<project>--claude-worktrees-<name>`;
# 14 of this author's 40 directories are worktrees, and counting them apart would compute every
# per-project median from a fraction of its sample. The key collapses them into the parent.
gw_project_key() { # abs_path
  printf '%s' "$1" | sed -e 's#[/._]#-#g' -e 's#--claude-worktrees-.*$##'
}

# Every transcript directory belonging to this project, worktrees included.
gw_transcript_dirs() { # project_key
  [ -d "$PROJECTS_DIR" ] || return 0
  find "$PROJECTS_DIR" -maxdepth 1 -type d -name "$1" -o -maxdepth 1 -type d -name "$1--claude-worktrees-*" 2>/dev/null
}

# --- the measurement --------------------------------------------------------------------------
#
# Reads `timestamp` from each line and tolerates every unknown record type: a transcript format
# whose records carry no timestamp yields no rows rather than wrong ones.
gw_active_minutes() { # start_iso end_iso dir...
  command -v python3 >/dev/null 2>&1 || { printf '\t'; return 0; }
  local s="$1" e="$2"; shift 2
  GW_START="$s" GW_END="$e" GW_IDLE="$IDLE" GW_DIRS="$*" python3 - <<'PY' 2>/dev/null || printf '\t'
import os, glob, datetime

def parse(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None

start = parse(os.environ.get("GW_START", "")) or datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
end = parse(os.environ.get("GW_END", "")) or datetime.datetime.max.replace(tzinfo=datetime.timezone.utc)
idle = float(os.environ.get("GW_IDLE", "120"))

ts = []
for d in os.environ.get("GW_DIRS", "").split():
    for f in glob.glob(os.path.join(d, "*.jsonl")):
        try:
            with open(f, errors="ignore") as fh:
                for line in fh:
                    i = line.find('"timestamp":"')
                    if i < 0:
                        continue
                    t = parse(line[i + 13:i + 37].split('"')[0])
                    if t is not None and start <= t <= end:
                        ts.append(t)
        except Exception:
            continue

if len(ts) < 2:
    print("\t")
else:
    ts.sort()
    gaps = [(ts[i + 1] - ts[i]).total_seconds() for i in range(len(ts) - 1)]
    active = sum(g for g in gaps if 0 <= g <= idle) / 60
    span = (ts[-1] - ts[0]).total_seconds() / 60
    print("%.0f\t%.0f" % (active, span))
PY
}

# --- the checkpoint ---------------------------------------------------------------------------
state_field() { # file regex
  grep -iE "^[[:space:]]*-?[[:space:]]*$2:" "$1" 2>/dev/null | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' \
    | tr -d '*_`' | sed -E 's/[[:space:]]+$//'
}

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40; }

# The ledger is created on first write, header first, so a hand-read of the file explains itself.
ensure_ledger() {
  mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || return 1
  [ -s "$LEDGER" ] || printf '%s\n' "$HEADER" >> "$LEDGER" 2>/dev/null || return 1
  return 0
}

append_row() { # level kind slug active calendar promised source branch
  ensure_ledger || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown')" \
    "$PROJECT_NAME" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$LEDGER" 2>/dev/null || true
}

# --- modes ------------------------------------------------------------------------------------

mode_record() { # promised_min kind_override
  local state=".claude/groundwork/task-state.md"
  [ -f "$state" ] || return 0

  # A checkpoint without `Started:` is skipped. Inferring a start time from a file mtime or the
  # first transcript event would produce a number that looks measured and is not.
  local started; started="$(state_field "$state" 'Started')"
  [ -n "$started" ] || { printf 'groundwork: no `Started:` in the checkpoint — nothing recorded.\n' >&2; return 0; }

  local level kind slug now measured active calendar
  level="$(state_field "$state" 'Level' | awk '{print $1}')"
  kind="${2:-$(state_field "$state" 'Kind')}"
  slug="$(slugify "$(state_field "$state" 'Task')")"
  [ -n "$slug" ] || slug="$(slugify "$(head -1 "$state" 2>/dev/null | sed -E 's/^#+[[:space:]]*(Task:)?[[:space:]]*//')")"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')"

  measured="$(gw_active_minutes "$started" "$now" $TRANSCRIPT_DIRS)"
  active="$(printf '%s' "$measured" | cut -f1)"
  calendar="$(printf '%s' "$measured" | cut -f2)"
  [ -n "$active" ] || { printf 'groundwork: no transcript events in the task window — nothing recorded.\n' >&2; return 0; }

  append_row "${level:-unknown}" "${kind:-unknown}" "${slug:-unknown}" "$active" "$calendar" "${1:-}" "task" "$BRANCH"
  GW_RECORDED=1
  printf 'groundwork: recorded %s active min (calendar %s) for %s.\n' "$active" "$calendar" "${slug:-unknown}" >&2
}

# The engine's own path: record when the checkpoint says the task shipped, and never twice.
#
# `Done` is deliberately NOT in the mode canon (hooks/lib.sh) — hooks/session-start.sh relies on a
# finished checkpoint yielding no canonical mode, which is what stops it re-injecting a shipped task
# every session. So the terminal marker is matched here, on its own, rather than by widening the canon.
mode_record_if_done() {
  local state=".claude/groundwork/task-state.md"
  [ -f "$state" ] || return 0

  local mode; mode="$(state_field "$state" 'Mode' | awk -F'|' '{print $1}' | awk '{print $1}' \
    | tr '[:upper:]' '[:lower:]')"
  [ "$mode" = "done" ] || return 0

  # The key is the task, not the file: a second task with the same title still gets its own row.
  local started slug key marker
  started="$(state_field "$state" 'Started')"
  [ -n "$started" ] || return 0
  slug="$(slugify "$(state_field "$state" 'Task')")"
  key="${slug:-unknown}@${started}"
  marker=".claude/groundwork/ledger-recorded"
  [ -f "$marker" ] && grep -Fqx "$key" "$marker" 2>/dev/null && return 0

  GW_RECORDED=0
  mode_record "" ""
  [ "$GW_RECORDED" = "1" ] || return 0     # nothing was written -> nothing to remember
  printf '%s\n' "$key" >> "$marker" 2>/dev/null || true
}

mode_report() { # kind_filter level_filter
  [ -s "$LEDGER" ] || { printf 'groundwork: the estimate ledger is empty. Run --backfill to seed it from git history.\n'; return 0; }
  command -v python3 >/dev/null 2>&1 || return 0
  GW_KIND="${1:-}" GW_LEVEL="${2:-}" GW_PROJECT="$PROJECT_NAME" GW_MIN="$MIN_SAMPLE" GW_FILE="$LEDGER" python3 - <<'PY' 2>/dev/null || true
import os, statistics

f, proj = os.environ["GW_FILE"], os.environ["GW_PROJECT"]
kind, level, minimum = os.environ.get("GW_KIND", ""), os.environ.get("GW_LEVEL", ""), int(os.environ.get("GW_MIN", "5"))

rows = []
with open(f, errors="ignore") as fh:
    head = fh.readline().rstrip("\n").split("\t")
    for line in fh:
        p = line.rstrip("\n").split("\t")
        if len(p) == len(head):
            rows.append(dict(zip(head, p)))

def keep(r):
    return (not kind or r["kind"] == kind) and (not level or r["level"] == level)

def stats(rs):
    v = sorted(float(r["active_min"]) for r in rs if r["active_min"].replace(".", "", 1).isdigit())
    if not v:
        return None
    return len(v), statistics.median(v), v[min(len(v) - 1, int(len(v) * 0.75))]

# `source=task` is this project's own unit and wins whenever its sample clears min_sample;
# `source=commit-window` is the noisier seed and is never silently mixed into it.
print("estimate ledger — active agent minutes (idle-gap method)")
for scope, rs in (("this project (%s)" % proj, [r for r in rows if r["project"] == proj]), ("all projects", rows)):
    rs = [r for r in rs if keep(r)]
    line = []
    for src in ("task", "commit-window"):
        s = stats([r for r in rs if r["source"] == src])
        if s:
            n, med, p75 = s
            mark = "" if (src == "task" and n >= minimum) else ("  (n < %d — small sample)" % minimum if src == "task" else "  (seed unit, not a Groundwork task)")
            line.append("  %-14s n=%-4d median=%-5.0f p75=%-5.0f%s" % (src, n, med, p75, mark))
    print(" %s:" % scope)
    print("\n".join(line) if line else "   no rows")
PY
}

mode_backfill() { # root
  local root="${1:-$(cd .. 2>/dev/null && pwd)}"
  [ -n "$root" ] && [ -d "$root" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  ensure_ledger || return 0
  local cfg_file repo key dirs
  # `find` at depth 2 keeps this to sibling projects rather than walking a home directory.
  find "$root" -maxdepth 2 -name .groundwork.json -type f 2>/dev/null | while read -r cfg_file; do
    repo="$(dirname "$cfg_file")"
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
    key="$(gw_project_key "$repo")"
    dirs="$(gw_transcript_dirs "$key" | tr '\n' ' ')"
    [ -n "$dirs" ] || continue

    # One pass over the project's transcripts, then every commit window is sliced out of the
    # timestamps already in memory. Re-reading them per window turned a seed into minutes of work.
    # Merge commits are excluded: their window is the branch's whole life, not a slice of work.
    # The commit list travels in the environment, not on stdin: the heredoc below already owns
    # stdin, and piping into it silently delivers an empty log.
    GW_COMMITS="$(git -C "$repo" log --no-merges --reverse --format='%aI%x09%s' --since='6 months ago' 2>/dev/null)" \
    GW_DIRS="$dirs" GW_IDLE="$IDLE" GW_PROJECT="$(basename "$repo")" GW_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    python3 - <<'PY' >> "$LEDGER" 2>/dev/null || true
import os, sys, glob, datetime, bisect, re

def parse(s):
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None

idle = float(os.environ.get("GW_IDLE", "120"))
project, now = os.environ["GW_PROJECT"], os.environ["GW_NOW"]

ts = []
for d in os.environ.get("GW_DIRS", "").split():
    for f in glob.glob(os.path.join(d, "*.jsonl")):
        try:
            with open(f, errors="ignore") as fh:
                for line in fh:
                    i = line.find('"timestamp":"')
                    if i < 0:
                        continue
                    t = parse(line[i + 13:i + 37].split('"')[0])
                    if t is not None:
                        ts.append(t)
        except Exception:
            continue
if not ts:
    sys.exit(0)
ts.sort()

def slug(s):
    return re.sub(r"^-+|-+$", "", re.sub(r"[^a-z0-9]+", "-", s.lower()))[:40]

commits = []
for line in os.environ.get("GW_COMMITS", "").splitlines():
    p = line.rstrip("\n").split("\t", 1)
    if len(p) == 2 and parse(p[0]):
        commits.append((parse(p[0]), p[1]))

for (t0, _), (t1, subject) in zip(commits, commits[1:]):
    lo, hi = bisect.bisect_left(ts, t0), bisect.bisect_right(ts, t1)
    window = ts[lo:hi]
    if len(window) < 2:
        continue
    gaps = [(window[i + 1] - window[i]).total_seconds() for i in range(len(window) - 1)]
    active = sum(g for g in gaps if 0 <= g <= idle) / 60
    # A window with no measurable activity is a window with no transcript: it is absent from the
    # corpus, not a zero in it.
    if active < 1:
        continue
    span = (window[-1] - window[0]).total_seconds() / 60
    print("\t".join([now, project, "unknown", "unknown", slug(subject),
                     "%.0f" % active, "%.0f" % span, "", "commit-window", ""]))
PY
    printf 'groundwork: backfilled %s\n' "$(basename "$repo")" >&2
  done
}

# --- entry ------------------------------------------------------------------------------------

MODE=''; PROMISED=''; KIND=''; LEVEL=''; ROOT=''
for arg in "$@"; do
  case "$arg" in
    --record|--report|--backfill) MODE="${arg#--}" ;;
    --record-if-done) MODE='record-if-done' ;;
    --promised=*) PROMISED="${arg#*=}" ;;
    --kind=*)     KIND="${arg#*=}" ;;
    --level=*)    LEVEL="${arg#*=}" ;;
    --root=*)     ROOT="${arg#*=}" ;;
  esac
done
[ -n "$MODE" ] || { printf 'usage: estimate-ledger.sh --record|--record-if-done|--report|--backfill [--kind=k] [--level=L] [--promised=min] [--root=dir]\n' >&2; exit 0; }

# Inert outside a Groundwork project and under the opt-out — the contract every hook here honours.
[ -f .groundwork.json ] || exit 0
# Read the opt-out directly rather than through cfg(): jq's `// empty` treats `false` as absent,
# so `.estimates.ledger // empty` on an explicit `false` would return the default and switch the
# opt-out off. Same form the other gates use.
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.estimates.ledger' .groundwork.json 2>/dev/null)" = "false" ] && exit 0
fi

PROJECT_ABS="$(pwd)"
PROJECT_KEY="$(gw_project_key "$PROJECT_ABS")"
PROJECT_NAME="$(basename "$(printf '%s' "$PROJECT_ABS" | sed -E 's#--claude-worktrees-.*$##')")"
TRANSCRIPT_DIRS="$(gw_transcript_dirs "$PROJECT_KEY" | tr '\n' ' ')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"

GW_RECORDED=0

case "$MODE" in
  record)         mode_record "$PROMISED" "$KIND" ;;
  record-if-done) mode_record_if_done ;;
  report)         mode_report "$KIND" "$LEVEL" ;;
  backfill)       mode_backfill "$ROOT" ;;
esac
exit 0
