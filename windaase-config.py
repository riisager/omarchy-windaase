#!/usr/bin/env python3
"""Atomic configuration helper for Omarchy-windåse."""

import glob
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
    "snap_assist",
    "snap_resize",
    "ultrawide_layout",
    "soft_maximize",
    "auto_raise",
    "hover_scroll",
    "shortcuts",
    "alt_tab",
)

NAUTILUS_EXT_MARKER = "# Managed by Omarchy-windåse (riisager.windaase)"

TWO_LINE_CLOCK_FORMAT = "HH:mm\ndd-MM-yyyy"
DEFAULT_CLOCK_FORMAT = "dddd HH:mm"

CHROMIUM_BROWSER_SUBDIRS = {
    "google-chrome": ".config/google-chrome",
    "chromium": ".config/chromium",
    "brave-browser": ".config/BraveSoftware/Brave-Browser",
    "brave": ".config/BraveSoftware/Brave-Browser",
    "vivaldi-stable": ".config/vivaldi",
    "vivaldi": ".config/vivaldi",
    "vivaldi-snapshot": ".config/vivaldi-snapshot",
    "microsoft-edge": ".config/microsoft-edge",
    "microsoft-edge-stable": ".config/microsoft-edge",
    "microsoft-edge-beta": ".config/microsoft-edge-beta",
    "microsoft-edge-dev": ".config/microsoft-edge-dev",
}
GECKO_BROWSER_SUBDIRS = {
    "firefox": (".mozilla/firefox", ".config/mozilla/firefox"),
    "org.mozilla.firefox": (".mozilla/firefox", ".config/mozilla/firefox"),
    "firefox-developer-edition": (".mozilla/firefox", ".config/mozilla/firefox"),
    "firefox-nightly": (".mozilla/firefox", ".config/mozilla/firefox"),
    "zen": (".zen",),
    "zen-browser": (".zen",),
    "zen-beta": (".zen",),
    "zen-alpha": (".zen",),
    "zen-twilight": (".zen",),
    "app.zen_browser.zen": (".zen",),
    "io.github.zen_browser.zen": (".zen",),
}
MAX_SESSION_BYTES = 4 * 1024 * 1024
INCOGNITO_RE = re.compile(
    r"[\[(](?:incognito|inkognito|inprivate|guest|gæst|private(?:\s+browsing)?|privat\s+(?:browsing|vindue))[\])]"
    r"|(?:^|[-\u2013\u2014]\s+)(?:InPrivate|(?:(?:Mozilla\s+Firefox|Zen(?:\s+Browser)?)\s+)?(?:Private\s+Browsing|Privat\s+(?:browsing|vindue)))\b",
    re.IGNORECASE,
)
BROWSER_SUFFIX_RE = re.compile(
    r"\s+[-\u2013\u2014]\s+(?:Google Chrome|Chromium|Brave(?:\s+Browser)?|Vivaldi|Microsoft\u200b?\s+Edge(?:\s+(?:Beta|Dev|Canary))?|Mozilla Firefox|Firefox(?:\s+(?:Developer Edition|Nightly))?|Zen(?:\s+Browser)?)\s*$",
    re.IGNORECASE,
)
EDGE_MORE_PAGES_RE = re.compile(r"\s+(?:and\s+\d+\s+more\s+pages?|og\s+\d+\s+flere\s+sider?)\s*$", re.IGNORECASE)
UNREAD_PREFIX_RE = re.compile(r"^(?:\(\d+\)|[•●])\s+")
GENERIC_BROWSER_TITLES = frozenset({
    "new tab",
    "ny fane",
    "untitled",
    "unavngivet",
    "about:blank",
    "google chrome",
    "chromium",
    "brave",
    "vivaldi",
    "microsoft edge",
    "edge",
    "firefox",
    "zen",
    "zen browser",
})


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


