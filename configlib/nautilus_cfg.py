"""Opt-in Nautilus context menu extension installer/uninstaller."""

import glob
import os
import sys

from .common import NAUTILUS_EXT_MARKER, atomic_write, config_lock


def nautilus_ext_path(home_dir=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    return os.path.join(home, ".local", "share", "nautilus-python", "extensions", "windaase_context_menu.py")


def nautilus_ext_source():
    plugin_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(plugin_root, "nautilus", "windaase_context_menu.py")


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
