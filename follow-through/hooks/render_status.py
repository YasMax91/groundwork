#!/usr/bin/env python3
"""follow-through :: render docs/ai/status.md into the HTML page published as its `mirror:` artifact.

    python3 render_status.py <repo dir> <out.html> [--ref origin/development]

With --ref the page is rendered from the status committed on that branch — the integration branch is the
only copy every lane agrees on, and a lane's own copy may lag it (rendering from one rolled the mirror back).

The mirror is rebuilt from the file every time, never edited on its own, so a session that moved a row
republishes with two calls: this script, then an Artifact publish to the `mirror:` URL. The page shows
the counts by status, each environment's branch head and how far it is behind the integration branch
(read from git at render time), and every row with its proof — commits linked to the remote.
"""

import html
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lanes  # noqa: E402

STATUSES = ["doing", "blocked", "todo", "done", "dropped"]
LABEL = {"doing": "в работе", "blocked": "заблокировано", "todo": "не начато", "done": "сделано", "dropped": "снято"}


def parse(text):
    body = re.sub(r"^---\n.*?\n---\n", "", text, flags=re.S)
    title, intro, sections, cur = "Status", [], [], None
    for line in body.splitlines():
        if line.startswith("# "):
            title = line[2:].strip()
        elif line.startswith("## "):
            cur = {"name": line[3:].strip(), "note": [], "rows": []}
            sections.append(cur)
        elif line.strip().startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not cells or cells[0] in ("ID", "") or re.fullmatch(r":?-{2,}:?", cells[0]):
                continue
            if cur is None:  # a table before any `##` heading still belongs on the page
                cur = {"name": "План", "note": [], "rows": []}
                sections.append(cur)
            cells += [""] * (6 - len(cells))
            cur["rows"].append(dict(zip(["id", "item", "status", "lane", "proof", "updated"], cells[:6])))
        elif line.strip():
            (cur["note"] if cur else intro).append(line.strip())
    return title, " ".join(intro), sections


