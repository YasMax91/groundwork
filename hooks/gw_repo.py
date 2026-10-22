"""Groundwork plugin :: where a tool call works, and where a session has worked (wave 40).

Every hook used to judge the session's own folder — `payload.cwd`, the directory in-cwd.sh entered. A session
opened in `ra-devs-laravel-back` (an empty folder, not a git repository) that worked in an otaje lane through
`cd <lane> && git push origin HEAD:development` pushed to the shared branch with nothing checked (2026-10-21,
E8): push-gate.py found no `.groundwork.json` in the session's folder and returned. The change touched
`bootstrap/app.php` and needed the whole suite, which was run by hand afterwards; no Stop gate ever saw the
lane, and the estimate ledger looked for the transcript under the lane's project and recorded nothing.

  commands(cmd, cwd)     the simple commands of a Bash line, in order, each with the directory it runs in:
                         `cd` / `pushd` / `popd`, `git -C`, `--git-dir` / `--work-tree`, `NAME=value` then
                         `$NAME`, subshells, `$(…)`, `bash -c` and `bash <<EOF`, `eval`, a git behind `sudo` /
                         `xargs` / `gtimeout`. A directory the line does not name — `cd "$LANE"` with LANE set
                         elsewhere — is None, never a guess; so is the one after a `cd` that may not have
                         happened (`cd A || cd B; …`, an `if` body), and a function's body until it is called.
  command_top / _root    the repository a command works in, and the directory a hook judges there
  call_targets(payload)  the same for a whole Bash / Edit / Write call, and whether each part changes anything
  remember / remembered  per session, the Groundwork repositories it changed outside its own folder
  hook_dirs(payload, m)  where in-cwd.sh runs a hook: the call's repository, or the session's folder plus every
                         remembered repository (Stop gates)

Fails soft like gw_tests.py: a line it cannot read yields fewer commands, never an exception in a hook.
"""

import json
import os
import re
import subprocess
import time

HOME = os.path.expanduser("~")
TOOLS = ("Bash", "Edit", "Write", "MultiEdit", "NotebookEdit")


# ------------------------------------------------------------------------------------------ lexing ---

META = frozenset(" \t\r\n;&|()<>")
REDIR = re.compile(r"(\d*)(<<<|<<-|<<|<>|<&|>&|>>|>\||<|>)")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class Word:
    """One shell word as parts: ("lit", text) · ("tilde", "") · ("var", name) · ("dyn", source text)."""

    __slots__ = ("parts", "raw")

    def __init__(self, parts, raw):
        self.parts, self.raw = parts, raw


def _skip_backtick(s, i):
    n = len(s)
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "`":
            return i + 1
        i += 1
    return n


def _skip_dquote(s, i):
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == '"':
            return i + 1
        if c == "$" and s[i + 1:i + 2] == "(":
            i = _skip_parens(s, i + 1)
            continue
        if c == "`":
            i = _skip_backtick(s, i + 1)
            continue
        i += 1
    return n


def _skip_parens(s, i):
    """s[i] is "(": the index after its matching ")". A here-document inside is skipped whole — the commit
    template `git commit -m "$(cat <<'EOF' … don't … EOF)"` carries quotes no parser should pair up."""
    depth, n, pending = 0, len(s), []
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "\n" and pending:
            i += 1
            for strip, delim in pending:
                i, _ = _body(s, i, strip, delim)
            pending = []
            continue
        if s.startswith("<<", i) and not s.startswith("<<<", i):
            strip = s.startswith("<<-", i)
            j = i + (3 if strip else 2)
            while j < n and s[j] in " \t":
                j += 1
            j, w = _read_word(s, j)
            delim = _literal(w)
            pending.append((strip, w.raw if delim is None else delim))
            i = j
            continue
        if c == "'":
            j = s.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            i = _skip_dquote(s, i + 1)
            continue
        if c == "`":
            i = _skip_backtick(s, i + 1)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def _read_dollar(s, i, buf, parts):
    n, nxt = len(s), s[i + 1:i + 2]

    def flush():
        if buf:
            parts.append(("lit", "".join(buf)))
            del buf[:]

    if nxt == "(":
        j = _skip_parens(s, i + 1)
        flush()
        parts.append(("dyn", s[i:j]))
        return j
    if nxt == "{":
        j = s.find("}", i + 2)
        j = n - 1 if j < 0 else j
        inner = s[i + 2:j]
        flush()
        parts.append(("var", inner) if NAME.fullmatch(inner) else ("dyn", s[i:j + 1]))
        return j + 1
    if nxt == "'":                                      # $'…': ANSI-C quoting, taken literally
        j, out = i + 2, []
        while j < n and s[j] != "'":
            if s[j] == "\\" and j + 1 < n:
                out.append({"n": "\n", "t": "\t"}.get(s[j + 1], s[j + 1]))
                j += 2
                continue
            out.append(s[j])
            j += 1
        buf.append("".join(out))
        return j + 1
    if nxt == '"':                                      # $"…" is "…"
        return i + 1
    m = NAME.match(s, i + 1)
    if m:
        flush()
        parts.append(("var", m.group(0)))
        return m.end()
    if nxt and (nxt.isdigit() or nxt in "@*#?$!-"):
        flush()
        parts.append(("dyn", s[i:i + 2]))
        return i + 2
    buf.append("$")
    return i + 1


