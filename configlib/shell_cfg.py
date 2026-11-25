"""Omarchy shell config, bar settings, and floating-only workspace enforcement."""

import glob
import json
import os
import re
import subprocess
import sys

from .common import (
    DEFAULT_CLOCK_FORMAT,
    HYPR_OPTION_KEYS,
    TWO_LINE_CLOCK_FORMAT,
    atomic_write,
    config_lock,
    omarchy_dir,
    state_omarchy_dir,
    workspace_layouts_dir,
)

FLOATING_DEFAULT_LUA = 'o.workspace_mode({ default = "floating" })\n'
DWINDLE_DEFAULT_LUA = 'o.workspace_mode({ default = "dwindle" })\n'


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


def sync_floating_workspace_layouts(ws_id=None, home_dir=None, state_home=None):
    layouts_dir = workspace_layouts_dir(home_dir=home_dir, state_home=state_home)
    os.makedirs(layouts_dir, exist_ok=True)
    default_path = os.path.join(layouts_dir, "default.lua")
    if os.path.islink(default_path):
        raise ValueError(f"Refusing to follow symlink at {default_path}")

    existing_default = ""
    if os.path.isfile(default_path):
        with open(default_path, "r", encoding="utf-8", errors="ignore") as handle:
            existing_default = handle.read()

    default_updated = 'default = "floating"' not in existing_default
    if default_updated:
        atomic_write(default_path, FLOATING_DEFAULT_LUA)

    if ws_id is not None:
        ws_str = str(ws_id).strip()
        if not re.fullmatch(r"[1-9]\d*", ws_str):
            raise ValueError(f"Invalid workspace ID for floating-only enforcement: {ws_id!r}")
        candidates = [os.path.join(layouts_dir, f"{ws_str}.lua")]
    else:
        candidates = sorted(glob.glob(os.path.join(layouts_dir, "[0-9]*.lua")))

    removed = []
    for path in candidates:
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            text = handle.read()
        if 'mode = "floating"' not in text:
            os.unlink(path)
            removed.append(os.path.basename(path))

    return {"defaultUpdated": default_updated, "removed": removed}


def reset_floating_default_layout(home_dir=None, state_home=None):
    layouts_dir = workspace_layouts_dir(home_dir=home_dir, state_home=state_home)
    default_path = os.path.join(layouts_dir, "default.lua")
    if os.path.islink(default_path) or not os.path.isfile(default_path):
        return False
    with open(default_path, "r", encoding="utf-8", errors="ignore") as handle:
        existing_default = handle.read()
    if 'default = "floating"' not in existing_default:
        return False
    atomic_write(default_path, DWINDLE_DEFAULT_LUA)
    return True


def _refresh_workspaces_bar_and_toast(state_home=None, replace_toast=False):
    try:
        subprocess.run(
            ["omarchy-shell", "-q", "omarchy.workspaces", "refresh"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass

    if not replace_toast:
        return

    notif_state = os.path.join(state_omarchy_dir(state_home=state_home), "workspace-layout-notification")
    if os.path.islink(notif_state) or not os.path.isfile(notif_state):
        return
    try:
        with open(notif_state, "r", encoding="utf-8", errors="ignore") as handle:
            last_id = handle.read().strip()
        if not re.fullmatch(r"\d+", last_id):
            return
        msg_res = subprocess.run(
            ["omarchy-i18n", "layout.workspaceFloating"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
        msg = (msg_res.stdout or "").strip() if msg_res.returncode == 0 else ""
        if msg:
            subprocess.run(
                ["omarchy-notification-send", "-p", "-r", last_id, "-g", "󱂬", msg],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
    except (OSError, subprocess.TimeoutExpired):
        pass


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
        if key == "floating_only" and val and not no_reload:
            sync_floating_workspace_layouts()

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
        if key == "floating_only" and val:
            _refresh_workspaces_bar_and_toast(replace_toast=False)


def cmd_enforce_floating_workspace(args):
    if len(args) > 1:
        raise ValueError("Expected optional <workspace_id> for enforce-floating-workspace")
    ws_id = args[0] if len(args) == 1 else None
    with config_lock():
        res = sync_floating_workspace_layouts(ws_id=ws_id)
    _refresh_workspaces_bar_and_toast(replace_toast=True)
    sys.stdout.write(json.dumps(res, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_reset_floating_default(args):
    if args:
        raise ValueError("reset-floating-default takes no arguments")
    with config_lock():
        reset_floating_default_layout()


def _entry_is_plugin(entry, plugin_id):
    return entry == plugin_id or (isinstance(entry, dict) and entry.get("id") == plugin_id)


def cleanup_shell_json_on_uninstall(restore_stock=False, home_dir=None, plugin_id="riisager.windaase"):
    with config_lock(home_dir=home_dir):
        path = os.path.join(omarchy_dir(home_dir=home_dir), "shell.json")
        if os.path.islink(path):
            raise ValueError(f"Refusing to follow symlink at {path}")
        if not os.path.isfile(path):
            return False

        try:
            with open(path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return False

        if not isinstance(data, dict):
            return False

        changed = False
        bar = data.get("bar")
        layout = bar.get("layout") if isinstance(bar, dict) else None
        if isinstance(layout, dict):
            for section, items in list(layout.items()):
                if not isinstance(items, list):
                    continue
                filtered = [e for e in items if not _entry_is_plugin(e, plugin_id)]
                if len(filtered) != len(items):
                    layout[section] = filtered
                    changed = True
                if restore_stock:
                    for entry in layout[section]:
                        if (
                            isinstance(entry, dict)
                            and entry.get("id") == "omarchy.clock"
                            and entry.get("format") == TWO_LINE_CLOCK_FORMAT
                        ):
                            entry["format"] = DEFAULT_CLOCK_FORMAT
                            changed = True

        plugins = data.get("plugins")
        if isinstance(plugins, list):
            filtered_plugins = [e for e in plugins if not _entry_is_plugin(e, plugin_id)]
            if len(filtered_plugins) != len(plugins):
                data["plugins"] = filtered_plugins
                changed = True

        disabled = data.get("disabledPlugins")
        if isinstance(disabled, list):
            drop_ids = {plugin_id}
            if restore_stock:
                drop_ids.add("omarchy.dock")
            filtered_disabled = [e for e in disabled if e not in drop_ids]
            if len(filtered_disabled) != len(disabled):
                data["disabledPlugins"] = filtered_disabled
                changed = True

        if restore_stock and isinstance(bar, dict) and bar.get("position") != "top":
            bar["position"] = "top"
            changed = True

        if changed:
            atomic_write(path, json.dumps(data, indent=2) + "\n")
        return changed


def cmd_uninstall_shell_cleanup(args):
    restore_stock = False
    for arg in args:
        if arg == "--restore-stock":
            restore_stock = True
        else:
            raise ValueError(f"Unexpected argument for uninstall-shell-cleanup: {arg}")
    changed = cleanup_shell_json_on_uninstall(restore_stock=restore_stock)
    sys.stdout.write("updated\n" if changed else "unchanged\n")