def _normalize_address(raw_addr):
    s = str(raw_addr or "").strip()
    m = re.fullmatch(r"(?:0[xX])?([0-9a-fA-F]{1,20})", s)
    return ("0x" + m.group(1).lower()) if m else ""


def _is_valid_profile_dir(name):
    if not isinstance(name, str):
        return False
    trimmed = name.strip()
    if not trimmed or len(trimmed) > 64 or trimmed in (".", ".."):
        return False
    if re.search(r"[/\\\x00-\x1f\x7f]", name):
        return False
    return True


def _strip_edge_profile_segment(text, profile_names_lower=None):
    m = re.match(r"^(.*?)\s+[-\u2013\u2014]\s+([^\-\u2013\u2014]+)$", text)
    if not m:
        return text, ""
    head, tail = m.group(1).strip(), m.group(2).strip()
    if profile_names_lower is not None and tail.lower() not in profile_names_lower:
        return text, ""
    return head, tail


def _browser_title_candidates(title, initial_title, profile_names_lower=None):
    out = []
    seen = set()

    def add(val):
        text = str(val or "").strip()
        if len(text) < 3 or text.lower() in GENERIC_BROWSER_TITLES:
            return
        if text not in seen:
            seen.add(text)
            out.append(text)

    for raw in (title, initial_title):
        clean_title = BROWSER_SUFFIX_RE.sub("", str(raw or "")).strip()
        add(clean_title)
        unread_stripped = UNREAD_PREFIX_RE.sub("", clean_title).strip()
        if unread_stripped != clean_title:
            add(unread_stripped)
        if profile_names_lower:
            no_prof, _ = _strip_edge_profile_segment(unread_stripped, profile_names_lower)
            if no_prof != unread_stripped:
                add(no_prof)
            no_pages = EDGE_MORE_PAGES_RE.sub("", no_prof).strip()
            if no_pages != no_prof:
                add(no_pages)
        else:
            no_pages = EDGE_MORE_PAGES_RE.sub("", unread_stripped).strip()
            if no_pages != unread_stripped:
                add(no_pages)
    return out


def _read_tail_bytes(path, max_bytes=MAX_SESSION_BYTES):
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            if size > max_bytes:
                handle.seek(-max_bytes, os.SEEK_END)
            else:
                handle.seek(0)
            return handle.read()
    except OSError:
        return b""


def _load_chromium_context(base_dir):
    state_path = os.path.join(base_dir, "Local State")
    if not os.path.isfile(state_path):
        return None
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            parsed = json.load(handle)
    except (OSError, ValueError):
        return None

    prof_obj = parsed.get("profile") if isinstance(parsed, dict) else None
    info_cache = prof_obj.get("info_cache") if isinstance(prof_obj, dict) else None
    if not isinstance(info_cache, dict):
        return None

    profiles = {}
    for pdir, info in info_cache.items():
        if pdir in ("System Profile", "Guest Profile") or not _is_valid_profile_dir(pdir):
            continue
        if not isinstance(info, dict):
            continue
        if info.get("is_ephemeral") is True or info.get("is_omitted_from_profile_list") is True:
            continue

        raw_name = info.get("name") or info.get("shortcut_name") or info.get("gaia_name") or pdir
        name = re.sub(r"[\r\n\t]+", " ", str(raw_name)).strip()[:64] or pdir
        initial = (name[0].upper() if name else "?") or "?"

        pic_file = ""
        for pic_key in ("gaia_picture_file_name", "edge_picture_file_name", "avatar_picture_file_name"):
            cand_pic = str(info.get(pic_key) or "").strip()
            if cand_pic:
                pic_file = cand_pic
                break

        picture_path = ""
        if _is_valid_profile_dir(pic_file):
            candidate_pic = os.path.join(base_dir, pdir, pic_file)
            if os.path.isfile(candidate_pic):
                picture_path = candidate_pic
        elif not pic_file:
            edge_pic = os.path.join(base_dir, pdir, "Edge Profile Picture.png")
            if os.path.isfile(edge_pic):
                picture_path = edge_pic

        try:
            active_time = float(info.get("active_time") or 0.0)
        except (TypeError, ValueError):
            active_time = 0.0

        profiles[pdir] = {
            "dir": pdir,
            "name": name,
            "initial": initial,
            "picturePath": picture_path,
            "active_time": active_time,
            "blobs": None,
        }

    # Only tag browsers when the user has 2+ configured profiles.
    if len(profiles) < 2:
        return None

    last_used = str(prof_obj.get("last_used") or "")
    raw_active = prof_obj.get("last_active_profiles")
    active_list = [p for p in (raw_active if isinstance(raw_active, list) else []) if p in profiles]

    name_map = {}
    for prof in profiles.values():
        name_map.setdefault(prof["name"].lower(), []).append(prof)

    return {
        "base_dir": base_dir,
        "profiles": profiles,
        "name_map": name_map,
        "active_list": active_list,
        "active_set": set(active_list),
        "last_used": last_used if last_used in profiles else "",
    }