def _read_word(s, i):
    start, n, parts, buf = i, len(s), [], []

    def flush():
        if buf:
            parts.append(("lit", "".join(buf)))
            del buf[:]

    while i < n:
        c = s[i]
        if c in META:
            break
        if c == "\\":
            if s[i + 1:i + 2] == "\n":
                i += 2
                continue
            buf.append(s[i + 1:i + 2])
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            j = n if j < 0 else j
            buf.append(s[i + 1:j])
            i = j + 1
            continue
        if c == '"':
            i += 1
            while i < n and s[i] != '"':
                d = s[i]
                if d == "\\" and i + 1 < n and s[i + 1] in '"\\$`\n':
                    if s[i + 1] != "\n":
                        buf.append(s[i + 1])
                    i += 2
                    continue
                if d == "$":
                    i = _read_dollar(s, i, buf, parts)
                    continue
                if d == "`":
                    j = _skip_backtick(s, i + 1)
                    flush()
                    parts.append(("dyn", s[i:j]))
                    i = j
                    continue
                buf.append(d)
                i += 1
            i += 1
            continue
        if c == "$":
            i = _read_dollar(s, i, buf, parts)
            continue
        if c == "`":
            j = _skip_backtick(s, i + 1)
            flush()
            parts.append(("dyn", s[i:j]))
            i = j
            continue
        if c == "~" and i == start:
            if i + 1 >= n or s[i + 1] == "/" or s[i + 1] in META:
                parts.append(("tilde", ""))
                i += 1
                continue
            j = i + 1
            while j < n and s[j] not in META and s[j] != "/":
                j += 1
            parts.append(("dyn", s[i:j]))                   # ~user
            i = j
            continue
        buf.append(c)
        i += 1
    flush()
    return i, Word(parts, s[start:i])


def _literal(w):
    return "".join(t for k, t in w.parts) if all(k == "lit" for k, _ in w.parts) else None


def _body(s, i, strip, delim):
    """A here-document's body from s[i] on: (the index after its delimiter line, the body)."""
    body, n = [], len(s)
    while i < n:
        j = s.find("\n", i)
        line = s[i:] if j < 0 else s[i:j]
        i = n if j < 0 else j + 1
        if (line.lstrip("\t") if strip else line) == delim:
            break
        body.append(line)
    return i, "\n".join(body)


def _heredoc(s, i, tok):
    """Read a here-document's body into tok[3]; the index after its delimiter line."""
    delim = _literal(tok[2])
    i, tok[3] = _body(s, i, tok[1] == "<<-", tok[2].raw if delim is None else delim)
    return i


def lex(s):
    """Tokens: ("w", Word) · ("op", text) · ["redir", op, Word, here-document body or None].

    Comments are dropped and here-document bodies kept off the command stream: a commit message saying
    `git push origin development` is not a push.
    """
    toks, i, n, pending = [], 0, len(s), []
    while i < n:
        c = s[i]
        if c == "\\" and s[i + 1:i + 2] == "\n":
            i += 2
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "\n":
            toks.append(("op", "\n"))
            i += 1
            for tok in pending:
                i = _heredoc(s, i, tok)
            pending = []
            continue
        if c == "#":
            j = s.find("\n", i)
            i = n if j < 0 else j
            continue
        if s.startswith("((", i):                       # arithmetic: `1 << 2` in it is no here-document
            j = _skip_parens(s, i)
            toks.append(("w", Word([("dyn", s[i:j])], s[i:j])))
            i = j
            continue
        two = s[i:i + 2]
        if two in ("&&", "||", ";;", "|&"):
            toks.append(("op", two))
            i += 2
            continue
        if two == "&>":
            op = "&>>" if s[i:i + 3] == "&>>" else "&>"
            i += len(op)
            while i < n and s[i] in " \t":
                i += 1
            i, w = _read_word(s, i)
            toks.append(["redir", op, w, None])
            continue
        if c in ";|&()":
            toks.append(("op", c))
            i += 1
            continue
        m = REDIR.match(s, i)
        if m:
            op, i = m.group(2), m.end()
            while i < n and s[i] in " \t":
                i += 1
            i, w = _read_word(s, i)
            tok = ["redir", op, w, None]
            toks.append(tok)
            if op in ("<<", "<<-"):
                pending.append(tok)
            continue
        i, w = _read_word(s, i)
        toks.append(("w", w))
    return toks


# ----------------------------------------------------------------------------------------- parsing ---

OPEN, CLOSE = object(), object()


