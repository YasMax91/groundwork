#!/usr/bin/env python3
"""follow-through :: Stop hook — the turn may not end on the seven endings users complained about.

Source: 580 complaints in 2472 messages across 25 projects (docs/specs/wave-34-the-agent-hears-the-gate.md).
Each check below names its acceptance criterion. Every violation found is collected and returned to
the model in ONE `decision: block`, so a turn costs at most one re-entry; on the re-entry
(`stop_hook_active: true`) the gate is silent.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ft  # noqa: E402
import lanes  # noqa: E402

# --- the lists this gate is made of. Tune them here; the checks below never change. ---------------

# FT-AC1: the final paragraph announces work and the turn ends anyway.
ANNOUNCE = re.compile(
    r"(^|[.!:]\s+)("
    r"Беру(сь)?\b|Перехожу\b|Начинаю\b|Приступаю\b|Продолжаю\b|Запускаю\b|Делаю\b|"
    r"Сейчас (сделаю|запущу|займусь|проверю|исправлю|поправлю|допишу)\b|Дальше (делаю|беру)\b|"
    r"Next,? I'?ll\b|I'?ll now\b|Now I'?ll\b|Moving on to\b|Starting (on|with)\b|Let me now\b"
    r")",
    re.I,
)
# The same words are fine when the work honestly waits on someone else.
ANNOUNCE_WAITS = re.compile(
    r"после (тво|ваш)|когда (ответишь|подтвердишь|пришлёшь)|как только|after you|once you|when you|жду|waiting",
    re.I,
)

# FT-AC3: a question to the user written as prose.
ASK_PROSE = re.compile(
    r"скажи(те)?,? (какой|какую|что|как|где)|выбери(те)?\b|жду (тво|ваш)\w* (решени|ответ|выбор)|"
    r"продолжать\?|продолжить\?|делать\?|коммитить\?|let me know (which|whether|if)|should I\b.*\?$",
    re.I | re.M,
)

# FT-AC4: an action handed back to the user.
HAND_BACK = re.compile(
    r"залогинь(ся|тесь)|войди(те)? (в|на) (админку|систему|сайт|панель|аккаунт)|"
    r"(пришли|скинь|отправь)(те)? (мне )?(скрин|скриншот|вывод|лог)|"
    r"скажи(те)?,? как (это |оно |она )?(выглядит|отображается)|"
    r"(запусти|выполни|прогони)(те)? (это |её |его |команду )?(сам\b|сама\b|у себя|на сервере)|"
    r"send me (a |the )?screenshot|run (it|this) yourself|paste (me )?the output|log in and (check|tell)",
    re.I,
)
HAND_BACK_REASON = re.compile(
    r"нет доступа|не могу,? (потому|так как|т\.к\.)|только ты (можешь|сможешь)|"
    r"(нуж|треб)\w* тво(й|его|их|ё) (пароль|вход|подтвержд|ключ)|"
    r"no access|only you can|requires your|need your (password|credentials|approval)",
    re.I,
)

# FT-AC5: a chat-language rule, as the user writes it in CLAUDE.md.
LANG_RULE = re.compile(r"(only|только)\s+(in\s+|на\s+)?(Russian|Ukrainian|русск|украинск)", re.I)

# FT-AC6: inside an outbound block.
OUTBOUND = re.compile(r"^```outbound([^\n]*)\n(.*?)^```", re.M | re.S)
OB_LIST = re.compile(r"^\s*([-*•]|\d+[.)])\s+", re.M)
OB_IDENT = re.compile(
    r"\b[a-z][a-z0-9]*_[a-z0-9_]+\b|\b\w+::\w*|\b(AC|OQ|PB|FT|GW\d*)-?\d+\b|"
    r"\b[\w/-]+\.(php|js|ts|tsx|py|json|md|yml|yaml|sql)\b"
)
OB_AI = re.compile(r"\b(AI|ИИ|Claude|LLM|GPT)\b|нейросет|искусственн\w* интеллект", re.I)
OB_NEGATIVE = re.compile(
    r"нельзя|невозможно|не поддерживает|не позволяет|cannot|can't|not supported|not possible|doesn't support",
    re.I,
)
OB_SOURCED = re.compile(r"https?://|проверено запросом|verified by (a )?request", re.I)

# FT-AC7: UI files, a completion claim, and the proof that a screen was looked at.
UI_FILE = re.compile(
    r"(\.blade\.php|\.vue|\.tsx|\.jsx|\.svelte|\.css|\.scss|\.sass|\.less|\.dart)$|"
    r"/resources/js/|/res/layout/.*\.xml$"
)
NOT_UI = re.compile(r"/tests?/|__tests__|\.test\.|\.spec\.|\.stories\.")
DONE_CLAIM = re.compile(
    r"(?<!не )\b(готово|сделано|сделал|работает|исправил|исправлено|починил|починено|реализовал|"
    r"реализовано|done|fixed|works now|implemented)\b",
    re.I,
)
UI_UNVERIFIED = re.compile(r"UI (не проверен|not verified)\s*:", re.I)
VISUAL_TOOL = re.compile(
    r"^mcp__(Claude_Browser|plugin_playwright_playwright|playwright|claude-in-chrome|Claude_Code_iOS_Simulator)__"
)


# --- helpers ------------------------------------------------------------------------------------

def strip_code(text):
    text = OUTBOUND.sub(" ", text)
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"`[^`\n]*`", " ", text)
    text = re.sub(r"\]\([^)]*\)", "]", text)
    text = re.sub(r"https?://\S+", " ", text)
    return text


def last_paragraph(text):
    parts = [p.strip() for p in re.split(r"\n\s*\n", strip_code(text)) if p.strip()]
    return parts[-1] if parts else ""


def last_sentence(text):
    para = last_paragraph(text)
    lines = [l.strip() for l in para.splitlines() if l.strip()]
    return lines[-1] if lines else ""


def chat_language_required(cfg, cwd):
    forced = cfg.get("chat_language")
    if forced in ("off", False):
        return False
    if forced:
        return True
    for path in (os.path.join(ft.HOME, ".claude", "CLAUDE.md"), os.path.join(cwd, "CLAUDE.md")):
        try:
            with open(path, encoding="utf-8") as fh:
                if LANG_RULE.search(fh.read()):
                    return True
        except Exception:
            continue
    return False


def cyrillic_share(text):
    prose = strip_code(text)
    # Identifiers, paths and numbers are not prose in either language.
    prose = " ".join(w for w in prose.split() if not re.search(r"[_/\\.:0-9@#=<>{}|]", w))
    cyr = len(re.findall(r"[а-яёіїєґ]", prose, re.I))
    lat = len(re.findall(r"[a-z]", prose, re.I))
    return cyr, lat


def is_screenshot(tool):
    name, data = tool["name"], json.dumps(tool["input"], ensure_ascii=False)
    if not VISUAL_TOOL.search(name):
        return False
    return "screenshot" in name or "screenshot" in data or '"zoom"' in data


def edited_path(tool):
    if tool["name"] in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        return str(tool["input"].get("file_path") or tool["input"].get("notebook_path") or "")
    return ""


# --- the checks ---------------------------------------------------------------------------------

def check_announce(msg):
    para = last_paragraph(msg)
    if not para or len(para) > 400 or "?" in para:
        return None
    if ANNOUNCE.search(para) and not ANNOUNCE_WAITS.search(para):
        return (
            "announce_stop",
            para,
            "The turn ends on an announcement («" + para[:80] + "»). Do that step now, in this turn; "
            "end the turn only when the work is done, or when you genuinely wait on the user — then say what you wait for.",
        )
    return None


def check_empty(msg, user_text):
    if len(user_text) <= 20:
        return None
    if not msg.strip() or msg.strip().rstrip(".").lower() == "no response requested":
        return (
            "empty_reply",
            user_text,
            "The user wrote «" + user_text[:80] + "» and the turn ends with no answer. Answer it, or continue the work it asks for.",
        )
    return None


def check_prose_question(msg, tools):
    if any(t["name"] == "AskUserQuestion" for t in tools):
        return None
    tail = last_sentence(msg)
    para = last_paragraph(msg)
    if tail.endswith("?") or ASK_PROSE.search(para):
        return (
            "prose_question",
            tail,
            "The turn ends on a question written as prose («" + tail[:80] + "»). Ask it through AskUserQuestion "
            "with clickable options (recommended option first) — or, if the answer is already yours to give, decide and continue.",
        )
    return None


def check_hand_back(msg):
    text = strip_code(msg)
    m = HAND_BACK.search(text)
    if m and not HAND_BACK_REASON.search(text):
        return (
            "hand_back",
            m.group(0),
            "The message hands the user «" + m.group(0) + "». If you have the access — a browser tool, the shell, a seeded "
            "local login, the server key — do it yourself now. If you truly cannot, say why on the same line (e.g. «нет доступа к …»).",
        )
    return None


def check_language(msg, cfg, cwd):
    if not chat_language_required(cfg, cwd):
        return None
    cyr, lat = cyrillic_share(msg)
    if cyr + lat < 120 or cyr >= lat:
        return None
    return (
        "language",
        msg[:120],
        "The user's CLAUDE.md requires Russian or Ukrainian in chat, and this message is mostly not. Rewrite it in the "
        "user's language; code, identifiers and text inside ```outbound blocks stay as they are.",
    )


def check_outbound(msg, cfg):
    problems = []
    for m in OUTBOUND.finditer(msg):
        opts, body = m.group(1), m.group(2)
        limit = cfg.get("outbound_max", 900)
        lm = re.search(r"max=(\d+)", opts)
        if lm:
            limit = int(lm.group(1))
        if "—" in body:
            problems.append("«—» (use «-»)")
        if "lists" not in opts and OB_LIST.search(body):
            problems.append("a bulleted or numbered list")
        if "ids-ok" not in opts:
            im = OB_IDENT.search(body)
            if im:
                problems.append("an internal identifier «" + im.group(0) + "»")
        if "ai-ok" not in opts:
            am = OB_AI.search(body)
            if am:
                problems.append("a mention of «" + am.group(0) + "»")
        if len(body) > limit:
            problems.append("%d characters (limit %d)" % (len(body), limit))
        nm = OB_NEGATIVE.search(body)
        if nm and not OB_SOURCED.search(body):
            problems.append("«" + nm.group(0) + "» about a system with no source (a link, or «проверено запросом»)")
    if not problems:
        return None
    return (
        "outbound",
        "; ".join(problems),
        "The text for forwarding has: " + "; ".join(problems) + ". Rewrite the outbound block — short, plain, in the "
        "addressee's words, every negative claim sourced.",
    )


def check_ui_proof(msg, tools):
    last_ui = -1
    for i, t in enumerate(tools):
        path = edited_path(t)
        if path and UI_FILE.search(path) and not NOT_UI.search(path):
            last_ui = i
    if last_ui < 0:
        return None
    if not DONE_CLAIM.search(strip_code(msg)) or UI_UNVERIFIED.search(msg):
        return None
    if any(is_screenshot(t) for t in tools[last_ui + 1:]):
        return None
    shown = edited_path(tools[last_ui])
    return (
        "ui_proof",
        shown,
        "Screens changed (last: " + os.path.basename(shown) + ") and the message claims it works, but no browser or "
        "simulator screenshot was taken after the change. Open the changed screens and look at them now — or replace the "
        "claim with a line «UI не проверен: <screens>» and why.",
    )


STATUS_EVENT = re.compile(r"\bgit\s+(commit|merge|push|cherry-pick|rebase)\b|\bgh\s+pr\s+merge\b")
STATUS_UNCHANGED = re.compile(r"статус не меняется\s*:|status unchanged\s*:", re.I)


def check_freshness(msg, cwd, sid, cfg):
    """LN-AC3: claiming completion while the base moved under files this lane changed."""
    if not sid or not lanes.common_dir(cwd) or not DONE_CLAIM.search(strip_code(msg)):
        return None
    me = lanes.load(cwd, sid)
    n, subjects, touching = lanes.base_drift(cwd, lanes.base_ref(cwd, cfg), me.get("files", []))
    if not touching:
        return None
    return (
        "freshness",
        ", ".join(touching[:4]),
        "The base moved by %d commits since this lane forked, and they change files you changed (%s). Rebase on the "
        "base and re-run the checks before calling it done." % (n, ", ".join(touching[:6])),
    )


def check_status(msg, cwd, tools, cfg):
    """ST-AC2/ST-AC3, wave 36: a commit or deploy updates docs/ai/status.md; the mirror follows the
    integration branch and is republished by the session whose push changed the status there."""
    root = lanes.toplevel(cwd) or cwd
    text = lanes.read_status(root)
    if not text:
        return []
    found = []
    status_abs = os.path.realpath(os.path.join(root, lanes.STATUS_REL))
    status_re = re.compile(r"(^|/)docs/ai/status\.md$")
    cmds = [(i, str(t["input"].get("command") or "")) for i, t in enumerate(tools) if t["name"] == "Bash"]
    commits = [c for _, c in cmds if re.search(r"\bgit\s+(commit|cherry-pick)\b", c)]
    envs = lanes.front_matter(text).get("environments") or {}
    deploys = []
    for _, c in cmds:
        for spec in envs.values():
            pat = spec.get("deploy_cmd")
            try:
                if pat and re.search(pat, c):
                    deploys.append(c)
            except re.error:
                pass
    edited = False
    for t in tools:
        p = edited_path(t)
        if p and os.path.realpath(p if os.path.isabs(p) else os.path.join(cwd, p)) == status_abs:
            edited = True
        if t["name"] == "Bash" and lanes.shell_writes(str(t["input"].get("command") or ""), status_re):
            edited = True
    if (commits or deploys) and not edited and not STATUS_UNCHANGED.search(msg):
        found.append((
            "status_event",
            (commits or deploys)[0][:80],
            "This turn committed or deployed, and %s was not updated. Mark what moved (status, lane, proof = the "
            "commit or deploy) — or, if nothing in the plan changed, add a line «статус не меняется: <почему>»." % lanes.STATUS_REL,
        ))
    base = lanes.base_ref(root, cfg)
    mirror = lanes.front_matter(lanes.status_at(root, base) or text).get("mirror")
    pushed = [i for i, c in cmds if re.search(r"\bgit\s+push\b|\bgh\s+pr\s+merge\b", c)]
    if mirror and pushed and base:
        blob = lanes.status_blob(root, base)
        published_after = any(t["name"] == "Artifact" and str(t["input"].get("url") or "").rstrip("/") == mirror.rstrip("/")
                              for t in tools[pushed[-1] + 1:])
        if blob and blob != lanes.mirror_published_blob(root) and not published_after:
            found.append((
                "status_mirror",
                mirror,
                "Your push changed %s on %s, and its mirror %s still shows the previous version. Render it from the "
                "integration branch — python3 <follow-through>/hooks/render_status.py %s <out.html> --ref %s — and publish "
                "with url = the mirror. Never render from a lane's own copy." % (lanes.STATUS_REL, base, mirror, root, base),
            ))
    return found


def main():
    payload = ft.read_payload()
    if not payload:
        return
    cwd = payload.get("cwd") or os.getcwd()
    if payload.get("session_id") and lanes.common_dir(cwd):
        lanes.touch(cwd, payload["session_id"])
    if payload.get("stop_hook_active"):
        return
    cfg = ft.config(cwd)
    msg = payload.get("last_assistant_message") or ""
    user_text, tools = ft.current_turn(payload.get("transcript_path") or "")

    found = []
    if ft.gate_on(cfg, "empty_reply"):
        found.append(check_empty(msg, user_text))
    if msg.strip():
        if ft.gate_on(cfg, "announce_stop"):
            found.append(check_announce(msg))
        if ft.gate_on(cfg, "prose_question"):
            found.append(check_prose_question(msg, tools))
        if ft.gate_on(cfg, "hand_back"):
            found.append(check_hand_back(msg))
        if ft.gate_on(cfg, "language"):
            found.append(check_language(msg, cfg, cwd))
        if ft.gate_on(cfg, "outbound"):
            found.append(check_outbound(msg, cfg))
        if ft.gate_on(cfg, "ui_proof"):
            found.append(check_ui_proof(msg, tools))
        if ft.gate_on(cfg, "freshness"):
            found.append(check_freshness(msg, cwd, payload.get("session_id") or "", cfg))
    if ft.gate_on(cfg, "status"):
        found.extend(check_status(msg, cwd, tools, cfg))
    found = [f for f in found if f]
    if not found:
        return
    for gate, excerpt, _ in found:
        ft.log(gate, payload, excerpt)
    reason = "follow-through:\n" + "\n".join("- " + text for _, _, text in found)
    print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


if __name__ == "__main__":
    ft.run(main)