def _match_chromium_title_profile(title, ctx):
    stripped = BROWSER_SUFFIX_RE.sub("", str(title or "")).strip()
    if not stripped:
        return None
    _, seg = _strip_edge_profile_segment(stripped, None)
    if not seg:
        return None
    matches = ctx["name_map"].get(seg.lower(), [])
    if len(matches) == 1:
        return matches[0]
    return None


def _profile_session_blobs(ctx, pdir):
    prof = ctx["profiles"][pdir]
    if prof["blobs"] is not None:
        return prof["blobs"]
    blobs = []
    sessions_dir = os.path.join(ctx["base_dir"], pdir, "Sessions")
    if os.path.isdir(sessions_dir):
        for prefix in ("Session_*", "Tabs_*"):
            try:
                paths = glob.glob(os.path.join(sessions_dir, prefix))
                paths.sort(key=os.path.getmtime, reverse=True)
            except OSError:
                paths = []
            if paths:
                data = _read_tail_bytes(paths[0])
                if data:
                    blobs.append(data)
    prof["blobs"] = blobs
    return blobs


def _public_profile_payload(prof, confident):
    return {
        "dir": prof["dir"],
        "name": prof["name"],
        "initial": prof["initial"],
        "picturePath": prof["picturePath"],
        "confident": bool(confident),
    }


def _resolve_gecko_profile_path(base_dir, raw_path, is_relative):
    path = str(raw_path or "").strip()
    if not path or re.search(r"[\x00-\x1f\x7f]", path):
        return ""
    if is_relative:
        if path.startswith("/") or "\\" in path:
            return ""
        parts = path.split("/")
        if any(part == ".." for part in parts):
            return ""
        base_real = os.path.realpath(base_dir)
        cand_real = os.path.realpath(os.path.join(base_real, *parts))
        if cand_real != base_real and not cand_real.startswith(base_real + os.sep):
            return ""
        return cand_real
    if not os.path.isabs(path) or ".." in path.split(os.sep):
        return ""
    return os.path.realpath(path)