class Command:
    """One simple command. After commands(): argv (expanded words, None where a word cannot be read),
    dir (where it runs, None when the line does not say), why (the step that lost the directory),
    git (for a git call: dir after -C, git_dir, work_tree, sub, args), outputs (files it redirects into)."""

    __slots__ = ("words", "assigns", "redirs", "prev_op", "next_op", "argv", "dir", "why", "git", "outputs")

    def __init__(self):
        self.words, self.assigns, self.redirs = [], [], []
        self.prev_op = self.next_op = None
        self.argv, self.dir, self.why, self.git, self.outputs = [], None, "", None, []

    @property
    def text(self):
        return " ".join([w.raw for _, w in self.assigns] + [w.raw for w in self.words])


def _assignment(w):
    if not w.parts or w.parts[0][0] != "lit":
        return None
    m = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\+?=", w.parts[0][1])
    if not m:
        return None
    rest = w.parts[0][1][m.end():]
    return m.group(1), Word(([("lit", rest)] if rest else []) + w.parts[1:], w.raw)


def _parse(toks):
    items, state = [], {"cur": None, "prev": None}

    def finish(op):
        cur = state["cur"]
        if cur is not None and (cur.words or cur.assigns or cur.redirs):
            cur.prev_op, cur.next_op = state["prev"], op
            items.append(cur)
        state["cur"], state["prev"] = None, op

    for t in toks:
        if t[0] == "w":
            if state["cur"] is None:
                state["cur"] = Command()
            a = None if state["cur"].words else _assignment(t[1])
            if a:
                state["cur"].assigns.append(a)
            else:
                state["cur"].words.append(t[1])
        elif t[0] == "redir":
            if state["cur"] is None:
                state["cur"] = Command()
            state["cur"].redirs.append((t[1], t[2], t[3]))
        elif t[1] == "(":
            finish(None)
            items.append(OPEN)
        elif t[1] == ")":
            finish(None)
            items.append(CLOSE)
        else:
            finish(t[1])
    finish(None)
    return items


# ------------------------------------------------------------------------------------------- walking ---

SHELLS = ("bash", "sh", "zsh", "dash", "ksh")
KEYWORDS = ("then", "else", "elif", "do", "if", "while", "until", "!", "{", "}", "fi", "done", "esac")
SAFE_ENV = ("HOME", "USER", "LOGNAME")
# Commands that run another one somewhere else: a `git` among their words is not this machine's git here.
REMOTE = ("ssh", "docker", "podman", "kubectl", "sail")


class _State:
    """Where the line is: `cur` (None when unknown), and whether the last `cd` surely happened — one that ran
    on a condition, or into a folder that does not exist yet, holds only for the commands `&&` chains after it."""

    __slots__ = ("cur", "old", "stack", "vars", "exported", "why", "tentative", "pending", "conds", "fn",
                 "fn_next", "case", "case_cd")

    def __init__(self, cur):
        self.cur, self.old, self.stack, self.vars, self.exported, self.why = cur, None, [], {}, set(), ""
        self.tentative, self.pending, self.conds = False, "", []
        self.fn, self.fn_next, self.case, self.case_cd = 0, False, 0, False

    def snapshot(self):
        return tuple(list(v) if isinstance(v, list) else dict(v) if isinstance(v, dict) else
                     set(v) if isinstance(v, set) else v for v in (getattr(self, k) for k in self.__slots__))

    def restore(self, snap):
        for k, v in zip(self.__slots__, snap):
            setattr(self, k, list(v) if isinstance(v, list) else dict(v) if isinstance(v, dict) else
                    set(v) if isinstance(v, set) else v)


def _substitution(text, st):
    """The value of a read-only substitution the hook can compute itself — `$(pwd)`, `$(git rev-parse
    --show-toplevel)`, `$(git branch --show-current)` — or None."""
    if text.startswith("$(") and text.endswith(")"):
        inner = text[2:-1]
    elif text.startswith("`") and text.endswith("`") and len(text) > 1:
        inner = text[1:-1]
    else:
        return None
    inner = " ".join(inner.split())
    if not st.cur:
        return None
    if inner == "pwd":
        return st.cur
    if inner == "git rev-parse --show-toplevel":
        return toplevel(st.cur) or None
    if inner in ("git branch --show-current", "git rev-parse --abbrev-ref HEAD", "git symbolic-ref --short HEAD"):
        return _git(["branch", "--show-current"], st.cur) or None
    return None


def _expand(w, st):
    out = []
    for kind, text in w.parts:
        if kind == "lit":
            out.append(text)
        elif kind == "tilde":
            out.append(HOME)
        elif kind == "var":
            if text in st.vars:
                if st.vars[text] is None:
                    return None
                out.append(st.vars[text])
            elif text == "PWD" and st.cur:
                out.append(st.cur)
            elif text == "OLDPWD" and st.old:
                out.append(st.old)
            elif text in SAFE_ENV and os.environ.get(text):
                out.append(os.environ[text])
            else:
                return None
        else:
            v = _substitution(text, st)
            if v is None:
                return None
            out.append(v)
    return "".join(out)


