"""Safe Lua tokenizer and hypr.windaase loader stripper for uninstall."""

import re
import shutil
import subprocess

from .common import atomic_write

_LUA_KEYWORDS = frozenset({
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
})
_LUA_BINARY_KW = frozenset({"and", "or"})
_LUA_EXPR_PREFIX_KW = frozenset({
    "local", "return", "if", "elseif", "while", "until", "and", "or", "not", "in",
})
_LUA_EXPR_PREFIX_PUNCT = frozenset({
    "=", ",", "(", "{", "[", ".", ":", "+", "-", "*", "/", "%", "^", "#",
})
_LUA_EXPR_SUFFIX_PUNCT = frozenset({".", ":", "[", "(", ",", ")", "}", "]"})
_LUA_DELIM_PAIRS = {"(": ")", "{": "}", "[": "]"}
_LUA_CLOSERS = frozenset(_LUA_DELIM_PAIRS.values())


def _match_lua_long_bracket(text, pos):
    if pos >= len(text) or text[pos] != "[":
        return None
    n = len(text)
    j = pos + 1
    while j < n and text[j] == "=":
        j += 1
    if j >= n or text[j] != "[":
        return None
    eq = j - pos - 1
    closer = "]" + ("=" * eq) + "]"
    end = text.find(closer, j + 1)
    if end == -1:
        raise ValueError("Unterminated Lua long string or comment")
    return eq, end + len(closer)


def tokenize_lua(text):
    """Tokenize Lua source so strings and comments are isolated from delimiters."""
    tokens = []
    n = len(text)
    i = 0
    while i < n:
        ch = text[i]
        if ch in " \t\r\n\f\v":
            j = i + 1
            while j < n and text[j] in " \t\r\n\f\v":
                j += 1
            tokens.append(("ws", text[i:j], i, j))
            i = j
        elif text.startswith("--", i):
            lb = _match_lua_long_bracket(text, i + 2)
            if lb is not None:
                _, j = lb
            else:
                j = text.find("\n", i + 2)
                if j == -1:
                    j = n
            tokens.append(("comment", text[i:j], i, j))
            i = j
        elif ch == "[" and (lb := _match_lua_long_bracket(text, i)) is not None:
            _, j = lb
            tokens.append(("string", text[i:j], i, j))
            i = j
        elif ch in ('"', "'"):
            quote = ch
            j = i + 1
            closed = False
            while j < n:
                c = text[j]
                if c == "\\":
                    if text[j:j + 3] == "\\\r\n":
                        j += 3
                    else:
                        j += 2
                    continue
                if c == quote:
                    j += 1
                    closed = True
                    break
                if c in ("\n", "\r"):
                    raise ValueError("Unterminated Lua string")
                j += 1
            if not closed:
                raise ValueError("Unterminated Lua string")
            tokens.append(("string", text[i:j], i, j))
            i = j
        elif ch.isalpha() or ch == "_":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            tokens.append(("ident", text[i:j], i, j))
            i = j
        elif ch.isdigit() or (ch == "." and i + 1 < n and text[i + 1].isdigit()):
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] in "_."):
                j += 1
            tokens.append(("number", text[i:j], i, j))
            i = j
        elif text[i:i + 3] == "...":
            tokens.append(("other", "...", i, i + 3))
            i += 3
        elif text[i:i + 2] in ("==", "~=", "<=", ">=", "..", "::"):
            tokens.append(("other", text[i:i + 2], i, i + 2))
            i += 2
        elif ch in "()[]{}.,:;=":
            tokens.append(("punct", ch, i, i + 1))
            i += 1
        else:
            tokens.append(("other", ch, i, i + 1))
            i += 1
    return tokens


def _unquote_lua_string(raw):
    if raw.startswith("["):
        open_end = raw.find("[", 1) + 1
        eq = open_end - 2
        inner = raw[open_end:len(raw) - (2 + eq)]
        if inner.startswith("\r\n"):
            inner = inner[2:]
        elif inner.startswith("\n"):
            inner = inner[1:]
        return inner
    inner = raw[1:-1]
    escapes = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'"}
    out = []
    i = 0
    while i < len(inner):
        if inner[i] == "\\" and i + 1 < len(inner):
            nxt = inner[i + 1]
            out.append(escapes.get(nxt, nxt))
            i += 2
        else:
            out.append(inner[i])
            i += 1
    return "".join(out)


def _next_nontrivia(tokens, idx):
    n = len(tokens)
    while idx < n and tokens[idx][0] in ("ws", "comment"):
        idx += 1
    return idx


def _prev_nontrivia(tokens, idx):
    while idx >= 0 and tokens[idx][0] in ("ws", "comment"):
        idx -= 1
    return idx


