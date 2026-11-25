#!/usr/bin/env python3
"""Atomic configuration helper CLI for Omarchy-windåse."""

import os
import sys

_PLUGIN_DIR = os.path.dirname(os.path.abspath(__file__))
if _PLUGIN_DIR not in sys.path:
    sys.path.insert(0, _PLUGIN_DIR)

from configlib.browsers import (  # noqa: E402
    cmd_browser_window_profiles,
    resolve_browser_window_profiles,
)
from configlib.common import (  # noqa: E402
    HYPR_OPTION_KEYS,
    NAUTILUS_EXT_MARKER,
    atomic_write,
    config_lock,
)
from configlib.lua_strip import (  # noqa: E402
    cmd_strip_hyprland_loader,
    strip_hyprland_loader,
    tokenize_lua,
)
from configlib.monitors import (  # noqa: E402
    MONITORS_BLOCK_BEGIN,
    MONITORS_BLOCK_END,
    apply_safety_rules,
    build_monitors_status,
    cmd_monitors_apply,
    cmd_monitors_commit,
    cmd_monitors_preview,
    cmd_monitors_revert,
    cmd_monitors_status,
    cmd_strip_monitors_block,
    monitors_apply_action,
    monitors_commit_action,
    monitors_lua_path,
    monitors_preview_action,
    monitors_preview_lock_path,
    monitors_profiles_path,
    monitors_revert_action,
    resolve_monitor_match_keys,
    safe_desc_selector,
    strip_monitors_lua_block,
    sync_monitors_lua,
    validate_connector_name,
    validate_monitor_mode,
)
from configlib.nautilus_cfg import cmd_nautilus_menu  # noqa: E402
from configlib.shell_cfg import (  # noqa: E402
    cleanup_shell_json_on_uninstall,
    cmd_bar_height,
    cmd_bar_height_reset,
    cmd_enforce_floating_workspace,
    cmd_hypr_set,
    cmd_reset_floating_default,
    cmd_two_line_clock,
    cmd_uninstall_shell_cleanup,
    reset_floating_default_layout,
    sync_floating_workspace_layouts,
)


def main(argv):
    handlers = {
        "bar-height": cmd_bar_height,
        "bar-height-reset": cmd_bar_height_reset,
        "two-line-clock": cmd_two_line_clock,
        "hypr-set": cmd_hypr_set,
        "enforce-floating-workspace": cmd_enforce_floating_workspace,
        "reset-floating-default": cmd_reset_floating_default,
        "uninstall-shell-cleanup": cmd_uninstall_shell_cleanup,
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
    if len(argv) < 2:
        raise ValueError(f"Usage: windaase-config.py <{'|'.join(handlers)}> ...")
    cmd, rest = argv[1], argv[2:]
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