def _unwrap(argv, env):
    """The command behind `env`, `command`, `builtin`, `exec`, `nohup`, `noglob`, `time`, `nice`, `timeout`."""
    for _ in range(8):
        if not argv or argv[0] is None:
            return argv
        name = os.path.basename(argv[0])
        if name in ("command", "builtin", "exec", "nohup", "noglob", "time"):
            argv = argv[1:]
            while argv and argv[0] and argv[0].startswith("-") and argv[0] != "--":
                argv = argv[1:]
            if argv and argv[0] == "--":
                argv = argv[1:]
        elif name == "env":
            argv = argv[1:]
            while argv and argv[0] is not None:
                a = argv[0]
                if a in ("-C", "--chdir"):                  # GNU env runs the command in another folder
                    env["\0chdir"] = argv[1] if len(argv) > 1 else None
                    argv = argv[2:]
                elif a.startswith("--chdir="):
                    env["\0chdir"] = a[len("--chdir="):]
                    argv = argv[1:]
                elif a in ("-u", "--unset", "-S", "--split-string"):
                    argv = argv[2:]
                elif a.startswith("-"):
                    argv = argv[1:]
                elif re.match(r"[A-Za-z_][A-Za-z0-9_]*=", a):
                    k, _, v = a.partition("=")
                    env[k] = v
                    argv = argv[1:]
                else:
                    break
        elif name == "nice":
            argv = argv[1:]
            if argv and argv[0] == "-n":
                argv = argv[2:]
            elif argv and argv[0] and re.fullmatch(r"-\d+", argv[0]):
                argv = argv[1:]
        elif name in ("timeout", "gtimeout"):
            argv = argv[1:]
            while argv and argv[0] and argv[0].startswith("-"):
                argv = argv[2:] if argv[0] in ("-s", "-k", "--signal", "--kill-after") else argv[1:]
            argv = argv[1:]
        else:
            return argv
    return argv


def _chdir(st, name, argv, text, conditional):
    """Apply cd / pushd / popd. A target the line does not name leaves the directory unknown. A `cd` that may not
    happen — it runs on a condition, or its folder does not exist yet — holds only for what `&&` chains after it:
    `cd $W || cd $E; git push` pushes from W or from E, and the line does not say which."""
    args = [a for a in argv[1:] if not (a and (a == "--" or re.fullmatch(r"-[A-Za-z@]+", a)))]
    if name == "popd":
        new = st.stack.pop() if st.stack else None
    elif not args:
        new = HOME if name == "cd" else None
    elif args[0] is None:
        new = None
    elif args[0] == "-":
        new = st.old
    elif os.path.isabs(args[0]):
        new = args[0]
    else:
        new = os.path.join(st.cur, args[0]) if st.cur else None
    if new is not None:
        new = os.path.normpath(new)
        if not os.path.isdir(new):                      # it fails unless the line creates the folder first
            conditional = True
    if name == "pushd" and st.cur is not None:
        st.stack.append(st.cur)
    lost_before = st.cur is None and st.why
    st.old, st.cur = st.cur, new
    if new is None:
        st.tentative = False
        st.why = st.why if lost_before else "after `%s`" % text     # the first step that lost the directory
    elif conditional:
        st.tentative, st.pending = True, "after `%s`, which may not have run" % text
    else:
        st.tentative, st.why = False, ""


GIT_VALUE = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--super-prefix")


def _git_call(argv, cur, env, text=""):
    d, why = cur, ""
    gd, wt = env.get("GIT_DIR", ""), env.get("GIT_WORK_TREE", "")
    i = 1
    while i < len(argv):
        a = argv[i]
        if a is None:
            return {"dir": None, "why": "in `%s`" % text, "git_dir": "", "work_tree": "", "sub": "", "args": []}
        if a in GIT_VALUE:
            v = argv[i + 1] if i + 1 < len(argv) else None
            if a == "-C":
                if v is None or (d is None and not os.path.isabs(v)):
                    d, why = None, "in `%s`" % text
                else:
                    d = os.path.normpath(v if os.path.isabs(v) else os.path.join(d, v))
            elif a == "--git-dir":
                gd = v
            elif a == "--work-tree":
                wt = v
            i += 2
            continue
        if a.startswith("--git-dir="):
            gd = a[len("--git-dir="):]
        elif a.startswith("--work-tree="):
            wt = a[len("--work-tree="):]
        elif not a.startswith("-"):
            break
        i += 1

    def absolute(p):
        if p is None or p == "" or os.path.isabs(p):
            return p
        return os.path.normpath(os.path.join(d, p)) if d else None

    return {"dir": d, "why": why, "git_dir": absolute(gd), "work_tree": absolute(wt),
            "sub": argv[i] if i < len(argv) else "", "args": argv[i + 1:]}