def _load_gecko_context(home, candidate_subdirs):
    base_dir = ""
    ini_path = ""
    for sub in candidate_subdirs:
        cand_dir = os.path.join(home, sub)
        cand_ini = os.path.join(cand_dir, "profiles.ini")
        if os.path.isfile(cand_ini):
            base_dir = cand_dir
            ini_path = cand_ini
            break
    if not ini_path:
        return None
    try:
        with open(ini_path, "r", encoding="utf-8", errors="ignore") as handle:
            raw = handle.read()
    except OSError:
        return None

    sections = {}
    section_order = []
    current = ""
    for line in raw.splitlines():
        s = line.strip()
        if not s or s[0] in ("#", ";"):
            continue
        sec_m = re.fullmatch(r"\[([^\]]+)\]", s)
        if sec_m:
            current = sec_m.group(1).strip()
            if current not in sections:
                sections[current] = {}
                section_order.append(current)
            continue
        if not current or "=" not in s:
            continue
        k, v = s.split("=", 1)
        sections[current][k.strip().lower()] = v.strip()

    install_defaults = set()
    for sec_name in section_order:
        if re.match(r"^install", sec_name, re.IGNORECASE):
            dval = sections[sec_name].get("default", "")
            if dval:
                install_defaults.add(dval)

    profiles = []
    seen_names = set()
    for sec_name in section_order:
        if not re.match(r"^profile\d*$", sec_name, re.IGNORECASE):
            continue
        sec = sections[sec_name]
        raw_name = re.sub(r"[\r\n\t]+", " ", str(sec.get("name", ""))).strip()[:64]
        raw_path = sec.get("path", "")
        if not raw_name or not _is_valid_profile_dir(raw_name) or raw_name.startswith("-"):
            continue
        is_rel = sec.get("isrelative", "1").strip() != "0"
        prof_path = _resolve_gecko_profile_path(base_dir, raw_path, is_rel)
        if not prof_path:
            continue
        low = raw_name.lower()
        if low in seen_names:
            continue
        seen_names.add(low)
        profiles.append({
            "dir": raw_name,
            "name": raw_name,
            "initial": (raw_name[0].upper() if raw_name else "?") or "?",
            "picturePath": "",
            "profile_path": prof_path,
            "raw_path": raw_path,
            "is_default": (raw_path in install_defaults) or (sec.get("default") == "1"),
        })

    if len(profiles) < 2:
        return None

    # Sort longer paths first for unambiguous prefix matching against open fd symlinks.
    by_path_desc = sorted(profiles, key=lambda p: len(p["profile_path"]), reverse=True)
    by_name = {p["name"]: p for p in profiles}
    by_name_lower = {p["name"].lower(): p for p in profiles}
    return {
        "base_dir": base_dir,
        "profiles": profiles,
        "by_path_desc": by_path_desc,
        "by_name": by_name,
        "by_name_lower": by_name_lower,
    }


def _resolve_gecko_pid_profile(ctx, pid, proc_root="/proc", pid_cache=None):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return None, False
    if pid_cache is not None and pid in pid_cache:
        cached = pid_cache[pid]
        return cached, cached is not None

    matched = None
    proc_dir = os.path.join(proc_root, str(pid))

    cmdline_path = os.path.join(proc_dir, "cmdline")
    try:
        with open(cmdline_path, "rb") as handle:
            raw_args = handle.read().split(b"\x00")
        args = [a.decode("utf-8", errors="ignore") for a in raw_args if a]
    except OSError:
        args = []

    idx = 0
    while idx < len(args) and matched is None:
        arg = args[idx]
        prof_arg = None
        path_arg = None
        if arg in ("-P", "--profile-name") and idx + 1 < len(args):
            prof_arg = args[idx + 1]
            idx += 1
        elif arg.startswith("--profile-name="):
            prof_arg = arg.split("=", 1)[1]
        elif arg == "--profile" and idx + 1 < len(args):
            path_arg = args[idx + 1]
            idx += 1
        elif arg.startswith("--profile="):
            path_arg = arg.split("=", 1)[1]

        if prof_arg is not None:
            matched = ctx["by_name"].get(prof_arg) or ctx["by_name_lower"].get(prof_arg.lower())
        elif path_arg:
            real_arg = os.path.realpath(path_arg)
            for prof in ctx["by_path_desc"]:
                if real_arg == prof["profile_path"] or path_arg == prof["raw_path"]:
                    matched = prof
                    break
        idx += 1

    if matched is None:
        fd_dir = os.path.join(proc_dir, "fd")
        try:
            entries = os.listdir(fd_dir)[:512]
        except OSError:
            entries = []
        for entry in entries:
            link_path = os.path.join(fd_dir, entry)
            try:
                target = os.readlink(link_path)
            except OSError:
                continue
            target_real = os.path.realpath(target) if os.path.isabs(target) else target
            for prof in ctx["by_path_desc"]:
                pp = prof["profile_path"]
                if target_real == pp or target_real.startswith(pp + os.sep):
                    matched = prof
                    break
            if matched is not None:
                break

    if pid_cache is not None:
        pid_cache[pid] = matched
    return matched, matched is not None


