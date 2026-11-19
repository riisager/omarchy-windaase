#!/usr/bin/env python3
"""Atomic configuration helper for Omarchy-windåse."""

import json
import os
import re
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
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
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


def main(argv):
    if len(argv) < 2:
        raise ValueError("Usage: windaase-config.py <bar-height|bar-height-reset|two-line-clock|hypr-set> ...")
    cmd, rest = argv[1], argv[2:]
    if cmd == "bar-height":
        cmd_bar_height(rest)
    elif cmd == "bar-height-reset":
        cmd_bar_height_reset(rest)
    elif cmd == "two-line-clock":
        cmd_two_line_clock(rest)
    elif cmd == "hypr-set":
        cmd_hypr_set(rest)
    else:
        raise ValueError(f"Unknown subcommand: {cmd}")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception as exc:
        print(f"windaase-config: {exc}", file=sys.stderr)
        sys.exit(1)