def _substitutions(c, st, cur, out, depth):
    """A command substitution runs first, in a subshell of this directory: `out=$(git push … 2>&1)` pushes."""
    for w in [w for _, w in c.assigns] + c.words + [w for _, w, _ in c.redirs]:
        for kind, text in w.parts:
            inner = None
            if kind == "dyn" and text.startswith("$(") and not text.startswith("$(("):
                inner = text[2:-1] if text.endswith(")") else text[2:]
            elif kind == "dyn" and text.startswith("`"):
                inner = text[1:-1] if text.endswith("`") and len(text) > 1 else text[1:]
            if inner:
                child = _State(cur)
                child.vars, child.exported = dict(st.vars), set(st.exported)
                _walk(_parse(lex(inner)), child, out, depth + 1)


def _walk(items, st, out, depth):
    saved, i = [], 0
    while i < len(items):
        it = items[i]
        i += 1
        if it is OPEN or it is CLOSE:
            if st.case:                                 # `pattern)` inside a case: no subshell
                continue
            if it is OPEN:
                saved.append(st.snapshot())
            elif saved:
                st.restore(saved.pop())
            continue
        c = it
        # `name () { …; }`, `function name { …; }`: a definition — its body runs where the function is called.
        head = [_literal(w) for w in c.words]
        if head[:1] == ["function"] and len(head) >= 2:
            st.fn_next = True
            if items[i:i + 2] == [OPEN, CLOSE]:
                i += 2
            if len(c.words) == 2:
                continue
            c.words = c.words[2:]
        elif len(head) == 1 and head[0] and NAME.fullmatch(head[0]) and c.next_op is None \
                and items[i:i + 2] == [OPEN, CLOSE]:
            i += 2
            st.fn_next = True
            continue
        prev, words, opened = c.prev_op, list(c.words), False
        while words and _literal(words[0]) in KEYWORDS:
            k = _literal(words[0])
            words = words[1:]
            if k in ("if", "while", "until"):
                st.conds.append((st.cur, False))
            elif k in ("then", "do"):
                prev = None                             # a body starts a sequence of its own
            elif k in ("else", "elif"):
                prev = None                             # …from where the `if` started: its `then` did not run
                if st.conds:
                    st.cur, st.tentative = st.conds[-1][0], False
            elif k in ("fi", "done") and st.conds:
                # The body may not have run: a `cd` anywhere in it leaves the folder after it unknown.
                if st.conds.pop()[1]:
                    st.cur, st.tentative, st.why = None, False, "after a `cd` inside an `if` or a loop"
            elif k == "esac" and st.case:
                st.case -= 1
                if not st.case and st.case_cd:
                    st.cur, st.tentative, st.why, st.case_cd = None, False, "after a `cd` inside a `case`", False
            elif k == "{":
                if st.fn_next:
                    st.fn, st.fn_next, opened = 1, False, True
                elif st.fn:
                    st.fn += 1
            elif k == "}" and st.fn:
                st.fn -= 1
        if st.fn_next and not opened and words:
            st.fn_next = False                          # `f() ( … )` and the like: no braces to follow
        # A `cd` that may not have happened leaves only the commands `&&` chains after it in its folder.
        if st.tentative and prev not in ("&&", "|", "|&"):
            st.cur, st.why, st.tentative = None, st.pending, False
        first = _literal(words[0]) if words else None
        if first in ("for", "select"):
            st.conds.append((st.cur, False))
            continue                                    # a loop's header; its body follows
        if first == "case":
            st.case += 1
            continue
        # A pipeline's parts and a `&` job run in subshells; a function's body runs where it is called, a
        # case's arm only when it matches: a `cd` in any of them moves nothing after it here.
        hidden = st.fn > 0 or st.case > 0
        local = hidden or c.prev_op in ("|", "|&") or c.next_op in ("|", "|&", "&")
        cur = None if hidden else st.cur
        why = ("inside a function's body, which runs where it is called" if st.fn
               else "inside a `case`" if st.case else st.why)
        if depth < 4:
            _substitutions(c, st, cur, out, depth)
        env = {name: _expand(w, st) for name, w in c.assigns}
        c.dir, c.why = cur, why
        c.outputs = [None if w is None else _expand(w, st) for op, w, _ in c.redirs
                     if op in (">", ">>", ">|", "&>", "&>>", "<>")]
        if not words:
            if not local:
                st.vars.update(env)
            if c.redirs:
                out.append(c)
            continue
        argv = _unwrap([_expand(w, st) for w in words], env)
        c.argv = argv
        if "\0chdir" in env:                            # env -C <dir> <command>
            d = env.pop("\0chdir")
            c.dir = os.path.normpath(os.path.join(cur, d)) if (d is not None and (cur or os.path.isabs(d))) else None
            c.why = "in `%s`" % c.text if c.dir is None else c.why
        name = os.path.basename(argv[0]) if argv and argv[0] else None
        if name in ("cd", "pushd", "popd"):
            if st.case:
                st.case_cd = True
            if not local:
                _chdir(st, name, argv, c.text, prev in ("&&", "||"))
                st.conds = [(start, True) for start, _ in st.conds]
        elif name in ("export", "declare", "local", "readonly", "typeset"):
            if not local:
                for w in words[1:]:
                    k = w.raw.split("=", 1)[0]
                    if not NAME.fullmatch(k):
                        continue
                    if "=" in w.raw:
                        a = _expand(w, st)
                        st.vars[k] = a.split("=", 1)[1] if a is not None and "=" in a else None
                    if name == "export":
                        st.exported.add(k)
        elif name == "eval" and depth < 4 and all(a is not None for a in argv[1:]):
            _walk(_parse(lex(" ".join(argv[1:]))), st, out, depth + 1)
        elif name in SHELLS and depth < 4:
            script, heredoc = None, True
            for k, a in enumerate(argv[1:], 1):
                if a is not None and re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", a):
                    script, heredoc = (argv[k + 1] if k + 1 < len(argv) else None), False
                    break
                if a is None or not a.startswith("-"):
                    heredoc = False                     # a script file: nothing on this line to read
                    break
            if heredoc:
                script = "\n".join(body for op, _, body in c.redirs if op in ("<<", "<<-") and body)
            if script:
                _walk(_parse(lex(script)), _State(c.dir), out, depth + 1)   # a child shell: moves nothing here
        elif name and name not in READERS and name not in REMOTE:
            # `git`, or a git that another command runs here: sudo, gtimeout, stdbuf, caffeinate, script, xargs…
            g = 0 if name == "git" else next((k for k in range(1, len(argv))
                                              if argv[k] and os.path.basename(argv[k]) == "git"), None)
            if g is not None:
                genv = dict((k, st.vars.get(k)) for k in ("GIT_DIR", "GIT_WORK_TREE") if k in st.exported)
                genv.update((k, v) for k, v in env.items() if k in ("GIT_DIR", "GIT_WORK_TREE"))
                c.git = _git_call(argv[g:] + ([None] if name == "xargs" else []), c.dir, genv, c.text)
                c.dir = c.git["dir"]
                c.why = c.git["why"] or c.why
        out.append(c)