def resolve_browser_window_profiles(windows, home_dir=None, proc_root="/proc"):
    """Map browser window addresses to profile metadata for multi-profile setups."""
    if not isinstance(windows, list):
        return {}
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    chromium_contexts = {}
    gecko_contexts = {}
    gecko_pid_cache = {}
    resolved = {}

    for win in windows:
        if not isinstance(win, dict):
            continue
        addr = _normalize_address(win.get("address"))
        if not addr:
            continue
        raw_app = str(win.get("appKey") or "").strip().lower()
        if raw_app.endswith(".desktop"):
            raw_app = raw_app[:-8]

        title = str(win.get("title") or "")
        initial_title = str(win.get("initialTitle") or "")
        if INCOGNITO_RE.search(title) or INCOGNITO_RE.search(initial_title):
            continue

        if raw_app in GECKO_BROWSER_SUBDIRS:
            subdirs = GECKO_BROWSER_SUBDIRS[raw_app]
            if subdirs not in gecko_contexts:
                gecko_contexts[subdirs] = _load_gecko_context(home, subdirs)
            gctx = gecko_contexts[subdirs]
            if gctx is None:
                continue
            raw_pid = win.get("pid")
            try:
                pid = int(raw_pid) if raw_pid is not None else 0
            except (TypeError, ValueError):
                pid = 0
            prof, confident = _resolve_gecko_pid_profile(gctx, pid, proc_root=proc_root, pid_cache=gecko_pid_cache)
            if prof is not None:
                resolved[addr] = _public_profile_payload(prof, confident)
            continue

        subdir = CHROMIUM_BROWSER_SUBDIRS.get(raw_app)
        if not subdir:
            continue

        if subdir not in chromium_contexts:
            chromium_contexts[subdir] = _load_chromium_context(os.path.join(home, subdir))
        ctx = chromium_contexts[subdir]
        if ctx is None:
            continue

        profiles = ctx["profiles"]
        best_prof = _match_chromium_title_profile(title, ctx) or _match_chromium_title_profile(initial_title, ctx)
        confident = best_prof is not None

        if best_prof is None:
            candidates = _browser_title_candidates(title, initial_title, ctx["name_map"])
            for cand in candidates:
                n16 = cand.encode("utf-16le", errors="ignore")
                n8 = cand.encode("utf-8", errors="ignore")
                hits = []
                for pdir, prof in profiles.items():
                    best_pos = -1
                    for blob in _profile_session_blobs(ctx, pdir):
                        pos = max(blob.rfind(n16) if n16 else -1, blob.rfind(n8) if n8 else -1)
                        if pos > best_pos:
                            best_pos = pos
                    if best_pos >= 0:
                        hits.append((pdir in ctx["active_set"], best_pos, prof["active_time"], pdir))
                if hits:
                    hits.sort(reverse=True)
                    best_prof = profiles[hits[0][3]]
                    confident = len(hits) == 1
                    break

        if best_prof is None and len(ctx["active_list"]) == 1:
            best_prof = profiles[ctx["active_list"][0]]
            confident = True

        if best_prof is None and win.get("activated") and ctx["last_used"]:
            best_prof = profiles[ctx["last_used"]]
            confident = False

        if best_prof is not None:
            resolved[addr] = _public_profile_payload(best_prof, confident)

    return resolved


def cmd_browser_window_profiles(args):
    if len(args) != 1:
        raise ValueError("Expected <windows_json> for browser-window-profiles")
    try:
        windows = json.loads(args[0])
    except ValueError as exc:
        raise ValueError(f"Invalid windows JSON: {exc}") from exc
    result = resolve_browser_window_profiles(windows)
    sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")


