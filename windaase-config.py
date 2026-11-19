#!/usr/bin/env python3
"""Atomic configuration helper for Omarchy-windåse."""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HYPR_OPTION_KEYS = (
    "aero_snap",
    "snap_layouts",
    "soft_maximize",
    "auto_raise",
    "hover_scroll",
    "shortcuts",
)

TWO_LINE_CLOCK_FORMAT = "HH:mm\ndd-MM-yyyy"
DEFAULT_CLOCK_FORMAT = "dddd HH:mm"


def atomic_write(path, content):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    mode = None
    if os.path.exists(path):
        mode = os.stat(path).st_mode & 0o777
    fd, tmp_path = tempfile.mkstemp(prefix=".windaase-", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        if mode is not None:
            os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def omarchy_dir():
    home = os.path.expanduser("~")
    return os.path.join(home, ".config", "omarchy")


def cmd_bar_height(args):
    if len(args) != 1 or not re.fullmatch(r"\d+", args[0]):
        raise ValueError("Expected integer bar height between 24 and 64")
    height = int(args[0], 10)
    if height < 24 or height > 64:
        raise ValueError("Bar height must be between 24 and 64")

    path = os.path.join(omarchy_dir(), "shell.toml")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
    else:
        text = ""
    lines = text.splitlines(keepends=True)

    sec_re = re.compile(r"^\s*\[([A-Za-z0-9_-]+)\]\s*(?:#.*)?$")
    key_re = re.compile(r"^(\s*size-horizontal\s*=\s*)([^\r\n#]*)(.*)$")

    in_bar = False
    found_bar = False
    updated = False
    out = []

    for line in lines:
        sec_m = sec_re.match(line)
        if sec_m:
            if in_bar and not updated:
                out.append(f"size-horizontal = {height}\n")
                updated = True
            in_bar = sec_m.group(1) == "bar"
            if in_bar:
                found_bar = True
            out.append(line)
            continue
        if in_bar:
            key_m = key_re.match(line)
            if key_m:
                line_ending = "\n" if line.endswith("\n") else ""
                suffix = key_m.group(3).rstrip("\r\n")
                out.append(f"{key_m.group(1)}{height}{suffix}{line_ending}")
                updated = True
                continue
        out.append(line)

    if in_bar and not updated:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        out.append(f"size-horizontal = {height}\n")
    elif not found_bar:
        if out and out[-1].strip():
            if not out[-1].endswith("\n"):
                out[-1] += "\n"
            out.append("\n")
        out.append(f"[bar]\nsize-horizontal = {height}\n")

    atomic_write(path, "".join(out))


def cmd_bar_height_reset(args):
    if args:
        raise ValueError("bar-height-reset takes no arguments")

    path = os.path.join(omarchy_dir(), "shell.toml")
    if not os.path.exists(path):
        return

    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines(keepends=True)

    sec_re = re.compile(r"^\s*\[([A-Za-z0-9_-]+)\]\s*(?:#.*)?$")
    key_re = re.compile(r"^\s*size-horizontal\s*=")

    blocks = []
    current_name = None
    current_header = ""
    current_body = []

    for line in lines:
        sec_m = sec_re.match(line)
        if sec_m:
            blocks.append((current_name, current_header, current_body))
            current_name = sec_m.group(1)
            current_header = line
            current_body = []
        else:
            current_body.append(line)
    blocks.append((current_name, current_header, current_body))

    out = []
    for name, header, body in blocks:
        if name == "bar":
            filtered = [line for line in body if not key_re.match(line)]
            has_keys = any(line.strip() and not line.lstrip().startswith("#") for line in filtered)
            if not has_keys:
                continue
            out.append(header)
            out.extend(filtered)
        else:
            if header:
                out.append(header)
            out.extend(body)

    result = "".join(out)
    if not result.strip():
        os.unlink(path)
        return

    result = re.sub(r"\n{3,}", "\n\n", result.lstrip("\n"))
    if not result.endswith("\n"):
        result += "\n"
    atomic_write(path, result)


def cmd_two_line_clock(args):
    if len(args) != 1 or args[0] not in ("on", "off"):
        raise ValueError("Expected 'on' or 'off' for two-line-clock")
    fmt = TWO_LINE_CLOCK_FORMAT if args[0] == "on" else DEFAULT_CLOCK_FORMAT

    path = os.path.join(omarchy_dir(), "shell.json")
    if not os.path.exists(path):
        raise FileNotFoundError(f"Missing shell config: {path}")

    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)

    layout = data.get("bar", {}).get("layout", {})
    if isinstance(layout, dict):
        for items in layout.values():
            if not isinstance(items, list):
                continue
            for entry in items:
                if isinstance(entry, dict) and entry.get("id") == "omarchy.clock":
                    entry["format"] = fmt

    atomic_write(path, json.dumps(data, indent=2) + "\n")


def cmd_hypr_set(args):
    no_reload = False
    pos_args = []
    for arg in args:
        if arg == "--no-reload":
            no_reload = True
        else:
            pos_args.append(arg)

    if len(pos_args) != 2:
        raise ValueError("Expected <key> <true|false> [--no-reload]")
    key, raw_val = pos_args
    if key not in HYPR_OPTION_KEYS:
        raise ValueError(f"Unsupported Hyprland option: {key}")
    if raw_val not in ("true", "false"):
        raise ValueError(f"Expected 'true' or 'false', got: {raw_val}")
    val = raw_val == "true"

    path = os.path.join(omarchy_dir(), "windaase.json")
    data = {}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as handle:
                loaded = json.load(handle)
                if isinstance(loaded, dict):
                    data = loaded
        except (OSError, ValueError):
            data = {}

    data[key] = val
    atomic_write(path, json.dumps(data, indent=2) + "\n")

    if not no_reload:
        subprocess.run(["hyprctl", "reload"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


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
    res = subprocess.run([luac, "-p", "-"], input=text, text=True, capture_output=True, check=False)
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


def main(argv):
    if len(argv) < 2:
        raise ValueError(
            "Usage: windaase-config.py <bar-height|bar-height-reset|two-line-clock|hypr-set|strip-hyprland-loader> ..."
        )
    cmd, rest = argv[1], argv[2:]
    if cmd == "bar-height":
        cmd_bar_height(rest)
    elif cmd == "bar-height-reset":
        cmd_bar_height_reset(rest)
    elif cmd == "two-line-clock":
        cmd_two_line_clock(rest)
    elif cmd == "hypr-set":
        cmd_hypr_set(rest)
    elif cmd == "strip-hyprland-loader":
        cmd_strip_hyprland_loader(rest)
    else:
        raise ValueError(f"Unknown subcommand: {cmd}")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception as exc:
        print(f"windaase-config: {exc}", file=sys.stderr)
        sys.exit(1)