def commands(cmd, cwd):
    """Every simple command of a Bash line, in the order it runs, with the directory it runs in."""
    out = []
    try:
        _walk(_parse(lex(cmd or "")), _State(os.path.abspath(cwd) if cwd else None), out, 0)
    except Exception:
        pass
    return out


# ------------------------------------------------------------------------------------- repositories ---

_TOPS = {}


def _git(args, cwd):
    try:
        r = subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _existing(path):
    d = path
    while d and not os.path.isdir(d):
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent
    return d


def toplevel(path):
    """The root of the repository a directory or a file belongs to; '' outside one."""
    d = _existing(path or "")
    if not d:
        return ""
    if d not in _TOPS:
        _TOPS[d] = _git(["rev-parse", "--show-toplevel"], d)
    return _TOPS[d]


def is_groundwork(d):
    return bool(d) and os.path.isfile(os.path.join(d, ".groundwork.json"))


def project_root(path):
    """The directory a hook judges for `path`: the nearest one up to the repository's root that carries
    `.groundwork.json` (a project in a subfolder of its repository), else the root; '' outside a repository."""
    top = toplevel(path)
    if not top:
        return ""
    rt, d = os.path.realpath(top), os.path.realpath(_existing(path))
    while d.startswith(rt + os.sep):
        if is_groundwork(d):
            return d
        d = os.path.dirname(d)
    return top


def command_top(c):
    """(repository root, known) for a command: '' outside a repository; known is False when the line does not
    say where it runs, or its --git-dir / --work-tree name another repository than the one they sit in."""
    if c.dir is None:
        return "", False
    g = c.git
    if g and (g["git_dir"] is None or g["work_tree"] is None):
        return "", False
    if g and (g["git_dir"] or g["work_tree"]):
        flags = (["--git-dir=" + g["git_dir"]] if g["git_dir"] else []) + \
                (["--work-tree=" + g["work_tree"]] if g["work_tree"] else [])
        top = _git(flags + ["rev-parse", "--show-toplevel"], c.dir)
        if not top:
            return "", True                             # a bare repository: no working tree to judge
        a = _git(flags + ["rev-parse", "--absolute-git-dir"], c.dir)
        b = _git(["rev-parse", "--absolute-git-dir"], top)
        if not a or os.path.realpath(a) != os.path.realpath(b):
            return "", False
        return top, True
    return toplevel(c.dir), True


def command_root(c):
    top, known = command_top(c)
    if not top:
        return "", known
    g = c.git
    return (project_root(c.dir) if not (g and (g["git_dir"] or g["work_tree"])) else top), True