def _scan_balanced_delim(tokens, open_idx):
    open_ch = tokens[open_idx][1]
    stack = [open_ch]
    k = open_idx + 1
    n = len(tokens)
    while k < n:
        kind, val, _, _ = tokens[k]
        if kind == "punct":
            if val in _LUA_DELIM_PAIRS:
                stack.append(val)
            elif val in _LUA_CLOSERS:
                if not stack or _LUA_DELIM_PAIRS[stack[-1]] != val:
                    raise ValueError("Unbalanced Lua delimiters")
                stack.pop()
                if not stack:
                    return k
        k += 1
    raise ValueError("Unbalanced Lua delimiters")


def _is_windaase_module_ref(name):
    return (
        name in ("hypr.windaase", "hypr/windaase")
        or name.startswith("hypr.windaase.")
        or name.startswith("hypr/windaase/")
    )


def _match_require_windaase(tokens, idx):
    """If tokens[idx] is `require` loading 'hypr.windaase', return closing token index."""
    if tokens[idx][0] != "ident" or tokens[idx][1] != "require":
        return None
    j = _next_nontrivia(tokens, idx + 1)
    if j >= len(tokens):
        return None
    if tokens[j][0] == "string":
        return j if _unquote_lua_string(tokens[j][1]) in ("hypr.windaase", "hypr/windaase") else None
    if tokens[j][:2] != ("punct", "("):
        return None
    close_idx = _scan_balanced_delim(tokens, j)
    first = _next_nontrivia(tokens, j + 1)
    if first >= close_idx or tokens[first][0] != "string":
        return None
    if _next_nontrivia(tokens, first + 1) != close_idx:
        return None
    return close_idx if _unquote_lua_string(tokens[first][1]) in ("hypr.windaase", "hypr/windaase") else None


def _consume_setup_chain(tokens, end_idx, require_setup=False):
    j = _next_nontrivia(tokens, end_idx + 1)
    if j >= len(tokens) or tokens[j][0] != "punct" or tokens[j][1] not in (".", ":"):
        if require_setup:
            raise ValueError("Unsupported use of hypr.windaase variable")
        return end_idx
    m = _next_nontrivia(tokens, j + 1)
    if m >= len(tokens) or tokens[m][:2] != ("ident", "setup"):
        raise ValueError("Unsupported field or method on hypr.windaase")
    arg = _next_nontrivia(tokens, m + 1)
    if arg < len(tokens) and tokens[arg][0] == "punct" and tokens[arg][1] in ("(", "{"):
        return _scan_balanced_delim(tokens, arg)
    if arg < len(tokens) and tokens[arg][0] == "string":
        return arg
    raise ValueError("Unsupported arguments to hypr.windaase.setup")


def _assert_statement_prefix(tokens, start_idx):
    prev = _prev_nontrivia(tokens, start_idx - 1)
    if prev < 0:
        return
    kind, val, _, _ = tokens[prev]
    if kind == "other":
        raise ValueError("hypr.windaase appears inside a compound expression")
    if kind == "punct" and val in _LUA_EXPR_PREFIX_PUNCT:
        raise ValueError("hypr.windaase appears inside a compound expression")
    if kind == "ident" and val in _LUA_EXPR_PREFIX_KW:
        raise ValueError("hypr.windaase appears inside a compound expression")


def _finish_statement_span(tokens, end_idx):
    nxt = _next_nontrivia(tokens, end_idx + 1)
    if nxt < len(tokens) and tokens[nxt][:2] == ("punct", ";"):
        end_idx = nxt
        nxt = _next_nontrivia(tokens, nxt + 1)
    if nxt < len(tokens):
        kind, val, _, _ = tokens[nxt]
        if kind == "other":
            raise ValueError("hypr.windaase statement has trailing operator")
        if kind == "punct" and val in _LUA_EXPR_SUFFIX_PUNCT:
            raise ValueError("hypr.windaase statement has trailing punctuation")
        if kind == "ident" and val in _LUA_BINARY_KW:
            raise ValueError("hypr.windaase statement has trailing logical operator")
    return end_idx