def inline(text, remote):
    out = html.escape(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    if remote:
        out = re.sub(r"\b([0-9a-f]{7,40})\b", lambda m: '<a href="%s/commit/%s">%s</a>' % (remote, m.group(1), m.group(1)), out)
    return out


def remote_url(root):
    url = lanes.git(root, "remote", "get-url", "origin")
    m = re.match(r"(?:git@|https://)([^/:]+)[/:](.+?)(?:\.git)?$", url)
    return "https://%s/%s" % (m.group(1), m.group(2)) if m else ""


def render(root, ref=""):
    text = lanes.status_at(root, ref) if ref else lanes.read_status(root)
    if not text:
        sys.exit("render_status: no %s in %s" % (lanes.STATUS_REL, root))
    fm = lanes.front_matter(text)
    title, intro, sections = parse(text)
    remote = remote_url(root)
    base = lanes.base_ref(root, {})
    head = lanes.git(root, "rev-parse", "--short", ref or "HEAD")
    rows = [r for s in sections for r in s["rows"]]
    seen, dupes = set(), set()
    for r in rows:
        (dupes if r["id"] in seen else seen).add(r["id"])
    counts = {k: sum(1 for r in rows if r["status"].lower() == k) for k in STATUSES}

    envs = []
    for name, spec in (fm.get("environments") or {}).items():
        b = spec.get("branch", "")
        sha = lanes.git(root, "rev-parse", "--short", b) if b else ""
        behind = lanes.git(root, "rev-list", "--count", "%s..%s" % (b, base)) if b and base else ""
        ahead = lanes.git(root, "rev-list", "--count", "%s..%s" % (base, b)) if b and base else ""
        when = lanes.git(root, "log", "-1", "--format=%ad", "--date=short", b) if b else ""
        envs.append((name, b, sha, behind, ahead, when, spec.get("version_url", "")))

    tally = "".join('<button class="chip" data-f="%s" aria-pressed="false"><span class="pill s-%s"></span>'
                    '<b>%d</b> %s</button>' % (k, k, counts[k], LABEL[k]) for k in STATUSES if counts[k])
    env_html = ""
    for name, b, sha, behind, ahead, when, vurl in envs:
        lag = ("отстаёт на %s" % behind) if behind and behind != "0" else "актуально"
        extra = (" · своих коммитов %s" % ahead) if ahead and ahead != "0" else ""
        live = ('<a href="%s">живая версия</a>' % html.escape(vurl)) if vurl else "собрано CD, выкатка вручную"
        env_html += ('<div class="env"><div class="env-name">%s</div><div class="env-sha">%s</div>'
                     '<div class="env-meta">%s · %s от %s%s · %s</div></div>') % (
            html.escape(name), inline(sha or "?", remote), html.escape(b), lag, html.escape(base or "?"), extra,
            "%s · %s" % (html.escape(when or "?"), live))
    body = ""
    for s in sections:
        trs = "".join(
            '<tr data-s="{s}"><td class="id">{id}{dup}</td><td class="item">{item}</td><td><span class="tag s-{s}">{label}</span></td>'
            '<td class="lane">{lane}</td><td class="proof">{proof}</td><td class="upd">{upd}</td></tr>'.format(
                s=html.escape(r["status"].lower()), id=html.escape(r["id"]),
                dup=(' <span class="tag s-blocked" title="this ID is used by more than one row">дубль</span>' if r["id"] in dupes else ""), item=inline(r["item"], remote),
                label=LABEL.get(r["status"].lower(), html.escape(r["status"])), lane=html.escape(r["lane"]),
                proof=inline(r["proof"], remote), upd=html.escape(r["updated"])) for r in s["rows"])
        body += ('<section><h2>%s</h2>%s<div class="scroll"><table><thead><tr><th>ID</th><th>Пункт</th><th>Статус</th>'
                 '<th>Полоса</th><th>Доказательство</th><th>Обновлено</th></tr></thead><tbody>%s</tbody></table></div></section>') % (
            html.escape(s["name"]), ('<p class="note">%s</p>' % inline(" ".join(s["note"]), remote)) if s["note"] else "", trs)

    return PAGE.format(
        title=html.escape(title.replace("Status — ", "Статус ")), intro=inline(intro, remote), tally=tally,
        envs=env_html or '<p class="note">Среды не описаны.</p>', body=body,
        stamp="Собрано %s из %s @ %s%s" % (time.strftime("%Y-%m-%d %H:%M"), lanes.STATUS_REL, (ref + " ") if ref else "", head),
        total=len(rows))


PAGE = """<title>{title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Golos+Text:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
/* Layout: a ledger — environments strip, a status tally that filters, then one table per plan block. */
:root {{
  --bg: #f4f5f2; --surface: #ffffff; --line: #dfe2db; --fg: #1d221c; --muted: #646b61; --accent: #2f6f62;
  --done: #2f7a4f; --done-bg: #e3f1e8; --doing: #2f5fa8; --doing-bg: #e4ecf8; --todo: #8a6a1c; --todo-bg: #f6eed9;
  --blocked: #a8402f; --blocked-bg: #f7e4e0; --dropped: #6f6f6f; --dropped-bg: #ececec;
  --sans: "Golos Text", system-ui, -apple-system, "Segoe UI", sans-serif; --mono: "JetBrains Mono", ui-monospace, Menlo, monospace;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg: #151916; --surface: #1c211d; --line: #2e352f; --fg: #e6ebe4; --muted: #9aa397; --accent: #79c2b0;
  --done: #7fd0a0; --done-bg: #183324; --doing: #8fb4f0; --doing-bg: #1b2a40; --todo: #e2c27a; --todo-bg: #352c16;
  --blocked: #f19a88; --blocked-bg: #3a1f1a; --dropped: #a8a8a8; --dropped-bg: #2a2a2a; color-scheme: dark; }} }}
:root[data-theme="dark"] {{
  --bg: #151916; --surface: #1c211d; --line: #2e352f; --fg: #e6ebe4; --muted: #9aa397; --accent: #79c2b0;
  --done: #7fd0a0; --done-bg: #183324; --doing: #8fb4f0; --doing-bg: #1b2a40; --todo: #e2c27a; --todo-bg: #352c16;
  --blocked: #f19a88; --blocked-bg: #3a1f1a; --dropped: #a8a8a8; --dropped-bg: #2a2a2a; color-scheme: dark; }}
* {{ box-sizing: border-box; }}
body {{ background: var(--bg); color: var(--fg); font: 15px/1.55 var(--sans); }}
.wrap {{ max-width: 1180px; margin: 0 auto; padding: 32px 20px 72px; display: grid; gap: 28px; }}
h1 {{ font-size: clamp(26px, 3.4vw, 34px); font-weight: 600; margin: 0 0 6px; text-wrap: balance; }}
h2 {{ font-size: 19px; font-weight: 600; margin: 0 0 8px; text-wrap: balance; }}
.intro, .note {{ color: var(--muted); max-width: 78ch; margin: 0 0 10px; font-size: 14px; }}
.stamp {{ font: 12px var(--mono); color: var(--muted); }}
.envs {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px; }}
.env {{ background: var(--surface); border: 1px solid var(--line); border-radius: 8px; padding: 14px 16px; min-width: 0; }}
.env-name {{ font: 500 11px var(--mono); letter-spacing: .12em; text-transform: uppercase; color: var(--muted); }}
.env-sha {{ font: 500 20px var(--mono); margin: 2px 0; }}
.env-meta {{ font-size: 13px; color: var(--muted); }}
.tally {{ display: flex; flex-wrap: wrap; gap: 8px; }}
.chip {{ font: inherit; font-size: 13.5px; display: flex; align-items: center; gap: 7px; padding: 7px 13px; border-radius: 999px;
  border: 1px solid var(--line); background: var(--surface); color: var(--fg); cursor: pointer; }}
.chip b {{ font-variant-numeric: tabular-nums; }}
.chip[aria-pressed="true"] {{ border-color: var(--accent); outline: 1px solid var(--accent); }}
.chip:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}
.pill {{ width: 9px; height: 9px; border-radius: 50%; }}
.pill.s-done {{ background: var(--done); }} .pill.s-doing {{ background: var(--doing); }} .pill.s-todo {{ background: var(--todo); }}
.pill.s-blocked {{ background: var(--blocked); }} .pill.s-dropped {{ background: var(--dropped); }}
.scroll {{ overflow-x: auto; background: var(--surface); border: 1px solid var(--line); border-radius: 8px; }}
table {{ width: 100%; border-collapse: collapse; font-size: 14px; min-width: 760px; }}
th {{ text-align: left; font: 500 11px var(--mono); letter-spacing: .08em; text-transform: uppercase; color: var(--muted);
  padding: 10px 12px; border-bottom: 1px solid var(--line); }}
td {{ padding: 10px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }}
tr:last-child td {{ border-bottom: 0; }}
td.id, td.upd {{ font: 13px var(--mono); color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }}
td.item {{ min-width: 280px; }}
td.proof, td.lane {{ font: 12.5px var(--mono); color: var(--muted); overflow-wrap: anywhere; }}
.tag {{ font-size: 12px; font-weight: 500; padding: 2px 8px; border-radius: 4px; white-space: nowrap; }}
.tag.s-done {{ color: var(--done); background: var(--done-bg); }} .tag.s-doing {{ color: var(--doing); background: var(--doing-bg); }}
.tag.s-todo {{ color: var(--todo); background: var(--todo-bg); }} .tag.s-blocked {{ color: var(--blocked); background: var(--blocked-bg); }}
.tag.s-dropped {{ color: var(--dropped); background: var(--dropped-bg); }}
a {{ color: var(--accent); text-decoration: none; }} a:hover {{ text-decoration: underline; }}
code {{ font: 12.5px var(--mono); }}
@media (prefers-reduced-motion: reduce) {{ * {{ transition: none !important; }} }}
</style>
<div class="wrap">
  <header><h1>{title}</h1><p class="intro">{intro}</p><div class="stamp">{stamp} · {total} пунктов</div></header>
  <div class="envs">{envs}</div>
  <div class="tally" id="tally">{tally}</div>
  {body}
</div>
<script>
(function () {{
  var chips = document.querySelectorAll('.chip'), active = null;
  chips.forEach(function (c) {{
    c.addEventListener('click', function () {{
      active = active === c.dataset.f ? null : c.dataset.f;
      chips.forEach(function (x) {{ x.setAttribute('aria-pressed', String(x.dataset.f === active)); }});
      document.querySelectorAll('tbody tr').forEach(function (tr) {{ tr.hidden = !!active && tr.dataset.s !== active; }});
    }});
  }});
}})();
</script>
"""


if __name__ == "__main__":
    args = sys.argv[1:]
    ref = ""
    if "--ref" in args:
        i = args.index("--ref")
        ref = args[i + 1] if i + 1 < len(args) else ""
        del args[i:i + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    page = render(os.path.abspath(args[0]), ref)
    with open(args[1], "w", encoding="utf-8") as fh:
        fh.write(page)
    print("render_status: wrote %s" % args[1])