# What changes nothing. Anything else — a script, an artisan call, a test run, an unknown tool — is work.
READERS = frozenset("""
cat less more head tail grep egrep fgrep rg ag ack ls tree wc file stat du df pwd echo printf which type whereis
test [ [[ true false : diff cmp comm sort uniq cut tr column nl od xxd hexdump strings jq yq basename dirname
realpath readlink date printenv id whoami uname hostname sleep cd pushd popd md5 md5sum shasum sha1sum sha256sum
zcat bat fd find sed awk export unset set declare local readonly typeset alias shopt
""".split())
GIT_READERS = frozenset("""
status log show diff rev-parse rev-list ls-files ls-tree ls-remote cat-file grep blame describe shortlog
for-each-ref merge-base name-rev whatchanged count-objects check-ignore check-attr var help version fetch
show-ref show-branch cherry range-diff annotate verify-commit verify-tag
""".split())
GIT_LISTS = {"stash": ("list", "show"), "worktree": ("list",), "remote": ("", "show", "get-url"),
             "notes": ("", "list", "show"), "reflog": ("", "show"), "submodule": ("", "status", "summary")}


def writes(c):
    """False only for a command known to change nothing."""
    if any(o not in ("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty") for o in c.outputs):
        return True
    argv = c.argv
    if not argv or argv[0] is None:
        return bool(c.outputs)
    name, args = os.path.basename(argv[0]), [a or "" for a in argv[1:]]
    if name == "git" and c.git:
        sub, ga = c.git["sub"] or "", [a or "" for a in c.git["args"]]
        pos = [a for a in ga if not a.startswith("-")]
        if sub in GIT_READERS:
            return any(a.startswith("--output") for a in ga)
        if sub == "branch":
            change = ("-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy", "-u", "--unset-upstream",
                      "-f", "--force", "--edit-description", "-t", "--track")
            listing = ("--list", "-l", "--contains", "--no-contains", "--merged", "--no-merged", "--points-at")
            return any(a in change or a.startswith("--set-upstream-to") for a in ga) or \
                (bool(pos) and not any(a.split("=")[0] in listing for a in ga))
        if sub == "tag":
            return any(a in ("-d", "--delete", "-a", "-s", "-f", "-m") for a in ga) or \
                (bool(pos) and not any(a.split("=")[0] in ("-l", "--list", "-v", "--verify", "--contains",
                                                           "--points-at", "--merged", "--no-merged") for a in ga))
        if sub in GIT_LISTS:
            return (pos[0] if pos else "") not in GIT_LISTS[sub]
        if sub == "config":
            return len(pos) > 1 and not any(a in ("--get", "--get-all", "--get-regexp", "--list", "-l") for a in ga)
        return True
    if name not in READERS:
        return True
    if name == "sed":
        return any(re.match(r"-[A-Za-z]*i", a) or a.startswith("--in-place") for a in args)
    if name == "find":
        return any(a in ("-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls")
                   for a in args)
    if name == "sort":
        return any(a == "-o" or a.startswith("--output") for a in args)
    if name == "yq":
        return any(re.match(r"-[A-Za-z]*i", a) or a.startswith("--inplace") for a in args)
    return False


def call_targets(payload):
    """[(root, writes, known)] for a Bash / Edit / Write call: the directory a hook judges for each part of it."""
    tool = payload.get("tool_name")
    inp = payload.get("tool_input") or {}
    if tool == "Bash":
        out = []
        for c in commands(str(inp.get("command") or ""), payload.get("cwd") or os.getcwd()):
            root, known = command_root(c)
            out.append((root, writes(c), known))
        return out
    if tool in TOOLS:
        path = str(inp.get("file_path") or inp.get("notebook_path") or "")
        if path and not os.path.isabs(path):
            path = os.path.join(payload.get("cwd") or os.getcwd(), path)
        return [(project_root(path), True, True)] if path else []
    return []


# ----------------------------------------------------------------------------------- the registry ---
#
# `~/.claude/groundwork/sessions/<session id>.jsonl`, one line per Groundwork repository the session changed
# outside its own folder: {"repo", "transcript", "cwd", "time"}. Written before the call runs (PreToolUse), so a
# Stop gate and the estimate ledger know the repository the moment the session first touches it.

def sessions_dir():
    return os.environ.get("GW_SESSIONS_DIR") or os.path.join(HOME, ".claude", "groundwork", "sessions")


def _registry(sid):
    sid = str(sid or "")
    return os.path.join(sessions_dir(), sid + ".jsonl") if re.fullmatch(r"[A-Za-z0-9._-]{1,128}", sid) else ""


def _entries(path):
    out = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                except Exception:
                    continue
                if isinstance(e, dict) and e.get("repo"):
                    out.append(e)
    except Exception:
        pass
    return out


def remembered(sid):
    f = _registry(sid)
    seen = []
    for e in (_entries(f) if f else []):
        if e["repo"] not in seen:
            seen.append(e["repo"])
    return seen