def _apply_lua_removals(text, tokens, token_spans):
    char_spans = sorted((tokens[s][2], tokens[e][3]) for s, e in token_spans)
    if not char_spans:
        return text

    banner_re = re.compile(r"^[ \t]*--\s*Omarchy-wind[åa]se\b[^\r\n]*\r?$")
    out = []
    cursor = 0
    for start_c, end_c in char_spans:
        if start_c < cursor:
            continue
        line_start = text.rfind("\n", cursor, start_c) + 1 if text.rfind("\n", cursor, start_c) != -1 else cursor
        prefix_same_line = text[line_start:start_c]
        nl_after = text.find("\n", end_c)
        line_end = nl_after if nl_after != -1 else len(text)
        suffix_same_line = text[end_c:line_end]

        if prefix_same_line.strip(" \t\r") == "" and suffix_same_line.strip(" \t\r") == "":
            cut_start = line_start
            prev_nl = cut_start - 1
            if prev_nl >= cursor and text[prev_nl] == "\n":
                prev_start = text.rfind("\n", cursor, prev_nl)
                prev_start = prev_start + 1 if prev_start != -1 else cursor
                if banner_re.match(text[prev_start:prev_nl]):
                    cut_start = prev_start

            cut_end = line_end + (1 if nl_after != -1 else 0)
            while cut_end < len(text) and text[cut_end] in "\r\n":
                before_tail = ("".join(out[-2:] + [text[cursor:cut_start]])).replace("\r\n", "\n")
                before_ends_blank = before_tail.endswith("\n\n") or cut_start == 0
                if not before_ends_blank:
                    break
                cut_end += 1

            out.append(text[cursor:cut_start])
            cursor = cut_end
        else:
            cut_end = end_c
            while cut_end < line_end and text[cut_end] in " \t":
                cut_end += 1
            out.append(text[cursor:start_c])
            cursor = cut_end

    out.append(text[cursor:])
    result = "".join(out)
    stripped = result.rstrip(" \t\r\n")
    eol = "\r\n" if "\r\n" in text else "\n"
    return (stripped + eol) if stripped else ""


def _luac_validates(text):
    luac = shutil.which("luac")
    if not luac:
        return True
    try:
        res = subprocess.run([luac, "-p", "-"], input=text, text=True, capture_output=True, check=False, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return res.returncode == 0


def strip_hyprland_loader(text):
    """Remove standalone hypr.windaase loader/setup statements while preserving valid Lua."""
    tokens = tokenize_lua(text)
    spans = []
    local_vars = {}
    taken = set()
    n = len(tokens)
    i = 0

    while i < n:
        kind, val, _, _ = tokens[i]
        if kind == "ident" and val == "local":
            v = _next_nontrivia(tokens, i + 1)
            eq = _next_nontrivia(tokens, v + 1) if v < n else n
            req = _next_nontrivia(tokens, eq + 1) if eq < n else n
            if (
                v < n
                and tokens[v][0] == "ident"
                and tokens[v][1] not in _LUA_KEYWORDS
                and eq < n
                and tokens[eq][:2] == ("punct", "=")
                and req < n
            ):
                req_end = _match_require_windaase(tokens, req)
                if req_end is not None:
                    _assert_statement_prefix(tokens, i)
                    end_idx = _consume_setup_chain(tokens, req_end, require_setup=False)
                    stmt_end = _finish_statement_span(tokens, end_idx)
                    local_vars[tokens[v][1]] = True
                    spans.append((i, stmt_end))
                    taken.update(range(i, stmt_end + 1))
                    i = stmt_end + 1
                    continue

        if kind == "ident" and val == "require" and i not in taken:
            req_end = _match_require_windaase(tokens, i)
            if req_end is not None:
                _assert_statement_prefix(tokens, i)
                end_idx = _consume_setup_chain(tokens, req_end, require_setup=False)
                stmt_end = _finish_statement_span(tokens, end_idx)
                spans.append((i, stmt_end))
                taken.update(range(i, stmt_end + 1))
                i = stmt_end + 1
                continue
        i += 1

    if local_vars:
        i = 0
        while i < n:
            if i in taken:
                i += 1
                continue
            kind, val, _, _ = tokens[i]
            if kind == "ident" and val in local_vars:
                prev = _prev_nontrivia(tokens, i - 1)
                if prev >= 0 and tokens[prev][0] == "punct" and tokens[prev][1] in (".", ":"):
                    i += 1
                    continue
                _assert_statement_prefix(tokens, i)
                end_idx = _consume_setup_chain(tokens, i, require_setup=True)
                stmt_end = _finish_statement_span(tokens, end_idx)
                spans.append((i, stmt_end))
                taken.update(range(i, stmt_end + 1))
                i = stmt_end + 1
                continue
            i += 1

    # Fail closed if an unparsed hypr.windaase module reference exists outside comments.
    for idx, (kind, raw, _, _) in enumerate(tokens):
        if idx in taken or kind == "comment":
            continue
        if kind == "string" and _is_windaase_module_ref(_unquote_lua_string(raw)):
            raise ValueError("Found unsupported hypr.windaase reference; refusing partial edit")

    orig_valid = _luac_validates(text)
    cleaned = _apply_lua_removals(text, tokens, spans)
    if orig_valid and not _luac_validates(cleaned):
        raise ValueError("Cleaned Lua failed syntax validation (luac -p)")
    return cleaned


def cmd_strip_hyprland_loader(args):
    if len(args) != 1:
        raise ValueError("Expected <path> for strip-hyprland-loader")
    path = args[0]
    with open(path, "r", encoding="utf-8", newline="") as handle:
        original = handle.read()
    cleaned = strip_hyprland_loader(original)
    if cleaned != original:
        atomic_write(path, cleaned)
