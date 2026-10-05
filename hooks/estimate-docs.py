#!/usr/bin/env python3
"""Groundwork plugin :: Stop hook — an estimate written into a document obeys the chat rules (GW34-AC2).

`estimate-claim.sh` reads the chat message. The estimates the user complained about most (person-hours
for a CEO, a total that did not add up, "5 days" for work the agent does in an afternoon) were written
into files under docs/ and into texts for forwarding — where no gate looked. This one looks there:

  BLOCK  person-day / person-hour / man-hour units (`человеко-…`), anywhere in a changed doc or an
         outbound block
  BLOCK  "N days / N дней" next to an estimate, unless the same line names a wait (approval, review)
  BLOCK  a table whose total row (Итого / Всего / Total / Разом) does not equal the sum of its rows

Scope: files under docs/ written or edited in this turn (from the transcript), plus ```outbound blocks
in the last message. Inert outside a Groundwork project and under `gates.estimate_claim: false`; any
error → silent allow. One re-entry: `stop_hook_active` → silent.
"""

import json
import os
import re
import sys

HUMAN_UNIT = re.compile(r"человеко[-‑ ]?(час|дн|день|недел)\w*|person[- ]?(day|hour)s?|man[- ]?(day|hour)s?", re.I)
DAYS = re.compile(r"\b\d+([.,]\d+)?\s*(-\s*\d+\s*)?(дн(я|ей)|день|days?|working days?|раб\w* дн\w*)\b", re.I)
WAIT_WORD = re.compile(r"ожидани|одобрени|апрув|ревью|review|approval|wait|согласовани|модераци|Meta|клиент", re.I)
TOTAL_ROW = re.compile(r"^\s*\|\s*\**(Итого|Всего|Total|Разом|Сума|Сумма)\b", re.I)
HOURS_CELL = re.compile(r"^\**\s*(\d+(?:[.,]\d+)?)\s*(ч|h|час\w*|hrs?|hours?)?\s*\**$|^\**\s*(\d+):([0-5]\d)\s*\**$", re.I)
OUTBOUND = re.compile(r"^```outbound[^\n]*\n(.*?)^```", re.M | re.S)


def read_payload():
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def gate_enabled(cwd):
    path = os.path.join(cwd, ".groundwork.json")
    if not os.path.isfile(path):
        return False
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
        return (cfg.get("gates") or {}).get("estimate_claim") is not False
    except Exception:
        return True


def docs_edited(transcript, cwd):
    paths, seen = [], set()
    try:
        lines = open(transcript, encoding="utf-8", errors="ignore").readlines()
    except Exception:
        return paths
    turn = []
    for line in lines:
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get("type") == "user" and not e.get("isMeta"):
            c = (e.get("message") or {}).get("content")
            if isinstance(c, str) or (isinstance(c, list) and not any(
                    isinstance(x, dict) and x.get("type") == "tool_result" for x in c)):
                turn = []
                continue
        if e.get("type") == "assistant":
            for x in (e.get("message") or {}).get("content") or []:
                if isinstance(x, dict) and x.get("type") == "tool_use" and x.get("name") in ("Write", "Edit", "MultiEdit"):
                    turn.append(str((x.get("input") or {}).get("file_path") or ""))
    for p in turn:
        rel = os.path.relpath(p, cwd) if os.path.isabs(p) else p
        if rel.startswith("docs" + os.sep) and rel.endswith(".md") and rel not in seen and os.path.isfile(os.path.join(cwd, rel)):
            seen.add(rel)
            paths.append(rel)
    return paths


def hours_of(cell):
    m = HOURS_CELL.match(cell.strip())
    if not m:
        return None
    if m.group(1):
        return float(m.group(1).replace(",", "."))
    return int(m.group(3)) + int(m.group(4)) / 60.0


def table_problems(text):
    problems, block = [], []
    for line in text.splitlines() + [""]:
        if line.strip().startswith("|"):
            block.append(line)
            continue
        if block:
            problems += check_table(block)
            block = []
    return problems


def check_table(rows):
    """Only the first total row of a table is checked, against every numeric row above it."""
    parsed = []
    for r in rows:
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells):
            continue
        parsed.append((bool(TOTAL_ROW.match(r)), cells))
    total_at = next((i for i, (is_total, _) in enumerate(parsed) if is_total), None)
    if total_at is None or total_at < 2:
        return []
    out = []
    total_cells = parsed[total_at][1]
    for col in range(1, len(total_cells)):
        want = hours_of(total_cells[col])
        if want is None:
            continue
        body = [hours_of(c[col]) for _, c in parsed[:total_at] if col < len(c)]
        body = [v for v in body if v is not None]
        if len(body) >= 2 and abs(sum(body) - want) > 0.05:
            out.append("a total of %g in column %d while its rows add up to %g" % (want, col + 1, sum(body)))
    return out


def scan(label, text):
    found = []
    m = HUMAN_UNIT.search(text)
    if m:
        found.append("%s: «%s» — estimate in the agent's active time; a person's time is its own line, in hours" % (label, m.group(0)))
    for line in text.splitlines():
        d = DAYS.search(line)
        if d and not WAIT_WORD.search(line):
            found.append("%s: «%s» — an estimate in days with no wait named on the line" % (label, d.group(0)))
            break
    for p in table_problems(text):
        found.append("%s: %s — re-add the rows" % (label, p))
    return found


def main():
    payload = read_payload()
    if not payload or payload.get("stop_hook_active"):
        return
    cwd = payload.get("cwd") or os.getcwd()
    if not gate_enabled(cwd):
        return
    found = []
    for rel in docs_edited(payload.get("transcript_path") or "", cwd):
        try:
            found += scan(rel, open(os.path.join(cwd, rel), encoding="utf-8").read())
        except Exception:
            continue
    for body in OUTBOUND.findall(payload.get("last_assistant_message") or ""):
        found += scan("outbound text", body)
    if not found:
        return
    try:
        log = os.path.join(cwd, ".claude", "groundwork", "estimate-claims.log")
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "a", encoding="utf-8") as fh:
            fh.write("docs\t%s\t%s\n" % (payload.get("session_id", "unknown"), found[0][:160]))
    except Exception:
        pass
    print(json.dumps({
        "decision": "block",
        "reason": "groundwork estimate-docs:\n- " + "\n- ".join(found[:6])
        + "\nNumbers come from hooks/estimate-ledger.sh --report (median and sample size).",
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
