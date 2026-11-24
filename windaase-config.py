#!/usr/bin/env python3
"""Atomic configuration helper for Omarchy-windåse."""

import contextlib
import fcntl
import glob
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

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


def atomic_write(path, content, mode=None):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    if mode is None and os.path.exists(path) and not os.path.islink(path):
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


def omarchy_dir(home_dir=None):
    home = os.path.abspath(os.path.expanduser(home_dir)) if home_dir else os.path.expanduser("~")
    return os.path.join(home, ".config", "omarchy")


@contextlib.contextmanager
def config_lock(home_dir=None):
    cfg_dir = omarchy_dir(home_dir=home_dir)
    os.makedirs(cfg_dir, exist_ok=True)
    lock_path = os.path.join(cfg_dir, ".windaase.lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


def cmd_bar_height(args):
    if len(args) != 1 or not re.fullmatch(r"\d+", args[0]):
        raise ValueError("Expected integer bar height between 24 and 64")
    height = int(args[0], 10)
    if height < 24 or height > 64:
        raise ValueError("Bar height must be between 24 and 64")

    with config_lock():
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

    with config_lock():
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

    with config_lock():
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

    with config_lock():
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
        try:
            subprocess.run(
                ["hyprctl", "reload"],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
        except (OSError, subprocess.TimeoutExpired):
            pass


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

        with config_lock():
            if os.path.islink(dest):
                raise ValueError(f"Refusing to overwrite symlink at {dest}")
            if os.path.lexists(dest):
                if not os.path.isfile(dest):
                    raise ValueError(f"Refusing to overwrite non-file entry at {dest}")
                with open(dest, "r", encoding="utf-8", errors="ignore") as handle:
                    if NAUTILUS_EXT_MARKER not in handle.read():
                        raise ValueError(f"Refusing to overwrite unmanaged file at {dest}")

            atomic_write(dest, content, mode=0o644)
        return

    # action == "off"
    with config_lock():
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


MONITORS_BLOCK_BEGIN = "-- BEGIN OMARCHY-WINDAASE MONITORS"
MONITORS_BLOCK_END = "-- END OMARCHY-WINDAASE MONITORS"
CONNECTOR_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
MODE_STRING_RE = re.compile(r"^(\d{3,5})x(\d{3,5})(?:@(\d+(?:\.\d+)?))?$")


def monitors_profiles_path(home_dir=None):
    return os.path.join(omarchy_dir(home_dir=home_dir), "windaase-monitors.json")


def monitors_lua_path(home_dir=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    return os.path.join(home, ".config", "hypr", "monitors.lua")


def monitors_preview_lock_path(runtime_dir=None, home_dir=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    base = (
        runtime_dir
        or os.environ.get("XDG_RUNTIME_DIR")
        or os.environ.get("XDG_CACHE_HOME")
        or os.path.join(home, ".cache")
    )
    return os.path.join(base, "omarchy-windaase-monitor-preview.json")


def is_internal_connector(name):
    return bool(re.match(r"^(?:eDP|LVDS|DSI)(?:-\d+)?$", str(name or "")))


def validate_connector_name(name):
    if not isinstance(name, str) or not CONNECTOR_NAME_RE.fullmatch(name):
        raise ValueError(f"Unsafe monitor connector name: {name!r}")
    return name


def safe_desc_selector(desc):
    text = str(desc or "").strip()
    if not (1 <= len(text) <= 160):
        return ""
    if any(ch in text for ch in ('"', "'", "\\", "\n", "\r", "\t", "\x00", "$", "`")):
        return ""
    return f"desc:{text}"


def validate_output_selector(selector):
    if not isinstance(selector, str):
        raise ValueError("Monitor selector must be a string")
    if selector.startswith("desc:"):
        desc = selector[5:]
        if safe_desc_selector(desc) != selector:
            raise ValueError(f"Unsafe desc monitor selector: {selector!r}")
        return selector
    return validate_connector_name(selector)


def validate_monitor_mode(mode_str):
    raw = str(mode_str or "").strip()
    if not raw or raw.lower() == "preferred":
        return "preferred"
    clean = re.sub(r"(?i)hz$", "", raw).strip()
    m = MODE_STRING_RE.fullmatch(clean)
    if not m:
        raise ValueError(f"Invalid monitor mode: {mode_str!r}")
    w = int(m.group(1), 10)
    h = int(m.group(2), 10)
    if not (320 <= w <= 16384 and 200 <= h <= 16384):
        raise ValueError(f"Monitor mode dimensions out of range: {mode_str!r}")
    if m.group(3):
        hz = float(m.group(3))
        if not math.isfinite(hz) or hz <= 0 or hz > 1000:
            raise ValueError(f"Monitor refresh rate out of range: {mode_str!r}")
        return f"{w}x{h}@{m.group(3)}"
    return f"{w}x{h}"


def dedupe_available_modes(raw_modes):
    if not isinstance(raw_modes, list):
        return []
    out = []
    seen = set()
    for raw in raw_modes:
        if not isinstance(raw, str):
            continue
        clean = re.sub(r"(?i)hz$", "", raw).strip()
        if not MODE_STRING_RE.fullmatch(clean) or "@" not in clean:
            continue
        if clean not in seen:
            seen.add(clean)
            out.append(clean)
    return out


def clean_hypr_scale(scale, width, height):
    req = float(scale)
    w = int(round(float(width)))
    h = int(round(float(height)))
    if not math.isfinite(req) or req <= 0 or w <= 0 or h <= 0:
        raise ValueError(f"Invalid scale parameters: scale={scale!r}, w={width!r}, h={height!r}")
    req = max(0.25, min(8.0, req))
    divisor = math.gcd(w * 120, h * 120)
    if divisor <= 0:
        return round(req, 4)
    units = max(1, min(divisor, int(round(req * 120))))
    while divisor % units != 0:
        units += 1
    return round(units / 120.0, 4)


def _format_scale_str(scale_val):
    val = float(scale_val)
    if not math.isfinite(val) or val <= 0:
        raise ValueError(f"Invalid monitor scale: {scale_val!r}")
    val = max(0.25, min(8.0, val))
    text = f"{round(val, 4):.4f}".rstrip("0").rstrip(".")
    return text or "1"


def format_hl_monitor_call(output, enabled, mode="preferred", x=0, y=0, scale=1.0, transform=0, include_disabled_false=False):
    sel = validate_output_selector(output)
    if not enabled:
        return f'hl.monitor({{ output = "{sel}", disabled = true }})'
    clean_mode = validate_monitor_mode(mode)
    px = int(round(float(x)))
    py = int(round(float(y)))
    if not (-32768 <= px <= 32768 and -32768 <= py <= 32768):
        raise ValueError(f"Monitor position out of range: {x}, {y}")
    tr = int(round(float(transform))) % 4
    scale_str = _format_scale_str(scale)
    dis_part = "disabled = false, " if include_disabled_false else ""
    tr_part = f", transform = {tr}" if tr in (1, 2, 3) else ""
    return f'hl.monitor({{ output = "{sel}", {dis_part}mode = "{clean_mode}", position = "{px}x{py}", scale = {scale_str}{tr_part} }})'


def is_clamshell_closed(home_dir=None, lid_paths=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    state_flag = os.path.join(home, ".local", "state", "omarchy", "toggles", "hypr", "internal-monitor-clamshell.lua")
    if os.path.exists(state_flag):
        return True
    paths = lid_paths if lid_paths is not None else glob.glob("/proc/acpi/button/lid/*/state")
    for p in paths:
        try:
            with open(p, "r", encoding="utf-8", errors="ignore") as handle:
                if "closed" in handle.read().lower():
                    return True
        except OSError:
            continue
    return False


def resolve_monitor_match_keys(raw_monitors):
    """Assign hardware matchKey values, display numbers (1..N), and a stable dock profileId."""
    filtered = []
    for raw in raw_monitors or []:
        if not isinstance(raw, dict):
            continue
        name = raw.get("name")
        if not name or name == "FALLBACK":
            continue
        if not isinstance(name, str) or not CONNECTOR_NAME_RE.fullmatch(name):
            continue
        mirror_of = raw.get("mirrorOf")
        if mirror_of not in (None, "", "none"):
            continue
        filtered.append(raw)

    desc_counts = {}
    for raw in filtered:
        if is_internal_connector(raw["name"]):
            continue
        dsel = safe_desc_selector(raw.get("description"))
        if dsel:
            desc_counts[dsel] = desc_counts.get(dsel, 0) + 1

    items = []
    for raw in filtered:
        name = raw["name"]
        internal = is_internal_connector(name)
        dsel = "" if internal else safe_desc_selector(raw.get("description"))
        match_key = name if (internal or not dsel or desc_counts.get(dsel, 0) != 1) else dsel
        items.append({
            "raw": raw,
            "name": name,
            "internal": internal,
            "matchKey": match_key,
        })

    items.sort(key=lambda item: (0 if item["internal"] else 1, item["matchKey"], item["name"]))
    for idx, item in enumerate(items, start=1):
        item["number"] = idx

    profile_id = " | ".join(sorted(item["matchKey"] for item in items))
    return items, profile_id


def _load_monitors_db(home_dir=None):
    path = monitors_profiles_path(home_dir=home_dir)
    if not os.path.exists(path):
        return {"profiles": {}}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {"profiles": {}}
    if not isinstance(data, dict) or not isinstance(data.get("profiles"), dict):
        return {"profiles": {}}
    return data


def _save_monitors_db(db, home_dir=None):
    path = monitors_profiles_path(home_dir=home_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    atomic_write(path, json.dumps(db, indent=2, ensure_ascii=False) + "\n")


def _parse_mode_dimensions(mode_str, fallback_w, fallback_h, fallback_hz):
    if mode_str and mode_str != "preferred":
        m = MODE_STRING_RE.fullmatch(mode_str)
        if m:
            w = int(m.group(1), 10)
            h = int(m.group(2), 10)
            hz = float(m.group(3)) if m.group(3) else float(fallback_hz or 60.0)
            return w, h, hz
    return int(fallback_w or 1920), int(fallback_h or 1080), float(fallback_hz or 60.0)


def apply_safety_rules(entries, clamshell_closed):
    """Ensure closed laptops do not force-enable internal screens over externals and never leave 0 displays."""
    if not entries:
        return []
    safe = [dict(e) for e in entries]
    ext_enabled = any(bool(e.get("enabled")) and not is_internal_connector(e.get("name")) for e in safe)
    if clamshell_closed and ext_enabled:
        for e in safe:
            if is_internal_connector(e.get("name")):
                e["enabled"] = False
    if not any(bool(e.get("enabled")) for e in safe):
        target = next((e for e in safe if is_internal_connector(e.get("name"))), safe[0])
        target["enabled"] = True
        target["x"] = 0
        target["y"] = 0
    return safe


def _validate_and_normalize_entries(raw_entries, items_by_key, raw_by_name):
    if not isinstance(raw_entries, list) or not raw_entries:
        raise ValueError("Expected non-empty monitors list")
    parsed = []
    seen_keys = set()
    for entry in raw_entries:
        if not isinstance(entry, dict):
            raise ValueError("Each monitor entry must be an object")
        name = validate_connector_name(entry.get("name", ""))
        item = items_by_key.get(entry.get("matchKey")) or items_by_key.get(name)
        if item is None:
            raise ValueError(f"Unknown or disconnected monitor: {name}")
        mkey = item["matchKey"]
        if mkey in seen_keys:
            raise ValueError(f"Duplicate monitor key in payload: {mkey}")
        seen_keys.add(mkey)

        raw = raw_by_name[item["name"]]
        avail_modes = dedupe_available_modes(raw.get("availableModes") or [])
        fb_w = int(raw.get("width") or 1920)
        fb_h = int(raw.get("height") or 1080)
        fb_hz = float(raw.get("refreshRate") or 60.0)

        enabled = bool(entry.get("enabled", True))
        mode = validate_monitor_mode(entry.get("mode", "preferred"))
        mode_w, mode_h, mode_hz = _parse_mode_dimensions(mode, fb_w, fb_h, fb_hz)
        scale_in = entry.get("scale", raw.get("scale") or 1.0)
        clean_sc = clean_hypr_scale(scale_in, mode_w, mode_h)
        transform = int(round(float(entry.get("transform", raw.get("transform") or 0)))) % 4
        x = int(round(float(entry.get("x", raw.get("x") or 0))))
        y = int(round(float(entry.get("y", raw.get("y") or 0))))
        if not (-32768 <= x <= 32768 and -32768 <= y <= 32768):
            raise ValueError(f"Monitor position out of bounds: {x}, {y}")

        parsed.append({
            "name": item["name"],
            "matchKey": mkey,
            "internal": item["internal"],
            "enabled": enabled,
            "mode": mode,
            "x": x,
            "y": y,
            "scale": clean_sc,
            "transform": transform,
            "width": mode_w,
            "height": mode_h,
            "refreshRate": mode_hz,
            "availableModes": avail_modes,
        })

    for item in items_by_key.values():
        if item["matchKey"] not in seen_keys:
            raw = raw_by_name[item["name"]]
            parsed.append({
                "name": item["name"],
                "matchKey": item["matchKey"],
                "internal": item["internal"],
                "enabled": not bool(raw.get("disabled")),
                "mode": "preferred",
                "x": int(raw.get("x") or 0),
                "y": int(raw.get("y") or 0),
                "scale": float(raw.get("scale") or 1.0),
                "transform": int(raw.get("transform") or 0) % 4,
                "width": int(raw.get("width") or 1920),
                "height": int(raw.get("height") or 1080),
                "refreshRate": float(raw.get("refreshRate") or 60.0),
                "availableModes": dedupe_available_modes(raw.get("availableModes") or []),
            })
            seen_keys.add(item["matchKey"])

    return parsed


def _strip_legacy_monitors_rules(text):
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    n = len(lines)
    monitor_rule_re = re.compile(r'^\s*hl\.monitor\(\{.*output\s*=\s*"([^"]*)"')
    while i < n:
        line = lines[i]
        stripped = line.strip()
        # Strip custom eDP auto-switcher block when migrating pre-Windaase monitors.lua.
        if re.match(r"^\s*local\s+last_edp_pos\s*=", line):
            i += 1
            while i < n:
                if re.match(r'^\s*hl\.on\(\s*"monitor\.removed"', lines[i]):
                    i += 1
                    while i < n and not re.match(r"^\s*end\)\s*$", lines[i]):
                        i += 1
                    i += 1
                    break
                i += 1
            continue
        m = monitor_rule_re.match(line)
        if m and m.group(1) != "" and not stripped.startswith("--"):
            i += 1
            continue
        out.append(line)
        i += 1
    return "".join(out)


def sync_monitors_lua(path, rules, gdk_scale, create_backup=True):
    """Maintain single-line hl.monitor rules and GDK_SCALE inside ~/.config/hypr/monitors.lua."""
    existing = ""
    existed = os.path.exists(path)
    if existed:
        with open(path, "r", encoding="utf-8") as handle:
            existing = handle.read()

    has_block = MONITORS_BLOCK_BEGIN in existing and MONITORS_BLOCK_END in existing
    if existed and create_backup and not has_block:
        bak_path = f"{path}.bak-windaase-{int(time.time())}"
        shutil.copy2(path, bak_path)

    base_text = existing if has_block else _strip_legacy_monitors_rules(existing)
    if has_block:
        block_re = re.compile(
            re.escape(MONITORS_BLOCK_BEGIN) + r".*?" + re.escape(MONITORS_BLOCK_END) + r"[ \t]*\r?\n?",
            re.DOTALL,
        )
        base_text = block_re.sub("", base_text, count=1)

    rule_lines = [
        MONITORS_BLOCK_BEGIN,
        "-- Managed automatically by Omarchy-windaase dock profiles.",
    ]
    ordered_rules = [r for r in rules if bool(r.get("enabled", True))] + [
        r for r in rules if not bool(r.get("enabled", True))
    ]
    for r in ordered_rules:
        sel = r["name"] if is_internal_connector(r["name"]) else r.get("matchKey", r["name"])
        rule_lines.append(
            format_hl_monitor_call(
                sel,
                bool(r.get("enabled", True)),
                mode=r.get("mode", "preferred"),
                x=r.get("x", 0),
                y=r.get("y", 0),
                scale=r.get("scale", 1.0),
                transform=r.get("transform", 0),
                include_disabled_false=False,
            )
        )
    rule_lines.append(MONITORS_BLOCK_END)
    block_text = "\n".join(rule_lines) + "\n"

    gdk_int = max(1, int(gdk_scale))
    gdk_re = re.compile(r"(^\s*local\s+omarchy_gdk_scale\s*=\s*)\d+(.*)$", re.MULTILINE)
    if gdk_re.search(base_text):
        base_text = gdk_re.sub(rf"\g<1>{gdk_int}\g<2>", base_text, count=1)

    catchall_re = re.compile(r'(^\s*hl\.monitor\(\{[^}\n]*output\s*=\s*""[^}\n]*\}\)[ \t]*\r?\n?)', re.MULTILINE)
    m_catch = catchall_re.search(base_text)
    if m_catch:
        pos = m_catch.end()
        prefix = base_text[:pos].rstrip("\n")
        suffix = base_text[pos:].lstrip("\n")
        combined = f"{prefix}\n\n{block_text}\n{suffix}" if suffix else f"{prefix}\n\n{block_text}"
    else:
        gdk_pos = gdk_re.search(base_text)
        if gdk_pos:
            pos = gdk_pos.start()
            prefix = base_text[:pos].rstrip("\n")
            suffix = base_text[pos:]
            combined = f"{prefix}\n\n{block_text}\n{suffix}" if prefix else f"{block_text}\n{suffix}"
        else:
            trimmed = base_text.strip("\n")
            combined = f"{trimmed}\n\n{block_text}" if trimmed else block_text
            if "omarchy_gdk_scale" not in combined:
                combined += f'\nlocal omarchy_gdk_scale = {gdk_int}\nhl.env("GDK_SCALE", tostring(omarchy_gdk_scale))\n'

    combined = re.sub(r"\n{3,}", "\n\n", combined.lstrip("\n"))
    if not combined.endswith("\n"):
        combined += "\n"

    if combined != existing:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        atomic_write(path, combined)
        return True
    return False


def strip_monitors_lua_block(path):
    """Remove the Windaase-managed monitors block from monitors.lua cleanly."""
    if not os.path.exists(path):
        return False
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    if MONITORS_BLOCK_BEGIN not in text or MONITORS_BLOCK_END not in text:
        return False
    block_re = re.compile(
        r"\n?" + re.escape(MONITORS_BLOCK_BEGIN) + r".*?" + re.escape(MONITORS_BLOCK_END) + r"[ \t]*\r?\n?",
        re.DOTALL,
    )
    updated = block_re.sub("\n", text, count=1)
    updated = re.sub(r"\n{3,}", "\n\n", updated.lstrip("\n"))
    if updated and not updated.endswith("\n"):
        updated += "\n"
    if updated != text:
        atomic_write(path, updated)
        return True
    return False


RESCUE_OFFSCREEN_LUA = (
    'local ok, w = pcall(require, "hypr.windaase"); '
    'if ok and w and w.rescue_offscreen_windows then w.rescue_offscreen_windows() end'
)


def _default_hyprctl_monitors():
    res = subprocess.run(["hyprctl", "-j", "monitors", "all"], capture_output=True, text=True, check=True, timeout=5)
    return json.loads(res.stdout)


def _default_hyprctl_eval(expr, ignore_errors=False):
    res = subprocess.run(
        ["hyprctl", "eval", expr],
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    if not ignore_errors and res.returncode != 0:
        detail = (res.stderr or res.stdout or "").strip() or f"exit {res.returncode}"
        raise RuntimeError(f"hyprctl eval failed: {detail}")


def _eval_monitor_entries(entries, hypr_eval=_default_hyprctl_eval, rescue=True):
    enabled_list = [e for e in entries if e.get("enabled")]
    disabled_list = [e for e in entries if not e.get("enabled")]
    for e in enabled_list + disabled_list:
        expr = format_hl_monitor_call(
            e["name"],
            bool(e.get("enabled")),
            mode=e.get("mode", "preferred"),
            x=e.get("x", 0),
            y=e.get("y", 0),
            scale=e.get("scale", 1.0),
            transform=e.get("transform", 0),
            include_disabled_false=True,
        )
        hypr_eval(expr)
    if rescue:
        if hypr_eval is _default_hyprctl_eval:
            _default_hyprctl_eval(RESCUE_OFFSCREEN_LUA, ignore_errors=True)
        else:
            hypr_eval(RESCUE_OFFSCREEN_LUA)


def _compute_gdk_scale(entries):
    scales = [float(e.get("scale") or 1.0) for e in entries if e.get("enabled")]
    min_scale = min(scales) if scales else 1.0
    return max(1, int(min_scale + 0.5))


def build_monitors_status(raw_monitors, home_dir=None, lid_paths=None):
    items, profile_id = resolve_monitor_match_keys(raw_monitors)
    db = _load_monitors_db(home_dir=home_dir)
    saved_profile = db["profiles"].get(profile_id)
    saved_by_key = {}
    if isinstance(saved_profile, dict) and isinstance(saved_profile.get("monitors"), list):
        for sm in saved_profile["monitors"]:
            if isinstance(sm, dict) and sm.get("matchKey"):
                saved_by_key[sm["matchKey"]] = sm

    clamshell = is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths)
    has_ext_enabled = any((not it["internal"]) and (not bool(it["raw"].get("disabled"))) for it in items)

    monitors_out = []
    for it in items:
        raw = it["raw"]
        avail = dedupe_available_modes(raw.get("availableModes") or [])
        w = int(raw.get("width") or 1920)
        h = int(raw.get("height") or 1080)
        hz = float(raw.get("refreshRate") or 60.0)
        live_mode = f"{w}x{h}@{hz:.2f}"
        saved = saved_by_key.get(it["matchKey"])
        mode = "preferred"
        if saved and isinstance(saved.get("mode"), str):
            cand_mode = validate_monitor_mode(saved["mode"])
            if cand_mode != "preferred":
                sw, sh, shz = _parse_mode_dimensions(cand_mode, w, h, hz)
                if sw == w and sh == h and abs(shz - hz) <= 1.0:
                    mode = cand_mode
        enabled = not bool(raw.get("disabled"))
        monitors_out.append({
            "number": it["number"],
            "name": it["name"],
            "matchKey": it["matchKey"],
            "description": str(raw.get("description") or it["name"]),
            "model": str(raw.get("model") or it["name"]),
            "make": str(raw.get("make") or ""),
            "internal": it["internal"],
            "enabled": enabled,
            "clamshellLocked": bool(it["internal"] and clamshell and has_ext_enabled),
            "focused": bool(raw.get("focused")),
            "width": w,
            "height": h,
            "refreshRate": hz,
            "mode": mode,
            "liveMode": live_mode,
            "availableModes": avail,
            "x": int(raw.get("x") or 0),
            "y": int(raw.get("y") or 0),
            "scale": float(raw.get("scale") or 1.0),
            "transform": int(raw.get("transform") or 0) % 4,
        })

    return {
        "profileId": profile_id,
        "profileSaved": saved_profile is not None,
        "clamshellClosed": clamshell,
        "monitors": monitors_out,
    }


def monitors_preview_action(raw_monitors, payload, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    items, _ = resolve_monitor_match_keys(raw_monitors)
    items_by_key = {}
    raw_by_name = {}
    for it in items:
        items_by_key[it["matchKey"]] = it
        items_by_key[it["name"]] = it
        raw_by_name[it["name"]] = it["raw"]

    raw_entries = payload.get("monitors") if isinstance(payload, dict) else payload
    desired = _validate_and_normalize_entries(raw_entries, items_by_key, raw_by_name)
    desired = apply_safety_rules(desired, is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths))

    revert_entries = []
    for it in items:
        raw = it["raw"]
        w = int(raw.get("width") or 1920)
        h = int(raw.get("height") or 1080)
        hz = float(raw.get("refreshRate") or 60.0)
        avail = dedupe_available_modes(raw.get("availableModes") or [])
        cur_mode = f"{w}x{h}@{hz:.2f}"
        pref_mode = avail[0] if avail else cur_mode
        revert_entries.append({
            "name": it["name"],
            "matchKey": it["matchKey"],
            "internal": it["internal"],
            "enabled": not bool(raw.get("disabled")),
            "mode": "preferred" if cur_mode == pref_mode else cur_mode,
            "x": int(raw.get("x") or 0),
            "y": int(raw.get("y") or 0),
            "scale": float(raw.get("scale") or 1.0),
            "transform": int(raw.get("transform") or 0) % 4,
        })

    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    atomic_write(lock_path, json.dumps({
        "expiresAt": time.time() + 20.0,
        "revert": revert_entries,
    }) + "\n")

    _eval_monitor_entries(desired, hypr_eval=hypr_eval, rescue=True)
    return {"ok": True, "revert": revert_entries}


def monitors_commit_action(raw_monitors, payload, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    items, profile_id = resolve_monitor_match_keys(raw_monitors)
    items_by_key = {}
    raw_by_name = {}
    for it in items:
        items_by_key[it["matchKey"]] = it
        items_by_key[it["name"]] = it
        raw_by_name[it["name"]] = it["raw"]

    raw_entries = payload.get("monitors") if isinstance(payload, dict) else payload
    desired = _validate_and_normalize_entries(raw_entries, items_by_key, raw_by_name)
    clamshell = is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths)

    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    if os.path.exists(lock_path) and not os.path.islink(lock_path):
        os.unlink(lock_path)

    with config_lock(home_dir=home_dir):
        db = _load_monitors_db(home_dir=home_dir)
        prev_profile = db["profiles"].get(profile_id)
        prev_by_key = {}
        if isinstance(prev_profile, dict) and isinstance(prev_profile.get("monitors"), list):
            for pm in prev_profile["monitors"]:
                if isinstance(pm, dict) and pm.get("matchKey"):
                    prev_by_key[pm["matchKey"]] = pm

        # Preserve internal panel's open-lid preference while lid is physically closed over externals.
        ext_enabled = any(bool(e["enabled"]) and not e["internal"] for e in desired)
        saved_desired = [dict(e) for e in desired]
        if clamshell and ext_enabled:
            for e in saved_desired:
                if e["internal"]:
                    prev = prev_by_key.get(e["matchKey"])
                    e["enabled"] = bool(prev.get("enabled", True)) if prev else True
        if not any(bool(e["enabled"]) for e in saved_desired):
            target = next((e for e in saved_desired if e["internal"]), saved_desired[0])
            target["enabled"] = True

        runtime_desired = apply_safety_rules(saved_desired, clamshell)

        db["profiles"][profile_id] = {
            "monitors": [
                {
                    "matchKey": e["matchKey"],
                    "name": e["name"],
                    "enabled": bool(e["enabled"]),
                    "mode": e["mode"],
                    "x": int(e["x"]),
                    "y": int(e["y"]),
                    "scale": float(e["scale"]),
                    "transform": int(e["transform"]),
                }
                for e in saved_desired
            ]
        }
        _save_monitors_db(db, home_dir=home_dir)
        sync_monitors_lua(monitors_lua_path(home_dir=home_dir), saved_desired, _compute_gdk_scale(runtime_desired))

    _eval_monitor_entries(runtime_desired, hypr_eval=hypr_eval, rescue=True)
    return {"ok": True, "profileId": profile_id, "profileSaved": True}


def monitors_revert_action(raw_monitors=None, payload=None, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    revert_list = None
    if payload is not None:
        revert_list = payload.get("monitors") if isinstance(payload, dict) else payload
    elif os.path.exists(lock_path):
        try:
            with open(lock_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            if isinstance(data, dict) and isinstance(data.get("revert"), list):
                revert_list = data["revert"]
        except (OSError, ValueError):
            revert_list = None

    if os.path.exists(lock_path) and not os.path.islink(lock_path):
        os.unlink(lock_path)

    if not revert_list or not raw_monitors:
        return {"ok": True, "reverted": False}

    items, _ = resolve_monitor_match_keys(raw_monitors)
    items_by_key = {}
    raw_by_name = {}
    for it in items:
        items_by_key[it["matchKey"]] = it
        items_by_key[it["name"]] = it
        raw_by_name[it["name"]] = it["raw"]

    entries = _validate_and_normalize_entries(revert_list, items_by_key, raw_by_name)
    entries = apply_safety_rules(entries, is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths))
    _eval_monitor_entries(entries, hypr_eval=hypr_eval, rescue=True)
    return {"ok": True, "reverted": True}


def _entry_differs_from_live(desired, raw_live):
    live_enabled = not bool(raw_live.get("disabled"))
    if bool(desired["enabled"]) != live_enabled:
        return True
    if not desired["enabled"]:
        return False
    if int(desired["x"]) != int(raw_live.get("x") or 0):
        return True
    if int(desired["y"]) != int(raw_live.get("y") or 0):
        return True
    if (int(desired["transform"]) % 4) != (int(raw_live.get("transform") or 0) % 4):
        return True
    if abs(float(desired["scale"]) - float(raw_live.get("scale") or 1.0)) > 0.01:
        return True
    if desired["mode"] != "preferred":
        w = int(raw_live.get("width") or 0)
        h = int(raw_live.get("height") or 0)
        hz = float(raw_live.get("refreshRate") or 0.0)
        mw, mh, mhz = _parse_mode_dimensions(desired["mode"], w, h, hz)
        if w != mw or h != mh or abs(hz - mhz) > 1.0:
            return True
    return False


def monitors_apply_action(raw_monitors, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    if os.path.exists(lock_path):
        try:
            with open(lock_path, "r", encoding="utf-8") as handle:
                lock_data = json.load(handle)
            if isinstance(lock_data, dict) and float(lock_data.get("expiresAt", 0)) > time.time():
                return {"ok": True, "skipped": "preview-active"}
        except (OSError, ValueError, TypeError):
            pass

    items, profile_id = resolve_monitor_match_keys(raw_monitors)
    if not items:
        return {"ok": True, "applied": False}

    clamshell = is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths)
    db = _load_monitors_db(home_dir=home_dir)
    saved_profile = db["profiles"].get(profile_id)
    if not isinstance(saved_profile, dict) or not isinstance(saved_profile.get("monitors"), list):
        # Recover if disconnecting a dock left every remaining monitor disabled.
        if all(bool(it["raw"].get("disabled")) for it in items):
            target = next((it for it in items if it["internal"]), items[0])
            raw = target["raw"]
            _eval_monitor_entries(
                [{
                    "name": target["name"],
                    "enabled": True,
                    "mode": "preferred",
                    "x": 0,
                    "y": 0,
                    "scale": float(raw.get("scale") or 1.0),
                    "transform": int(raw.get("transform") or 0) % 4,
                }],
                hypr_eval=hypr_eval,
                rescue=True,
            )
            return {"ok": True, "recovered": True}
        return {"ok": True, "applied": False}

    saved_by_key = {sm["matchKey"]: sm for sm in saved_profile["monitors"] if isinstance(sm, dict) and sm.get("matchKey")}
    desired = []
    for it in items:
        raw = it["raw"]
        sm = saved_by_key.get(it["matchKey"])
        if sm:
            desired.append({
                "name": it["name"],
                "matchKey": it["matchKey"],
                "internal": it["internal"],
                "enabled": bool(sm.get("enabled", True)),
                "mode": validate_monitor_mode(sm.get("mode", "preferred")),
                "x": int(round(float(sm.get("x", 0)))),
                "y": int(round(float(sm.get("y", 0)))),
                "scale": float(sm.get("scale", 1.0)),
                "transform": int(round(float(sm.get("transform", 0)))) % 4,
            })
        else:
            desired.append({
                "name": it["name"],
                "matchKey": it["matchKey"],
                "internal": it["internal"],
                "enabled": not bool(raw.get("disabled")),
                "mode": "preferred",
                "x": int(raw.get("x") or 0),
                "y": int(raw.get("y") or 0),
                "scale": float(raw.get("scale") or 1.0),
                "transform": int(raw.get("transform") or 0) % 4,
            })

    desired = apply_safety_rules(desired, clamshell)
    raw_by_name = {it["name"]: it["raw"] for it in items}
    to_apply = [e for e in desired if _entry_differs_from_live(e, raw_by_name[e["name"]])]
    if to_apply:
        _eval_monitor_entries(to_apply, hypr_eval=hypr_eval, rescue=True)

    # Apply live monitor rules only; writing monitors.lua here triggers Hyprland auto-reloads mid-hotplug.
    return {"ok": True, "applied": len(to_apply) > 0, "profileId": profile_id}


def cmd_monitors_status(args):
    if args:
        raise ValueError("monitors-status takes no arguments")
    raw_monitors = _default_hyprctl_monitors()
    status = build_monitors_status(raw_monitors)
    sys.stdout.write(json.dumps(status, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_preview(args):
    if len(args) != 1:
        raise ValueError("Expected <json> for monitors-preview")
    payload = json.loads(args[0])
    raw_monitors = _default_hyprctl_monitors()
    res = monitors_preview_action(raw_monitors, payload)
    sys.stdout.write(json.dumps(res, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_commit(args):
    if len(args) != 1:
        raise ValueError("Expected <json> for monitors-commit")
    payload = json.loads(args[0])
    raw_monitors = _default_hyprctl_monitors()
    monitors_commit_action(raw_monitors, payload)
    status = build_monitors_status(_default_hyprctl_monitors())
    sys.stdout.write(json.dumps(status, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_revert(args):
    if len(args) > 1:
        raise ValueError("Expected optional <json> for monitors-revert")
    payload = json.loads(args[0]) if len(args) == 1 else None
    raw_monitors = _default_hyprctl_monitors()
    monitors_revert_action(raw_monitors=raw_monitors, payload=payload)
    status = build_monitors_status(_default_hyprctl_monitors())
    sys.stdout.write(json.dumps(status, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_apply(args):
    if args:
        raise ValueError("monitors-apply takes no arguments")
    raw_monitors = _default_hyprctl_monitors()
    res = monitors_apply_action(raw_monitors)
    sys.stdout.write(json.dumps(res, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_strip_monitors_block(args):
    if args:
        raise ValueError("strip-monitors-block takes no arguments")
    with config_lock():
        strip_monitors_lua_block(monitors_lua_path())


def main(argv):
    if len(argv) < 2:
        raise ValueError(
            "Usage: windaase-config.py <bar-height|bar-height-reset|two-line-clock|hypr-set|strip-hyprland-loader|browser-window-profiles|nautilus-menu|monitors-status|monitors-preview|monitors-commit|monitors-revert|monitors-apply|strip-monitors-block> ..."
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
        "monitors-status": cmd_monitors_status,
        "monitors-preview": cmd_monitors_preview,
        "monitors-commit": cmd_monitors_commit,
        "monitors-revert": cmd_monitors_revert,
        "monitors-apply": cmd_monitors_apply,
        "strip-monitors-block": cmd_strip_monitors_block,
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