def nautilus_ext_path(home_dir=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    return os.path.join(home, ".local", "share", "nautilus-python", "extensions", "windaase_context_menu.py")


def nautilus_ext_source():
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "nautilus", "windaase_context_menu.py")


def _remove_nautilus_pycache(ext_path):
    cache_dir = os.path.join(os.path.dirname(ext_path), "__pycache__")
    for pyc_path in glob.glob(os.path.join(cache_dir, "windaase_context_menu*.pyc")):
        if not os.path.islink(pyc_path) and os.path.isfile(pyc_path):
            try:
                os.unlink(pyc_path)
            except OSError:
                pass


def cmd_nautilus_menu(args):
    if len(args) != 1 or args[0] not in ("on", "off", "status"):
        raise ValueError("Expected 'on', 'off', or 'status' for nautilus-menu")
    action = args[0]
    dest = nautilus_ext_path()

    if action == "status":
        installed = False
        if not os.path.islink(dest) and os.path.isfile(dest):
            try:
                with open(dest, "r", encoding="utf-8", errors="ignore") as handle:
                    installed = NAUTILUS_EXT_MARKER in handle.read()
            except OSError:
                installed = False
        sys.stdout.write("installed\n" if installed else "not-installed\n")
        return

    if action == "on":
        src = nautilus_ext_source()
        if os.path.islink(src) or not os.path.isfile(src):
            raise FileNotFoundError(f"Missing Nautilus extension source: {src}")
        with open(src, "r", encoding="utf-8") as handle:
            content = handle.read()
        if NAUTILUS_EXT_MARKER not in content:
            raise ValueError(f"Nautilus extension source is missing marker: {src}")

        if os.path.islink(dest):
            raise ValueError(f"Refusing to overwrite symlink at {dest}")
        if os.path.lexists(dest):
            if not os.path.isfile(dest):
                raise ValueError(f"Refusing to overwrite non-file entry at {dest}")
            with open(dest, "r", encoding="utf-8", errors="ignore") as handle:
                if NAUTILUS_EXT_MARKER not in handle.read():
                    raise ValueError(f"Refusing to overwrite unmanaged file at {dest}")

        atomic_write(dest, content)
        os.chmod(dest, 0o644)
        return

    # action == "off"
    if os.path.islink(dest):
        raise ValueError(f"Refusing to remove symlink at {dest}")
    if os.path.lexists(dest):
        if not os.path.isfile(dest):
            raise ValueError(f"Refusing to remove non-file entry at {dest}")
        with open(dest, "r", encoding="utf-8", errors="ignore") as handle:
            if NAUTILUS_EXT_MARKER not in handle.read():
                raise ValueError(f"Refusing to remove unmanaged file at {dest}")
        os.unlink(dest)
    _remove_nautilus_pycache(dest)


def main(argv):
    if len(argv) < 2:
        raise ValueError(
            "Usage: windaase-config.py <bar-height|bar-height-reset|two-line-clock|hypr-set|strip-hyprland-loader|browser-window-profiles|nautilus-menu> ..."
        )
    cmd, rest = argv[1], argv[2:]
    handlers = {
        "bar-height": cmd_bar_height,
        "bar-height-reset": cmd_bar_height_reset,
        "two-line-clock": cmd_two_line_clock,
        "hypr-set": cmd_hypr_set,
        "strip-hyprland-loader": cmd_strip_hyprland_loader,
        "browser-window-profiles": cmd_browser_window_profiles,
        "nautilus-menu": cmd_nautilus_menu,
    }
    handler = handlers.get(cmd)
    if handler is None:
        raise ValueError(f"Unknown subcommand: {cmd}")
    handler(rest)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception as exc:
        print(f"windaase-config: {exc}", file=sys.stderr)
        sys.exit(1)