def remember(payload):
    """Record the Groundwork repositories this call changes outside the session's own folder; the new ones."""
    f = _registry(payload.get("session_id"))
    if not f:
        return []
    cwd = payload.get("cwd") or os.getcwd()
    home = os.path.realpath(project_root(cwd) or cwd)
    found = []
    for root, changes, known in call_targets(payload):
        if known and changes and is_groundwork(root) and os.path.realpath(root) != home and root not in found:
            found.append(root)
    have = remembered(payload.get("session_id"))
    new = [r for r in found if r not in have]
    if not new:
        return []
    now = int(time.time())
    try:
        os.makedirs(os.path.dirname(f), exist_ok=True)
        first = not os.path.exists(f)
        with open(f, "a", encoding="utf-8") as fh:
            for r in new:
                fh.write(json.dumps({"repo": r, "transcript": payload.get("transcript_path") or "", "cwd": cwd,
                                     "time": now}) + "\n")
        if first:                                       # a new session: drop the registries of month-old ones
            for n in os.listdir(os.path.dirname(f)):
                p = os.path.join(os.path.dirname(f), n)
                if n.endswith(".jsonl") and now - os.path.getmtime(p) > 30 * 86400:
                    os.unlink(p)
    except Exception:
        return []
    return new


def project_key(path):
    """The estimate ledger's project key (estimate-ledger.sh gw_project_key): worktrees fold into the parent."""
    return re.sub(r"--claude-worktrees-.*$", "", re.sub(r"[/._]", "-", path))


def transcripts_for(path):
    """Transcripts of the sessions that worked in this project — any of its worktrees — from outside it."""
    key, out = project_key(os.path.realpath(path)), []
    try:
        names = sorted(os.listdir(sessions_dir()))
    except Exception:
        return out
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        for e in _entries(os.path.join(sessions_dir(), n)):
            t = e.get("transcript") or ""
            if t and t not in out and project_key(os.path.realpath(e["repo"])) == key and os.path.isfile(t):
                out.append(t)
    return out


# --------------------------------------------------------------------------------- where hooks run ---

def live_elsewhere(root, sid):
    """Another live Claude session has `root` as its folder now: a `claude` process working there, or a fresh
    entry in follow-through's session registry (lane-idle.py reads the same two)."""
    here = os.path.realpath(root)
    try:
        out = subprocess.run(["lsof", "-a", "-d", "cwd", "-c", "claude", "-Fn"], capture_output=True, text=True,
                             timeout=10).stdout
        if any(l.startswith("n") and os.path.realpath(l[1:]) == here for l in out.splitlines()):
            return True
    except Exception:
        pass
    common = _git(["rev-parse", "--path-format=absolute", "--git-common-dir"], root)
    d = os.path.join(common, "follow-through", "sessions") if common else ""
    try:
        for n in os.listdir(d):
            e = _read_json(os.path.join(d, n))
            if e.get("session_id") != sid and e.get("cwd") == here and time.time() - float(e.get("heartbeat", 0)) < 1800:
                return True
    except Exception:
        pass
    return False


def _read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            v = json.load(fh)
        return v if isinstance(v, dict) else {}
    except Exception:
        return {}


def hook_dirs(payload, mode):
    """Directories in-cwd.sh runs a hook in, one per item; [] when the payload names no usable folder (it then
    falls back). An item "<dir>\\t<note>" is a repository whose verdict is shown but does not block.

    tool   a Bash / Edit / Write call: the first Groundwork project it works in — a command that changes
           something first, a `cd` never (it runs before the move) — else the first repository, else the
           session's folder; any other event: the session's folder (its project's root)
    each   the session's folder, then every Groundwork repository the session changed outside it; one that
           another live session works in now is judged without blocking — those changes may be that session's
    first  the session's folder when it is a Groundwork project, else the first remembered one
    """
    cwd = payload.get("cwd") or ""
    if not cwd or not os.path.isdir(cwd):
        return []
    home = project_root(cwd) or cwd
    if mode == "tool":
        order = []
        tool, inp = payload.get("tool_name"), payload.get("tool_input") or {}
        if tool == "Bash":
            found = []
            for c in commands(str(inp.get("command") or ""), cwd):
                if c.argv and c.argv[0] and os.path.basename(c.argv[0]) in ("cd", "pushd", "popd"):
                    continue
                root, known = command_root(c)
                if known and root:
                    found.append((root, writes(c)))
            order = [r for r, w in found if w] + [r for r, w in found if not w]
        elif tool in TOOLS:
            order = [r for r, _, known in call_targets(payload) if known and r]
        projects = [r for r in order if is_groundwork(r)]
        return [(projects or order or [home])[0]]
    sid = payload.get("session_id")
    rem = [r for r in remembered(sid) if is_groundwork(r) and os.path.realpath(r) != os.path.realpath(home)]
    if mode == "each":
        return [home] + [r + ("\tanother live session works there now" if live_elsewhere(r, sid) else "") for r in rem]
    if mode == "first":
        return [home] if (is_groundwork(home) or not rem) else rem[:1]
    return [home]
